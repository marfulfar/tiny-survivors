class_name Dice
extends RefCounted
## Every game-rule die roll goes through here, so the whole battle can be made repeatable
## (Dice.set_seed) for tests or replays. Purely visual randomness (a die tumbling through
## numbers in the UI) must NOT use this, or it would change the outcome of later rolls.

const D20 := 20

static var _rng: RandomNumberGenerator
## Debug/tests: results handed out (in order) by the next roll() calls instead of random ones.
static var _forced: Array[int] = []


## One roll of an N-sided die: 1..sides.
static func roll(sides := D20) -> int:
	if not _forced.is_empty():
		return clampi(_forced.pop_front(), 1, sides)
	return _get_rng().randi_range(1, sides)


## Makes the next rolls come out as `values` (debug keys, tests).
static func force_next(values: Array[int]) -> void:
	_forced.append_array(values)


## Sum of `count` rolls of an N-sided die (e.g. 2d6 = roll_many(2, 6)).
static func roll_many(count: int, sides: int) -> int:
	var total := 0
	for i in count:
		total += roll(sides)
	return total


static func set_seed(value: int) -> void:
	_get_rng().seed = value


static func _get_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng
