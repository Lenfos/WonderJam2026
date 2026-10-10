class_name PerformancePhase
extends Node
## Runs the PERFORMANCE phase: a count-in, then the composition replayed loop_count times over the
## backing track as a chart the player plays (keys D F J K). Talks to the UI only through MusicBus.
## Ends with MusicBus.performance_finished.
# STUB — replaced in phase 3: no input or judgment yet (note_hit, note_missed, combo_changed never
# fire, chaos stays 0) and the audimat is faked at the end. The chart, the count-in, the anchor
# lines and the start() signature are real: keep them.

## Fake audimat per composition note, before the multiplier.
const STUB_AUDIMAT_PER_NOTE := 100.0

## Shared with the composition phase (siblings in main.tscn).
@export var clock: MusicClock
@export var sequencer: SequencerPlayer
## Times the composition is played.
@export var loop_count: int = 3
## Backing-only beats before the first chart beat, counted down by countdown_beat.
@export var count_in_beats: int = 4

var _running := false
var _news: NewsData
var _composition: Composition
var _multiplier := 1.0
## Absolute clock beats: step 0 of the first loop, and the end of the last loop.
var _start_beat := 0
var _end_beat := 0
## Next beat whose countdown_beat is still to be emitted.
var _next_countdown_beat := 0
## Next loop whose anchor line is still to be emitted.
var _next_loop := 0


## `multiplier` comes from the composition evaluation.
func start(news: NewsData, composition: Composition, multiplier: float) -> void:
	_news = news
	_composition = composition
	_multiplier = multiplier
	# The chart starts on a loop boundary so its steps line up with the backing track's bars:
	# the clock starts count_in_beats earlier, near the end of a loop.
	_start_beat = ceili(count_in_beats / float(MusicTypes.STEP_COUNT)) * MusicTypes.STEP_COUNT
	_end_beat = _start_beat + loop_count * MusicTypes.STEP_COUNT
	var count_in_start := _start_beat - count_in_beats
	var beat_length := news.backing_track.get_length() / MusicTypes.STEP_COUNT
	clock.start(news.backing_track, news.bpm, MusicTypes.STEP_COUNT, count_in_start * beat_length)
	sequencer.start(clock, news, composition, _start_beat, _end_beat)
	_next_countdown_beat = count_in_start
	_next_loop = 0
	_running = true
	var chart := NoteData.build_chart(composition, clock.get_beat_length(), _start_beat, loop_count)
	MusicBus.chaos_level_changed.emit(0.0)
	MusicBus.audimat_changed.emit(0)
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
	# Audio time: stops before the looping backing track is heard starting over.
	if clock.get_audio_time() >= clock.get_beat_time(_end_beat):
		_finish()


func _finish() -> void:
	_running = false
	sequencer.stop()
	clock.stop()
	# STUB: phase 3 builds the audimat from the player's hits instead.
	var audimat := roundi(_composition.count_notes() * _multiplier * STUB_AUDIMAT_PER_NOTE)
	MusicBus.audimat_changed.emit(audimat)
	MusicBus.performance_finished.emit(audimat)
