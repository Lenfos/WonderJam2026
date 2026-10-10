class_name CompositionPhase
extends Node
## Runs the COMPOSITION phase: backing track + live sequencer playback, cell toggles from
## MusicBus.cell_toggle_requested, and a countdown. Ends on timeout or finish_early().
## Talks to the UI only through MusicBus.

## Phase length when start() is not given one.
@export var duration_sec: float = 45.0

# ponytail: the phase owns the clock; move it to a round controller once the performance phase needs it too.
var clock: MusicClock
var _sequencer: SequencerPlayer
var _composition: Composition
var _running := false
var _duration: float = 0.0
var _seconds_left: int = -1


func _ready() -> void:
	clock = MusicClock.new()
	add_child(clock)
	_sequencer = SequencerPlayer.new()
	add_child(_sequencer)
	MusicBus.cell_toggle_requested.connect(_on_cell_toggle_requested)


## p_duration_sec <= 0 uses the exported duration_sec. Restarting mid-phase starts over with an empty grid.
func start(news: NewsData, p_duration_sec: float = -1.0) -> void:
	_duration = p_duration_sec if p_duration_sec > 0.0 else duration_sec
	_composition = Composition.new()
	clock.start(news.backing_track, news.bpm)
	_sequencer.start(clock, news, _composition)
	_running = true
	_seconds_left = -1
	MusicBus.composition_started.emit(news, _duration)
	_update_countdown()


## Ends the phase now, as if time ran out. No-op if not running.
func finish_early() -> void:
	if _running:
		_finish()


func is_running() -> bool:
	return _running


func _process(_delta: float) -> void:
	if _running:
		_update_countdown()


# Clock time, not delta: freezes with the clock on focus loss.
func _update_countdown() -> void:
	var left := _duration - maxf(clock.get_audio_time(), 0.0)
	if left <= 0.0:
		_finish()
		return
	var seconds := ceili(left)
	if seconds != _seconds_left:
		_seconds_left = seconds
		MusicBus.composition_time_changed.emit(seconds)


# The backing track keeps playing: the next phase decides what to do with the clock.
func _finish() -> void:
	_running = false
	_sequencer.stop()
	MusicBus.composition_time_changed.emit(0)
	MusicBus.composition_finished.emit(_composition.duplicate_composition())


func _on_cell_toggle_requested(lane: int, step: int) -> void:
	if not _running:
		return
	var active := _composition.toggle(lane, step)
	if active:
		_sequencer.preview_cell(lane, step)
	MusicBus.composition_changed.emit(lane, step, active)
