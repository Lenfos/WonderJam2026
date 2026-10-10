class_name MusicClock
extends Node
## Single source of gameplay time. Plays a looping backing track and turns its playback
## position into a continuous, monotonic clock (see "Sync the gameplay with audio and music").
##   get_audio_time(): time of the audio mix -> SCHEDULE/TRIGGER sounds.
##   get_song_time():  time the player HEARS (output latency removed) -> visuals, input judgment.
## Beats are counted from the real loop length, not from bpm: every loop starts exactly on a
## multiple of beats_per_loop, so a stream slightly off bpm never drifts loop after loop.
## Web: Sample playback bypasses the AudioServer mix, so playback position is unreliable there.
## The clock is a stopwatch started with the stream instead (rounds are short, drift negligible).
## Pauses on application focus loss and resumes in sync on focus back.

## Max allowed gap, in seconds, between the stream length and beats_per_loop at bpm.
## Within a loop, beats can be off from the nominal bpm grid by up to this gap (never accumulated).
const LENGTH_TOLERANCE_SEC := 0.005

const USEC_PER_SEC := 1000000.0

## Web only: how late, in seconds, the browser actually starts the stream after play().
## Positive delays the clock. Tune by ear (metronome vs backing); future player latency setting.
@export var web_start_offset_sec: float = 0.0

var bpm: float = 120.0
var beats_per_loop: int = MusicTypes.STEP_COUNT

var _is_web := OS.has_feature("web")
var _running := false
var _paused := false
## Web stopwatch origin: audio time = (now - _start_usec) / USEC_PER_SEC.
var _start_usec: int = 0
var _player: AudioStreamPlayer
var _output_latency: float = 0.0
var _loop_length: float = 0.0
var _loop_count: int = 0
var _last_position: float = 0.0
var _last_audio_time: float = 0.0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)


func _process(_delta: float) -> void:
	# Sample every frame so no wrap is missed, even when nobody queries the clock.
	if _player.playing:
		get_audio_time()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			pause()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			resume()


## from_sec: where playback starts in the stream, and the clock's time at start (e.g. a count-in
## starting a few beats before the loop end). Must be less than the stream length.
func start(stream: AudioStream, p_bpm: float, p_beats_per_loop: int = MusicTypes.STEP_COUNT, from_sec: float = 0.0) -> void:
	bpm = p_bpm
	beats_per_loop = p_beats_per_loop
	_loop_length = stream.get_length()
	var expected := beats_per_loop * 60.0 / bpm
	if absf(_loop_length - expected) > LENGTH_TOLERANCE_SEC:
		push_warning("MusicClock: stream is %.4f s but %d beats at %.2f BPM is %.4f s (%s)"
				% [_loop_length, beats_per_loop, bpm, expected, stream.resource_path])
	if stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_FORWARD:
		push_warning("MusicClock: %s is not imported with loop mode Forward" % stream.resource_path)
	_output_latency = AudioServer.get_output_latency()
	_loop_count = 0
	_last_position = from_sec
	# Web: behind from_sec during the browser start delay, like get_song_time() during output latency.
	_last_audio_time = from_sec - web_start_offset_sec if _is_web else from_sec
	_running = true
	_paused = false
	_player.stream = stream
	_player.stream_paused = false
	_player.play(from_sec)
	_restart_stopwatch(from_sec)


func stop() -> void:
	_running = false
	_paused = false
	_player.stop()


func is_playing() -> bool:
	return _running and not _paused


## Freezes the clock and the backing track. No-op if not playing.
func pause() -> void:
	if not is_playing():
		return
	_last_audio_time = get_audio_time()
	_paused = true
	if _is_web:
		_player.stop()
	else:
		_player.stream_paused = true


## Continues from the paused time. Web: replays the stream from that loop position.
func resume() -> void:
	if not _paused:
		return
	_paused = false
	if _is_web:
		_player.play(fposmod(_last_audio_time, _loop_length))
		_restart_stopwatch(_last_audio_time)
	else:
		_player.stream_paused = false


## Web: makes the stopwatch read from_time now, shifted by the browser start delay.
func _restart_stopwatch(from_time: float) -> void:
	_start_usec = Time.get_ticks_usec() - roundi((from_time - web_start_offset_sec) * USEC_PER_SEC)


## Continuous mix-side time in seconds since start(). Use it to trigger sounds.
func get_audio_time() -> float:
	if not _running or _paused:
		return _last_audio_time
	if _is_web:
		# Held at the paused time after resume() until the browser start delay has elapsed.
		_last_audio_time = maxf(_last_audio_time, (Time.get_ticks_usec() - _start_usec) / USEC_PER_SEC)
		return _last_audio_time
	if not _player.playing:
		return _last_audio_time
	var position := _player.get_playback_position()
	# Position jumping back by more than half a loop = the stream wrapped. Small backward
	# jitter between mixes stays well under that threshold.
	if position < _last_position - _loop_length * 0.5:
		_loop_count += 1
	_last_position = position
	var t := _loop_count * _loop_length + position + AudioServer.get_time_since_last_mix()
	# The raw formula can step slightly backwards between mixes: never go back in time.
	_last_audio_time = maxf(_last_audio_time, t)
	return _last_audio_time


## What the player hears right now. Use it for visuals and input judgment. Negative right after start().
func get_song_time() -> float:
	return get_audio_time() - _output_latency


func get_output_latency() -> float:
	return _output_latency


func get_loop_length() -> float:
	return _loop_length


## Seconds per beat: the loop length spread over beats_per_loop. Nominal 60 / bpm before start().
func get_beat_length() -> float:
	return _loop_length / beats_per_loop if _loop_length > 0.0 else 60.0 / bpm


func get_beat(time: float) -> float:
	return time / get_beat_length()


## Inverse of get_beat(): time at which a beat starts. Beat of step s in loop n = n * beats_per_loop + s.
func get_beat_time(beat: float) -> float:
	return beat * get_beat_length()


## Step 0..beats_per_loop-1 within the current loop (one step = one beat).
func get_step(time: float) -> int:
	return posmod(floori(get_beat(time)), beats_per_loop)


func get_loop_index(time: float) -> int:
	return floori(get_beat(time) / beats_per_loop)
