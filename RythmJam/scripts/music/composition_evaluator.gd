class_name CompositionEvaluator
extends RefCounted
## Judges a finished composition against what its news expects (target_density, special_criterion).
## The resulting multiplier scales the performance audimat.
# STUB — replaced in phase 2: fixed quality, placeholder comment. Keep the evaluate() signature.

## The multiplier gains +1 per this many notes (the grid holds LANE_COUNT * STEP_COUNT = 64 cells).
const NOTES_PER_BONUS := 32.0
const STUB_QUALITY := 0.5


## Returns {"quality": float 0-1, "multiplier": float, "comments": PackedStringArray}.
## Comments are French, shown to the player.
static func evaluate(composition: Composition, _news: NewsData) -> Dictionary:
	var quality := STUB_QUALITY
	return {
		"quality": quality,
		"multiplier": (1.0 + composition.count_notes() / NOTES_PER_BONUS) * (0.5 + quality),
		"comments": PackedStringArray(["(évaluation à venir)"]),
	}
