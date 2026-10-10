class_name CompositionEvaluator
extends RefCounted
## Judges a finished composition against what its news expects (target_density, special_criterion).
## The resulting multiplier scales the performance audimat.

## A lane scores 1 while its note count is within this many cells of its target...
const DENSITY_TOLERANCE_CELLS := 2.0
## ...then falls linearly to 0 at this many cells off.
const DENSITY_ZERO_GAP_CELLS := 6.0
## Share of quality given by the density score (mean of the lane scores)...
const DENSITY_WEIGHT := 0.7
## ...and by the special criterion, all or nothing.
const CRITERION_WEIGHT := 1.0 - DENSITY_WEIGHT
## SILENCE is met with at most this fraction of the expected notes (sum of target_density * STEP_COUNT).
const SILENCE_MAX_RATIO := 0.75
## multiplier = MIN_MULTIPLIER + quality: x0.5 to x1.5. Note count stays out of it, every hit
## already earns audimat during the performance.
const MIN_MULTIPLIER := 0.5
## Minimum quality of each verdict tier, best first. Below VERDICT_FAIR_MIN: the worst verdict.
const VERDICT_TOP_MIN := 0.9
const VERDICT_GOOD_MIN := 0.65
const VERDICT_FAIR_MIN := 0.4

## Player-facing lane names, indexed by MusicTypes.Lane.
const LANE_NAMES := ["grosse caisse", "caisse claire", "cuivres", "cloches"]
## Lane comments: lane name, notes placed, target notes.
const TOO_MANY_COMMENT := "Trop de %s : %d au lieu de %d, le réalisateur s'arrache les cheveux."
const TOO_FEW_COMMENT := "Pas assez de %s : %d sur %d attendues, le plateau s'endort."
## [met, missed] comment per MusicTypes.SpecialCriterion.
const CRITERION_COMMENTS := {
	MusicTypes.SpecialCriterion.VARIETY: [
		"Tout l'orchestre est à l'antenne, la rédaction applaudit.",
		"Une piste est restée en coulisses : la rédaction voulait tout l'orchestre.",
	],
	MusicTypes.SpecialCriterion.DOWNBEAT_HITS: [
		"Chaque mesure tombe pile sur le temps fort, le présentateur hoche la tête.",
		"Des temps forts restés vides : le présentateur cherche le rythme.",
	],
	MusicTypes.SpecialCriterion.FINAL_HIT: [
		"Le coup final claque juste avant la pub, la régie exulte.",
		"Pas de coup final : la séquence s'éteint sans prévenir.",
	],
	MusicTypes.SpecialCriterion.RISING_DENSITY: [
		"Ça monte en puissance jusqu'au bout, le suspense tient l'audience.",
		"Ça ne monte jamais : la deuxième moitié manque de souffle.",
	],
	MusicTypes.SpecialCriterion.SILENCE: [
		"Tout en retenue : le silence laisse parler la news.",
		"Trop chargé : la news réclamait du silence, la régie sature.",
	],
}
const EMPTY_COMMENT := "Écran noir : pas une seule note n'est arrivée en régie."


## Returns {"quality": float 0-1, "multiplier": float, "comments": PackedStringArray}.
## Comments are French, shown to the player: 1 to 3 lines, deterministic.
static func evaluate(composition: Composition, news: NewsData) -> Dictionary:
	# An empty grid would still meet SILENCE and score on low-target lanes.
	if composition.count_notes() == 0:
		return _result(0.0, PackedStringArray([EMPTY_COMMENT]))

	var notes := PackedInt32Array()
	var targets := PackedFloat32Array()
	var density := 0.0
	var worst := 0  # Lane farthest from its target, first one on a tie.
	for lane in MusicTypes.LANE_COUNT:
		notes.append(_count_lane_notes(composition, lane))
		targets.append(news.target_density[lane] * MusicTypes.STEP_COUNT)
		density += lane_score(notes[lane], targets[lane]) / MusicTypes.LANE_COUNT
		if absf(notes[lane] - targets[lane]) > absf(notes[worst] - targets[worst]):
			worst = lane

	var comments := PackedStringArray()
	if lane_score(notes[worst], targets[worst]) < 1.0:
		var template := TOO_MANY_COMMENT if notes[worst] > targets[worst] else TOO_FEW_COMMENT
		comments.append(template % [LANE_NAMES[worst], notes[worst], roundi(targets[worst])])
	var met := is_criterion_met(composition, news)
	comments.append(CRITERION_COMMENTS[news.special_criterion][0 if met else 1])
	var quality := DENSITY_WEIGHT * density + (CRITERION_WEIGHT if met else 0.0)
	comments.append(_verdict(quality))
	return _result(quality, comments)


## Score 0-1 of a lane holding `notes` cells when `target_notes` are expected.
static func lane_score(notes: int, target_notes: float) -> float:
	var gap := absf(notes - target_notes)
	return clampf(remap(gap, DENSITY_TOLERANCE_CELLS, DENSITY_ZERO_GAP_CELLS, 1.0, 0.0), 0.0, 1.0)


static func is_criterion_met(composition: Composition, news: NewsData) -> bool:
	match news.special_criterion:
		MusicTypes.SpecialCriterion.VARIETY:
			for lane in MusicTypes.LANE_COUNT:
				if _count_lane_notes(composition, lane) == 0:
					return false
			return true
		MusicTypes.SpecialCriterion.DOWNBEAT_HITS:
			for step in range(0, MusicTypes.STEP_COUNT, MusicTypes.STEPS_PER_BAR):
				if not composition.get_column(step).has(true):
					return false
			return true
		MusicTypes.SpecialCriterion.FINAL_HIT:
			return composition.get_column(MusicTypes.STEP_COUNT - 1).has(true)
		MusicTypes.SpecialCriterion.RISING_DENSITY:
			var first_half := 0
			var second_half := 0
			for step in MusicTypes.STEP_COUNT:
				var count := composition.get_column(step).count(true)
				if step * 2 < MusicTypes.STEP_COUNT:
					first_half += count
				else:
					second_half += count
			return second_half > first_half
		MusicTypes.SpecialCriterion.SILENCE:
			var expected := 0.0
			for density in news.target_density:
				expected += density * MusicTypes.STEP_COUNT
			return composition.count_notes() <= SILENCE_MAX_RATIO * expected
	return false


static func _count_lane_notes(composition: Composition, lane: int) -> int:
	var count := 0
	for step in MusicTypes.STEP_COUNT:
		if composition.is_active(lane, step):
			count += 1
	return count


static func _verdict(quality: float) -> String:
	if quality >= VERDICT_TOP_MIN:
		return "Verdict : la chaîne tient son nouveau générique."
	if quality >= VERDICT_GOOD_MIN:
		return "Verdict : du solide, le directeur d'antenne valide."
	if quality >= VERDICT_FAIR_MIN:
		return "Verdict : passable, ça ira pour la deuxième partie de soirée."
	return "Verdict : à rediffuser à 3 h du matin, et encore."


static func _result(quality: float, comments: PackedStringArray) -> Dictionary:
	return {"quality": quality, "multiplier": MIN_MULTIPLIER + quality, "comments": comments}
