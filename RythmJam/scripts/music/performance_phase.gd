class_name PerformancePhase
extends Node
## Runs the PERFORMANCE phase: a count-in, then the composition replayed loop_count times over the
## backing track as a chart the player plays (keys D F J K). Judges every lane key press against
## the chart and keeps the combo, the audimat and the chaos level. A missed note mutes its lane
## until the next hit on it. Talks to the UI only through MusicBus.
## Ends with MusicBus.performance_finished.

## Audimat of one hit, before the combo and composition multipliers.
const HIT_AUDIMAT := {
	MusicTypes.Judgment.PERFECT: 100,
	MusicTypes.Judgment.GOOD: 50,
	MusicTypes.Judgment.BAD: 10,
}
## Every HITS_PER_COMBO_STEP combo raises the combo multiplier by COMBO_STEP, up to
## MAX_COMBO_MULTIPLIER. A BAD hit takes one step back; a miss or a stray press resets it to 1.
const HITS_PER_COMBO_STEP := 8
const COMBO_STEP := 0.5
const MAX_COMBO_MULTIPLIER := 3.0
## Chaos level change per judged note, the level being clamped to 0-1.
const CHAOS_PER_JUDGMENT := {
	MusicTypes.Judgment.PERFECT: -0.05,
	MusicTypes.Judgment.GOOD: -0.05,
	MusicTypes.Judgment.BAD: 0.05,
	MusicTypes.Judgment.MISS: 0.2,
}

## Shared with the composition phase (siblings in main.tscn).
@export var clock: MusicClock
@export var sequencer: SequencerPlayer
## Times the composition is played.
@export var loop_count: int = 3
## Backing-only beats before the first chart beat, counted down by countdown_beat.
@export var count_in_beats: int = 4
## Seconds taken off every press before judging it. Raise it when every hit reads late (Bluetooth
## headset, web build...), go negative when they read early. Future player latency setting.
@export var input_offset_sec: float = 0.0

var _running := false
var _news: NewsData
## From the composition evaluation, applied to every hit.
var _composition_multiplier := 1.0
## Absolute clock beats: step 0 of the first loop, and the end of the last loop.
var _start_beat := 0
var _end_beat := 0
## Next beat whose countdown_beat is still to be emitted.
var _next_countdown_beat := 0
## Next loop whose anchor line is still to be emitted.
var _next_loop := 0
## Per lane: its chart notes, in time order.
var _lane_notes: Array[Array] = []
## Per lane: index in _lane_notes[lane] of its first note not judged yet.
var _next_note := PackedInt32Array()
var _combo := 0
var _combo_multiplier := 1.0
var _audimat := 0
var _chaos := 0.0


## `multiplier` comes from the composition evaluation.
func start(news: NewsData, composition: Composition, multiplier: float) -> void:
	_news = news
	_composition_multiplier = multiplier
	# The chart starts on a grid boundary so its steps line up with the backing track's bars:
	# the clock starts count_in_beats earlier, near the end of a grid.
	_start_beat = ceili(count_in_beats / float(MusicTypes.STEP_COUNT)) * MusicTypes.STEP_COUNT
	_end_beat = _start_beat + loop_count * MusicTypes.STEP_COUNT
	var count_in_start := _start_beat - count_in_beats
	var beat_length := news.backing_track.get_length() / news.backing_beats
	clock.start(news.backing_track, news.bpm, news.backing_beats, count_in_start * beat_length)
	sequencer.start(clock, news, composition, _start_beat, _end_beat)
	_next_countdown_beat = count_in_start
	_next_loop = 0
	_running = true
	var chart := NoteData.build_chart(composition, clock.get_beat_length(), _start_beat, loop_count)
	_lane_notes.clear()
	for lane in MusicTypes.LANE_COUNT:
		_lane_notes.append(chart.filter(func(note: NoteData) -> bool: return note.lane == lane))
	_next_note.resize(MusicTypes.LANE_COUNT)
	_next_note.fill(0)
	_combo = 0
	_combo_multiplier = 1.0
	_audimat = 0
	_chaos = 0.0
	MusicBus.chaos_level_changed.emit(_chaos)
	MusicBus.combo_changed.emit(_combo, _combo_multiplier)
	MusicBus.audimat_changed.emit(_audimat)
	MusicBus.performance_started.emit(chart, clock.get_beat_time(_start_beat) - clock.get_song_time())


func _process(_delta: float) -> void:
	if not _running:
		return
	# Song time: countdown and anchor text follow what the player hears.
	var song_time := clock.get_song_time()
	while _next_countdown_beat <= _start_beat and song_time >= clock.get_beat_time(_next_countdown_beat):
		MusicBus.countdown_beat.emit(_start_beat - _next_countdown_beat)
		_next_countdown_beat += 1
	if _next_loop < loop_count and song_time >= clock.get_beat_time(_start_beat + _next_loop * MusicTypes.STEP_COUNT):
		if _next_loop < _news.anchor_lines.size():
			MusicBus.anchor_line_changed.emit(_next_loop)
		_next_loop += 1
	_miss_late_notes(_judge_time())
	# Audio time: stops before the looping backing track is heard starting over.
	if clock.get_audio_time() >= clock.get_beat_time(_end_beat):
		_finish()


# _input, not _unhandled_input: a focused UI control must never swallow a lane key.
func _input(event: InputEvent) -> void:
	if not _running:
		return
	for lane in MusicTypes.LANE_COUNT:
		if event.is_action_pressed(MusicTypes.lane_action(lane)):
			_on_lane_pressed(lane, _judge_time())


# ponytail: a press is timed when Godot handles it, once per frame (up to ~16 ms late at 60 fps,
# well inside GOOD_WINDOW_SEC). input_offset_sec absorbs any steady part of it.
func _judge_time() -> float:
	return clock.get_song_time() - input_offset_sec


# ponytail: only the lane's next note can be hit. Notes on a lane are at least one beat apart,
# wider than the 2 * BAD_WINDOW_SEC judgment span up to 200 BPM; search the nearest note past that.
func _on_lane_pressed(lane: int, time: float) -> void:
	_miss_late_notes(time)
	var note := _peek_note(lane)
	var judgment: MusicTypes.Judgment = MusicTypes.Judgment.MISS
	if note != null:
		judgment = MusicTypes.judge(time - note.time_sec)
	if judgment == MusicTypes.Judgment.MISS:
		_set_combo(0, 1.0)  # Stray press: no note close enough on this lane.
		return
	_next_note[lane] += 1
	sequencer.set_lane_muted(lane, false)
	MusicBus.note_hit.emit(note.index, lane, judgment)
	if judgment == MusicTypes.Judgment.BAD:
		_set_combo(_combo, maxf(_combo_multiplier - COMBO_STEP, 1.0))
	else:
		var combo := _combo + 1
		var step_up := COMBO_STEP if combo % HITS_PER_COMBO_STEP == 0 else 0.0
		_set_combo(combo, minf(_combo_multiplier + step_up, MAX_COMBO_MULTIPLIER))
	_add_chaos(CHAOS_PER_JUDGMENT[judgment])
	var points: int = HIT_AUDIMAT[judgment]
	_audimat += roundi(points * _combo_multiplier * _composition_multiplier)
	MusicBus.audimat_changed.emit(_audimat)


## Misses every note whose BAD window closed before `time`.
func _miss_late_notes(time: float) -> void:
	for lane in MusicTypes.LANE_COUNT:
		var note := _peek_note(lane)
		while note != null and time - note.time_sec > MusicTypes.BAD_WINDOW_SEC:
			_next_note[lane] += 1
			sequencer.set_lane_muted(lane, true)
			MusicBus.note_missed.emit(note.index, lane)
			_set_combo(0, 1.0)
			_add_chaos(CHAOS_PER_JUDGMENT[MusicTypes.Judgment.MISS])
			note = _peek_note(lane)


## The lane's first note not judged yet, null when none is left.
func _peek_note(lane: int) -> NoteData:
	var notes: Array = _lane_notes[lane]
	if _next_note[lane] < notes.size():
		return notes[_next_note[lane]]
	return null


func _set_combo(combo: int, multiplier: float) -> void:
	if combo == _combo and multiplier == _combo_multiplier:
		return
	_combo = combo
	_combo_multiplier = multiplier
	MusicBus.combo_changed.emit(combo, multiplier)


func _add_chaos(amount: float) -> void:
	var chaos := clampf(_chaos + amount, 0.0, 1.0)
	if chaos != _chaos:
		_chaos = chaos
		MusicBus.chaos_level_changed.emit(chaos)


func _finish() -> void:
	_running = false
	# Every note is judged once: those still open when the music stops are missed.
	_miss_late_notes(INF)
	sequencer.stop()
	clock.stop()
	MusicBus.performance_finished.emit(_audimat)
