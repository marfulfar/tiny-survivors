class_name CombatResolver
extends RefCounted
## What the turn logic calls to settle a single-target attack: rolls it (CombatRules) and,
## if there is a presenter, plays the dice duel on screen before returning. Awaitable:
##     var result: AttackResult = await combat.attack(attacker, defender)
## The TacticsController owns one and hands it to EnemyAI, so both sides roll the same way.

## Shows the rolls (a DiceDuelOverlay); null resolves silently.
var presenter: DiceDuelOverlay


func _init(overlay: DiceDuelOverlay = null) -> void:
	presenter = overlay


func attack(attacker: Unit, defender: Unit, show_rolls := true) -> AttackResult:
	var result := CombatRules.resolve(attacker, defender)
	print_verbose(result)
	if show_rolls and presenter:
		await presenter.play(result)
	return result
