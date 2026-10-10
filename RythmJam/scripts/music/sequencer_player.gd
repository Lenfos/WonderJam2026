class_name SequencerPlayer
extends Node
## Plays a Composition in time with a running MusicClock: one step per beat, looping.
## Reads the grid when a step is reached, so edits are heard the next time that step comes around.
## Emits MusicBus.step_changed on every new step.

## Voices per melodic lane. pitch_scale is per player (it retunes every voice still ringing),
## so each melodic note takes the next player of a round-robin pool instead.
const MELODIC_POOL_SIZE := 4
## Simultaneous voices per player (kick/snare tails overlapping the next hit).
const MAX_POLYPHONY := 4
## A step reached later than this (frame hitch) is shown but not played: a late note sounds wrong.
const MAX_LATE_SEC := 0.05

## One-shot per lane, indexed by MusicTypes.Lane. Melodic samples must be tuned to MusicTypes.REFERENCE_NOTE.
@export var lane_streams: Array[AudioStream] = [
	preload("res://audio/placeholder/inst_kick.wav"),
	preload("res://audio/placeholder/inst_snare.wav"),
	preload("res://audio/placeholder/inst_brass.wav"),
	preload("res://audio/placeholder/inst_bells.wav"),
]
@export var bus: StringName = &"Instruments"

var _clock: MusicClock
var _news: NewsData
var _composition: Composition
## Absolute beat (loops included) last handled; first_beat - 1 before the first one.
var _last_beat: int = -1
## Absolute beat at which stepping stops; -1 = loop forever.
var _end_beat: int = -1
## Per lane: its players (1 for drums, MELODIC_POOL_SIZE for melodic lanes).
var _voices: Array[Array] = []
## Per lane: index in _voices[lane] of the next player to use.
var _next_voice := PackedInt32Array()


func _ready() -> void:
	_next_voice.resize(MusicTypes.LANE_COUNT)
	for lane in MusicTypes.LANE_COUNT:
		var pool: Array[AudioStreamPlayer] = []
		for i in MELODIC_POOL_SIZE if _is_melodic(lane) else 1:
			var player := AudioStreamPlayer.new()
			player.stream = lane_streams[lane]
			player.bus = bus
			player.max_polyphony = MAX_POLYPHONY
			add_child(player)
			pool.append(player)
		_voices.append(pool)


## `clock` must already be playing news.backing_track. `composition` is read live, not copied.
## Only absolute clock beats in [first_beat, end_beat) are stepped (end_beat -1 = loop forever):
## earlier ones are a count-in, the end lets the last notes ring.
func start(clock: MusicClock, news: NewsData, composition: Composition, first_beat: int = 0, end_beat: int = -1) -> void:
	_clock = clock
	_news = news
	_composition = composition
	_last_beat = first_beat - 1
	_end_beat = end_beat


## Stops stepping and cuts every ringing sample.
func stop() -> void:
	_clock = null
	for pool in _voices:
		for player: AudioStreamPlayer in pool:
			player.stop()


func _process(_delta: float) -> void:
	if _clock == null or not _clock.is_playing():
		return
	var time := _clock.get_audio_time()
	var beat := floori(_clock.get_beat(time))
	if beat <= _last_beat:
		return
	if _end_beat >= 0 and beat >= _end_beat:
		_clock = null
		return
	# Steps skipped by a hitch are dropped: only the latest one is considered.
	_last_beat = beat
	var step := _clock.get_step(time)
	if time - _clock.get_beat_time(beat) <= MAX_LATE_SEC:
		for lane in MusicTypes.LANE_COUNT:
			if _composition.is_active(lane, step):
				_play(lane, step)
	MusicBus.step_changed.emit(step)


## Plays a cell's sound now, at its pitch, whether the cell is on or not (click feedback).
func preview_cell(lane: int, step: int) -> void:
	if _news != null:
		_play(lane, step)


func _play(lane: int, step: int) -> void:
	var pool: Array = _voices[lane]
	var player: AudioStreamPlayer = pool[_next_voice[lane]]
	_next_voice[lane] = (_next_voice[lane] + 1) % pool.size()
	player.pitch_scale = MusicTypes.semitones_to_pitch_scale(_semitones(lane, step))
	player.play()


func _semitones(lane: int, step: int) -> int:
	match lane:
		MusicTypes.Lane.BRASS:
			return MusicTypes.degree_to_semitones(_news.scale, _news.brass_melody[step])
		MusicTypes.Lane.BELLS:
			return MusicTypes.degree_to_semitones(_news.scale, _news.bells_melody[step])
	return 0


func _is_melodic(lane: int) -> bool:
	return lane == MusicTypes.Lane.BRASS or lane == MusicTypes.Lane.BELLS
