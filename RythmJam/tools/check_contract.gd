extends SceneTree
## Smoke test for the contract classes. Needs data/news/cat_mayor.tres (see make_cat_mayor.gd).
## From the repo root: godot --headless --path RythmJam --script res://tools/check_contract.gd
## Asserts only run in debug builds (the editor binary is one).


func _init() -> void:
	var comp := Composition.new()
	assert(comp.count_notes() == 0)
	var on := comp.toggle(MusicTypes.Lane.KICK, 0)
	var off := comp.toggle(MusicTypes.Lane.KICK, 0)
	assert(on and not off, "toggle must return the new state")
	comp.set_cell(MusicTypes.Lane.BELLS, MusicTypes.STEP_COUNT - 1, true)
	comp.set_cell(MusicTypes.Lane.SNARE, 4, true)
	assert(comp.is_active(MusicTypes.Lane.BELLS, MusicTypes.STEP_COUNT - 1))
	assert(not comp.is_active(MusicTypes.Lane.BRASS, MusicTypes.STEP_COUNT - 1))
	assert(comp.get_column(4) == [false, true, false, false])
	assert(comp.count_notes() == 2)

	var copy := comp.duplicate_composition()
	copy.clear()
	assert(copy.count_notes() == 0 and comp.count_notes() == 2, "copy must be independent")
	print(comp)

	var news: NewsData = load("res://data/news/cat_mayor.tres")
	var errors := news.validate()
	assert(errors.is_empty(), "cat_mayor: %s" % [errors])
	assert(NewsData.new().validate().size() == 4, "empty news: 3 array size errors + missing track")

	var major := MusicTypes.ScaleType.MAJOR_PENTATONIC
	assert(MusicTypes.degree_to_semitones(major, 0) == 0)
	assert(MusicTypes.degree_to_semitones(major, 4) == 9)
	assert(MusicTypes.degree_to_semitones(major, 5) == 12, "degrees past the table wrap up an octave")
	assert(MusicTypes.degree_to_semitones(major, -1) == -3, "negative degrees go down an octave")
	assert(MusicTypes.degree_to_semitones(major, -5) == -12)
	assert(MusicTypes.degree_to_semitones(MusicTypes.ScaleType.WHOLE_TONE, 7) == 14)
	assert(is_equal_approx(MusicTypes.semitones_to_pitch_scale(12), 2.0))
	assert(is_equal_approx(MusicTypes.semitones_to_pitch_scale(-12), 0.5))
	var far := NewsData.new()
	far.brass_melody.resize(MusicTypes.STEP_COUNT)
	far.brass_melody[0] = 11  # major pentatonic degree 11 = 26 semitones
	assert("melody degree 11 is more than 24 semitones from the root" in far.validate())

	var lane_keys: Array[Key] = [KEY_D, KEY_F, KEY_J, KEY_K]
	for lane in MusicTypes.LANE_COUNT:
		var key := InputMap.action_get_events(MusicTypes.lane_action(lane))[0] as InputEventKey
		assert(key.physical_keycode == lane_keys[lane] and key.keycode == KEY_NONE, "lane %d must be a physical key" % lane)

	print("check_contract: OK")
	quit()
