class_name CombatRules
extends RefCounted
## The combat maths, in one place and free of any UI. resolve() rolls everything an attack
## needs and returns an AttackResult; nothing is applied to the units yet.
##
##   To hit:  attacker d20  vs  defender d20. Strictly higher hits; a tie or lower misses.
##   Damage:  (attacker's d20 + Strength) - (defender's d20 + Armour), never below 0.
##            Both d20s are the to-hit rolls. e.g. Wizard rolls 15, Skeleton Minion rolls 10:
##            hit; (15 + 4 STR) - (10 + 1 ARM) = 19 - 11 = 8 damage.
##   Critical: an attacker natural 20 (the die itself, before Strength) always hits, even
##            against a defender 20, and ignores Armour: damage = (20 + Strength) - defender d20.
##   The defender loses that much health and dies at 0 (Unit.take_hit).
##
## To add a stage (e.g. a separate damage die, a parry roll), append another OpposedRoll to
## result.checks and the overlay replays it automatically.


static func resolve(attacker: Unit, defender: Unit) -> AttackResult:
	var result := AttackResult.new(attacker, defender)
	var to_hit := OpposedRoll.roll("To hit", 0, 0, Dice.D20, true)
	result.checks.append(to_hit)
	result.hit = to_hit.attacker_wins()
	result.critical = to_hit.is_critical()
	result.damage_roll = to_hit.attacker_roll
	result.defense_roll = to_hit.defender_roll
	result.strength = attacker.strength
	result.armour = defender.armour
	if result.hit:
		result.damage = maxi(result.attack_total() - result.defense_total(), 0)
	return result
