class_name OpposedRoll
extends RefCounted
## One contest between two units: each rolls a die (a d20 by default) and adds a bonus.
## The attacking side wins only with a strictly higher total; a tie goes to the defender.
## With can_crit, a natural max roll (a 20 on a d20, before any bonus) is a critical: the
## attacker wins whatever the defender rolled, even another 20.
## An attack is a chain of these (today only "To hit"; later damage vs defense), and the
## DiceDuelOverlay shows each one in turn.

## Shown above the dice in the overlay ("To hit", later "Damage"...).
var label := ""
var sides := Dice.D20
var attacker_roll := 0
var defender_roll := 0
var attacker_bonus := 0
var defender_bonus := 0
## Verdict captions for the overlay.
var success_text := "HIT!"
var fail_text := "MISS"
var critical_text := "CRITICAL HIT!"
## Whether a natural max roll by the attacker is an automatic win (see is_critical).
var can_crit := false


static func roll(check_label: String, attack_bonus := 0, defense_bonus := 0, die := Dice.D20, crits := false) -> OpposedRoll:
	var r := OpposedRoll.new()
	r.label = check_label
	r.sides = die
	r.can_crit = crits
	r.attacker_bonus = attack_bonus
	r.defender_bonus = defense_bonus
	r.attacker_roll = Dice.roll(die)
	r.defender_roll = Dice.roll(die)
	return r


func attacker_total() -> int:
	return attacker_roll + attacker_bonus


func defender_total() -> int:
	return defender_roll + defender_bonus


## The attacker rolled the die's highest face (a natural 20) on a check that allows crits.
func is_critical() -> bool:
	return can_crit and attacker_roll == sides


func attacker_wins() -> bool:
	return is_critical() or attacker_total() > defender_total()


## Equal totals that decided the check (a critical overrides the tie rule).
func is_tie() -> bool:
	return not is_critical() and attacker_total() == defender_total()


func verdict_text() -> String:
	if is_critical():
		return critical_text
	return success_text if attacker_wins() else fail_text


func _to_string() -> String:
	return "%s: %d(+%d) vs %d(+%d) -> %s" % [label, attacker_roll, attacker_bonus,
		defender_roll, defender_bonus, verdict_text()]
