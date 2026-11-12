class_name AttackResult
extends RefCounted
## The outcome of one attack, decided before any animation plays: who attacked whom, every
## roll that decided it (in the order they were made) and what it does to the defender.
## Abilities receive this and apply it when the blow lands (Unit.receive_attack).

var attacker: Unit
var defender: Unit
## Opposed rolls in the order they were made; the overlay replays them in this order.
var checks: Array[OpposedRoll] = []
var hit := false
## Natural 20 on the to-hit roll: an automatic hit that ignores the defender's Armour.
var critical := false

## Damage breakdown (see CombatRules):
##   damage = (damage_roll + strength) - (defense_roll + armour), never below 0.
## The attacker's d20 that the damage builds on (today: its to-hit roll).
var damage_roll := 0
## The defender's d20 that its armour adds to (today: its to-hit roll).
var defense_roll := 0
## Attacker's Strength at the time of the attack.
var strength := 0
## Defender's Armour at the time of the attack.
var armour := 0
## Health the defender loses (0 on a miss or when armour soaks it all).
var damage := 0


func _init(from: Unit = null, to: Unit = null) -> void:
	attacker = from
	defender = to


func attack_total() -> int:
	return damage_roll + strength


## The defender's side of the damage sum; a critical leaves Armour out.
func defense_total() -> int:
	return defense_roll if critical else defense_roll + armour


## "(15 + 4 STR) - (10 + 1 ARM) = 19 - 11 = 8"; on a critical "(20 + 4 STR) - (10) = ...".
func damage_text() -> String:
	var defense := "(%d)" % defense_roll if critical else "(%d %s %d ARM)" % [
		defense_roll, "+" if armour >= 0 else "-", absi(armour)]
	return "(%d %s %d STR) - %s = %d - %d = %d" % [
		damage_roll, "+" if strength >= 0 else "-", absi(strength), defense,
		attack_total(), defense_total(), damage]


func _to_string() -> String:
	var parts: PackedStringArray = []
	for c in checks:
		parts.append(str(c))
	return "%s -> %s: %s; damage %s" % [attacker.display_name if attacker else "?",
		defender.display_name if defender else "?", "; ".join(parts),
		damage_text() if hit else "-"]
