class_name NewsData
extends Resource
## One breaking-news item: what the anchor says and how the game sounds while it plays.
## One .tres per news item in res://data/news/.

## Unique key, e.g. &"cat_mayor".
@export var id: StringName
## Short title shown on screen.
@export var headline: String
## Lines the anchor reads during the performance phase, in order.
@export var anchor_lines: PackedStringArray

## Tempo of the game. One sequencer step = one beat.
@export var bpm: float = 120.0
@export var scale: MusicTypes.ScaleType = MusicTypes.ScaleType.MAJOR_PENTATONIC
## Expected fraction of active steps (0-1) per lane, indexed by MusicTypes.Lane.
@export var target_density: PackedFloat32Array
@export var special_criterion: MusicTypes.SpecialCriterion = MusicTypes.SpecialCriterion.VARIETY

## Loop exactly backing_beats beats long at bpm.
@export var backing_track: AudioStream
## Length of backing_track in beats: a multiple of STEP_COUNT, so every grid starts on the same bar line.
@export var backing_beats: int = MusicTypes.STEP_COUNT
## Scale DEGREE per step (STEP_COUNT values), played when the BRASS cell of that step is on.
## Degrees, not semitones, so a melody can never leave `scale` (see MusicTypes.degree_to_semitones).
@export var brass_melody: PackedInt32Array
## Scale DEGREE per step (STEP_COUNT values), played when the BELLS cell of that step is on.
@export var bells_melody: PackedInt32Array

## Max |pitch shift| of a melody note, in semitones: pitch_scale tops out at 4.0 (2 octaves up),
## and samples sound bad stretched further anyway.
const MAX_MELODY_SEMITONES := 24


## Returns human-readable errors; empty means the resource is usable.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if bpm <= 0.0:
		errors.append("bpm must be > 0 (got %s)" % bpm)
	if target_density.size() != MusicTypes.LANE_COUNT:
		errors.append("target_density needs %d values, one per lane (got %d)" % [MusicTypes.LANE_COUNT, target_density.size()])
	for density in target_density:
		if density < 0.0 or density > 1.0:
			errors.append("target_density values must be within 0-1 (got %s)" % density)
	if brass_melody.size() != MusicTypes.STEP_COUNT:
		errors.append("brass_melody needs %d values, one per step (got %d)" % [MusicTypes.STEP_COUNT, brass_melody.size()])
	if bells_melody.size() != MusicTypes.STEP_COUNT:
		errors.append("bells_melody needs %d values, one per step (got %d)" % [MusicTypes.STEP_COUNT, bells_melody.size()])
	for degree in brass_melody + bells_melody:
		if absi(MusicTypes.degree_to_semitones(scale, degree)) > MAX_MELODY_SEMITONES:
			errors.append("melody degree %d is more than %d semitones from the root" % [degree, MAX_MELODY_SEMITONES])
	if backing_track == null:
		errors.append("backing_track is missing")
	if backing_beats <= 0 or backing_beats % MusicTypes.STEP_COUNT != 0:
		errors.append("backing_beats must be a positive multiple of %d (got %d)" % [MusicTypes.STEP_COUNT, backing_beats])
	return errors
