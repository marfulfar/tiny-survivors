# Tiny Survivors – project structure

```
assets/                     Imported art only (models, textures, animations). No game logic.
  characters/               kaykit_adventurers/ (models, shared Rig_Medium clip libraries, props)
                            kaykit_skeletons/ (models + weapons; same rig, reuses the clips above)
  effects/                  fireball/
  environment/nature_pack/  models/ (glTF + textures), previews/ (not imported)
  environment/medieval_hexagon/  models/ tiles, buildings (4 team colours + neutral), decoration
  environment/kaykit_forest_nature/  models/ trees, bare trees, bushes, grass, rocks (colour variants)
  environment/quaternius_ultimate_nature/  models/ FBX only (the pack ships no glTF): birch, common,
                                     pine, willow, palm trees in normal/autumn/snow/dead variants,
                                     bushes, cactus, rocks (+moss/snow), stumps, logs, crops
  environment/kaykit_dungeon/        models/ glTF + dungeon_texture.png: walls, floors, doors,
                                     stairs, pillars, barrels, chests, furniture, torches...
  */docs/                   Pack guides and preview images (not imported, .gdignore)
  _unused/                  Kept for reference, ignored by Godot (.gdignore): old procedural
                            wizard, the retired goblin enemy (art + unit scripts)

game/                       Everything that makes up the game, grouped by feature.
  battle/                   The reusable battle rig: battle.tscn = camera + grid + turn controller
                            tactics_controller.gd (turns, input), grid_board.gd (cells, paths,
                            overlays), enemy_ai.gd, camera_rig.gd, battle_markers.gd
  combat/                   Dice and combat rules, no UI: dice.gd (all rule rolls), opposed_roll.gd,
                            attack_result.gd, combat_rules.gd (the maths), combat_resolver.gd
                            (rolls + shows the duel; used by TacticsController and EnemyAI)
  units/                    unit.gd → animated_unit.gd / enemy_unit.gd (shared base classes)
    wizard/  skeleton_minion/  One folder per unit type: scene + script (+ helpers)
    models/                 KayKit character model scenes (mesh + AnimationPlayer + clips)
  effects/                  Projectiles and other spawned effects (fireball/)
  props/                    Interactive map objects (ice_crystal/)
  ui/                       HUD and world-space UI (battle_hud, health bar, AP pips, damage numbers)
  missions/                 One folder per map: <mission>.tscn + its scenery
```

## How the pieces fit

- **Unit** (`game/units/unit.gd`): every unit on the board. Team, health, AP, overhead bars,
  walking a path, facing, `take_hit()`. Teams are groups: `Unit.GROUP_PLAYERS` / `GROUP_ENEMIES`.
- **AnimatedUnit**: a Unit whose model has an AnimationPlayer (KayKit characters). Idle/walk/hit/death.
- **EnemyUnit**: an AnimatedUnit driven by `EnemyAI` on the enemy turn. Attack stats + clip, `attack()`,
  and a corpse that sinks away after death.
- **Attacks** are rolled before they animate. `CombatRules.resolve()` makes the rolls and returns an
  `AttackResult`: to hit, attacker d20 must beat defender d20 (ties miss); damage of a hit =
  (attacker's d20 + `strength`) - (defender's d20 + `armour`), min 0 (same d20s as the to-hit roll). A natural 20 by the attacker is a critical: it always
  hits (even against a 20) and the defender's Armour is left out of the sum. Health 0 = dead. Strength, Armour and
  health are per-unit Inspector stats (Unit > Combat / Stats); abilities have no damage of their own. Single-target attacks go through `CombatResolver.attack()`, which also plays the
  `DiceDuelOverlay` (portraits + d20s); area attacks roll per victim silently. The ability gets the
  result and calls `Unit.receive_attack()` when the blow lands (damage, or a floating "Miss").
  New roll stages (damage vs defense) = append another `OpposedRoll` in `CombatRules`; the overlay
  replays every check in order.
- **Turn hand-over**: at the battle start and every turn change the TacticsController awaits
  `TurnBanner.play()` (`game/ui/turn_banner.gd`): a ~1.4 s band over the top third saying
  "Player's Turn" / "Enemy's Turn", during which input is locked.
- **Battle rig** (`game/battle/battle.tscn`): finds units through their groups, so it needs no paths.
- **Mission** (`game/missions/<name>/<name>.tscn`): map + `Units` + one Battle instance.

## Recipes

- **New mission**: duplicate `game/missions/forest_clearing/`, change ground/scenery, place unit
  scenes under `Units`, set `board_half_extent` on the Battle node. Point `run/main_scene` at it.
- **New player character**: copy `game/units/wizard/`. Use a model from `game/units/models/`,
  extend `AnimatedUnit`, add the character's abilities. Movement and health come for free.
- **New enemy**: copy `game/units/skeleton_minion/`, swap the model scene (`game/units/models/`) and
  weapon, set stats in the Inspector. It uses EnemyAI automatically; override `attack()` if needed.
- **New ability**: today an ability is a method on the unit (`Wizard.shoot_at`) plus an entry in
  `TacticsController._actions_for()`. When there are several, move them into Ability resources.
