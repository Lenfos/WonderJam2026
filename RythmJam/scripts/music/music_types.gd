class_name MusicTypes
## Shared constants and enums of the music <-> UI contract. Never instantiated.

## Number of sequencer lanes, one per instrument (see Lane).
const LANE_COUNT := 4
## Number of steps in the sequencer grid. One step = one beat at the news bpm.
const STEP_COUNT := 16
## Steps per bar: a downbeat is a step where step % STEPS_PER_BAR == 0. Groups the grid columns.
const STEPS_PER_BAR := 4

## Max |press time - note time|, in seconds, for a PERFECT hit.
const PERFECT_WINDOW_SEC := 0.050
## Max |press time - note time|, in seconds, for a GOOD hit.
const GOOD_WINDOW_SEC := 0.100
## Max |press time - note time|, in seconds, for a BAD hit (multiplier lowered).
## A press with no note this close resets the combo; a note still unhit past it is missed.
const BAD_WINDOW_SEC := 0.150

## Sequencer rows / rhythm-game columns, in display order (keys D F J K).
enum Lane { KICK, SNARE, BRASS, BELLS }

## Result of one note in the rhythm phase.
enum Judgment { PERFECT, GOOD, BAD, MISS }


## Judgment of a press `offset_sec` from its note (press time - note time, early or late).
## Windows are inclusive; MISS past BAD_WINDOW_SEC.
static func judge(offset_sec: float) -> Judgment:
	var distance := absf(offset_sec)
	if distance <= PERFECT_WINDOW_SEC:
		return Judgment.PERFECT
	if distance <= GOOD_WINDOW_SEC:
		return Judgment.GOOD
	if distance <= BAD_WINDOW_SEC:
		return Judgment.BAD
	return Judgment.MISS


## Game flow phase, owned by the GameManager (see MusicBus.phase_changed and docs/CONTRACT.md).
enum Phase { TITLE, NEWS_INTRO, COMPOSITION, COMPOSITION_REVIEW, PERFORMANCE, GAME_OVER }

## Musical scale of a news item (used to build melodies).
enum ScaleType { MAJOR_PENTATONIC, MINOR_PENTATONIC, WHOLE_TONE }

## Semitones per octave.
const OCTAVE := 12
## Pitch of every melodic sample (brass, bells). Melodic samples MUST be tuned exactly to C
## (any octave): playback pitch-shifts by semitone offsets relative to C, so a detuned sample
## puts the whole lane out of tune.
const REFERENCE_NOTE := "C"
## Semitone offsets from the root within one octave, per ScaleType.
const SCALE_OFFSETS := {
	ScaleType.MAJOR_PENTATONIC: [0, 2, 4, 7, 9],
	ScaleType.MINOR_PENTATONIC: [0, 3, 5, 7, 10],
	ScaleType.WHOLE_TONE: [0, 2, 4, 6, 8, 10],
}


## Semitones above REFERENCE_NOTE of a scale degree. Degree 0 = root; degrees past the
## table wrap up an octave (MAJOR_PENTATONIC: 5 -> 12), negative ones go down (-1 -> -3).
static func degree_to_semitones(scale: ScaleType, degree: int) -> int:
	var offsets: Array = SCALE_OFFSETS[scale]
	var index := posmod(degree, offsets.size())
	@warning_ignore("integer_division")
	var octave := (degree - index) / offsets.size()
	return offsets[index] + octave * OCTAVE


## AudioStreamPlayer.pitch_scale that shifts a sample by `semitones`.
static func semitones_to_pitch_scale(semitones: int) -> float:
	return pow(2.0, semitones / float(OCTAVE))

## Bonus rule a news item rewards on top of matching its target densities.
enum SpecialCriterion {
	## Every lane has at least one note.
	VARIETY,
	## Every downbeat (step % STEPS_PER_BAR == 0) has at least one note, any lane.
	DOWNBEAT_HITS,
	## At least one note on the last step.
	FINAL_HIT,
	## Strictly more notes in the second half of the steps than in the first, all lanes combined.
	RISING_DENSITY,
	## Total notes at most CompositionEvaluator.SILENCE_MAX_RATIO of the expected total.
	SILENCE,
}


## InputMap action of a lane: "lane_0".."lane_3", bound in project.godot to PHYSICAL keys D F J K.
static func lane_action(lane: int) -> StringName:
	return StringName("lane_%d" % lane)
