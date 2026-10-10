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

	assert(MusicTypes.judge(0.0) == MusicTypes.Judgment.PERFECT)
	assert(MusicTypes.judge(-MusicTypes.PERFECT_WINDOW_SEC) == MusicTypes.Judgment.PERFECT, "windows are inclusive, early or late")
	assert(MusicTypes.judge(MusicTypes.GOOD_WINDOW_SEC) == MusicTypes.Judgment.GOOD)
	assert(MusicTypes.judge(-0.12) == MusicTypes.Judgment.BAD)
	assert(MusicTypes.judge(MusicTypes.BAD_WINDOW_SEC + 0.001) == MusicTypes.Judgment.MISS)

	# comp: SNARE on step 4, BELLS on the last step. 2 loops from beat 16, 0.5 s per beat.
	var chart := NoteData.build_chart(comp, 0.5, 16, 2)
	assert(chart.size() == 4)
	for i in chart.size():
		assert(chart[i].index == i, "index = position in the chart")
	assert(chart[0].lane == MusicTypes.Lane.SNARE and is_equal_approx(chart[0].time_sec, 10.0))
	assert(chart[1].lane == MusicTypes.Lane.BELLS and is_equal_approx(chart[1].time_sec, 15.5))
	assert(is_equal_approx(chart[2].time_sec, 18.0), "second loop starts STEP_COUNT beats later")
	var both := Composition.new()
	both.set_cell(MusicTypes.Lane.BELLS, 0, true)
	both.set_cell(MusicTypes.Lane.KICK, 0, true)
	var same_step := NoteData.build_chart(both, 0.5, 0, 1)
	assert(same_step[0].lane == MusicTypes.Lane.KICK and same_step[1].lane == MusicTypes.Lane.BELLS, "same time: lane order")

	var evaluation := CompositionEvaluator.evaluate(comp, news)
	assert(evaluation.has("quality") and evaluation.has("multiplier") and evaluation["comments"] is PackedStringArray)
	assert(CompositionEvaluator.lane_score(6, 4.0) == 1.0, "a 2-cell gap is tolerated")
	assert(CompositionEvaluator.lane_score(0, 4.0) == 0.5, "a 4-cell gap halves the lane score")
	assert(CompositionEvaluator.lane_score(2, 8.0) == 0.0 and CompositionEvaluator.lane_score(16, 4.0) == 0.0)

	# Exactly cat_mayor's 8/4/4/4: kick on even steps, then snare/brass/bells on steps 1/2/3 of each bar.
	var perfect := Composition.new()
	for step in MusicTypes.STEP_COUNT:
		perfect.set_cell(MusicTypes.Lane.KICK, step, step % 2 == 0)
		if step % MusicTypes.STEPS_PER_BAR != 0:
			perfect.set_cell(step % MusicTypes.STEPS_PER_BAR, step, true)
	var best := CompositionEvaluator.evaluate(perfect, news)
	assert(is_equal_approx(best["quality"], 1.0) and is_equal_approx(best["multiplier"], 1.5), "cat_mayor grid: %s" % best)
	var empty := CompositionEvaluator.evaluate(Composition.new(), news)
	assert(empty["quality"] == 0.0 and is_equal_approx(empty["multiplier"], 0.5) and empty["comments"].size() == 1)

	var first_only := Composition.new()
	first_only.set_cell(MusicTypes.Lane.KICK, 0, true)
	var last_only := Composition.new()
	last_only.set_cell(MusicTypes.Lane.BELLS, MusicTypes.STEP_COUNT - 1, true)
	var rule := NewsData.new()
	rule.special_criterion = MusicTypes.SpecialCriterion.VARIETY
	assert(CompositionEvaluator.is_criterion_met(perfect, rule) and not CompositionEvaluator.is_criterion_met(comp, rule))
	rule.special_criterion = MusicTypes.SpecialCriterion.DOWNBEAT_HITS
	assert(CompositionEvaluator.is_criterion_met(perfect, rule) and not CompositionEvaluator.is_criterion_met(comp, rule))
	rule.special_criterion = MusicTypes.SpecialCriterion.FINAL_HIT
	assert(CompositionEvaluator.is_criterion_met(last_only, rule) and not CompositionEvaluator.is_criterion_met(first_only, rule))
	rule.special_criterion = MusicTypes.SpecialCriterion.RISING_DENSITY
	assert(CompositionEvaluator.is_criterion_met(last_only, rule) and not CompositionEvaluator.is_criterion_met(comp, rule), "1 note per half is not rising")
	rule.special_criterion = MusicTypes.SpecialCriterion.SILENCE
	rule.target_density = news.target_density  # 20 notes expected, so at most 15.
	assert(CompositionEvaluator.is_criterion_met(comp, rule) and not CompositionEvaluator.is_criterion_met(perfect, rule))

	var full := Composition.new()
	for lane in MusicTypes.LANE_COUNT:
		for step in MusicTypes.STEP_COUNT:
			full.set_cell(lane, step, true)
	for grid: Composition in [comp, perfect, Composition.new(), first_only, last_only, full]:
		var comments: PackedStringArray = CompositionEvaluator.evaluate(grid, news)["comments"]
		assert(comments.size() >= 1 and comments.size() <= 3 and not comments.has(""), "comments: %s" % comments)

	var config: GameConfig = load("res://data/game_config.tres")
	assert(news in config.news_pool)
	config.news_pool = [news]
	assert(config.draw_news(news) == news, "a single news is drawn again")
	var other := NewsData.new()
	config.news_pool = [news, other]
	for _i in 20:
		assert(config.draw_news(news) == other and config.draw_news(other) == news, "never the previous news when another exists")
	assert(config.draw_news() in config.news_pool)

	# A fresh MusicBus, not the autoload: autoloads may not exist yet in _init of a --script run.
	var bus: Node = load("res://scripts/music/music_bus.gd").new()
	for signal_name in ["game_started", "game_finished", "performance_finished"]:
		assert(bus.has_signal(signal_name), "MusicBus.%s is missing" % signal_name)
	assert(bus.get_current_phase() == MusicTypes.Phase.TITLE and bus.get_current_news() == null, "defaults without a GameManager")
	assert(bus.get_audimat() == 0 and bus.get_song_time() == 0.0, "defaults without a GameManager")
	bus.free()

	var lane_keys: Array[Key] = [KEY_D, KEY_F, KEY_J, KEY_K]
	for lane in MusicTypes.LANE_COUNT:
		var key := InputMap.action_get_events(MusicTypes.lane_action(lane))[0] as InputEventKey
		assert(key.physical_keycode == lane_keys[lane] and key.keycode == KEY_NONE, "lane %d must be a physical key" % lane)

	print("check_contract: OK")
	quit()
