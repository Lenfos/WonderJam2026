extends Control
## Debug: plays a test loop through MusicClock, shows its times, flashes on each heard beat,
## and runs a metronome that logs its trigger error per loop to validate the clock.
##   M: metronome sound on/off (stats keep running).   B: next backing loop, restart the clock.
##   Left/Right: web start offset -/+ OFFSET_STEP_SEC, restarts the clock (no effect on desktop).

const STREAMS: Array[AudioStream] = [
	preload("res://audio/placeholder/test_loop_80.wav"),
	preload("res://audio/placeholder/test_loop_120.wav"),
	preload("res://audio/placeholder/test_loop_140.wav"),
]
const BPMS: Array[float] = [80.0, 120.0, 140.0]
const START_INDEX := 1
const CLICK := preload("res://audio/placeholder/click.wav")
const CLICK_POLYPHONY := 4
const OFFSET_STEP_SEC := 0.005
## pitch_scale of the click on the first beat of each bar.
const ACCENT_PITCH := 1.5
## A summary is printed every SUMMARY_LOOPS loops (first loop vs latest loop).
const SUMMARY_LOOPS := 6
## PASS: |latest-loop mean error - first-loop mean error| below this, in seconds.
const MAX_DRIFT_SEC := 0.005
## PASS: every |error| below this, in seconds. ~1 frame at 60 fps: _process quantizes triggers.
const MAX_ERROR_SEC := 0.017
## A click whose wall-clock interval to the previous one is off by more than this many beats is
## a glitch: catches a clock that freezes or jumps at the loop wrap, which audio time alone hides.
const INTERVAL_TOLERANCE_BEATS := 0.5
## Flash length, in beats.
const FLASH_BEATS := 0.25
const BEATS_PER_BAR := 4
const IDLE_COLOR := Color(0.12, 0.12, 0.12)
const BEAT_COLOR := Color(0.9, 0.9, 0.9)
const BAR_COLOR := Color(0.95, 0.3, 0.2)

var _clock := MusicClock.new()
var _label := Label.new()
var _flash := ColorRect.new()
var _click := AudioStreamPlayer.new()
var _stream_index := START_INDEX
var _metronome_on := true
var _last_beat := -1
var _last_click_usec := 0
var _stats_loop := 0
var _err_sum := 0.0
var _err_count := 0
var _err_max := 0.0
var _loop_means: Array[float] = []
var _run_max := 0.0
var _glitches := 0
var _last_report := ""


func _ready() -> void:
	add_child(_clock)
	_click.stream = CLICK
	_click.max_polyphony = CLICK_POLYPHONY
	add_child(_click)
	_flash.position = Vector2(40, 300)
	_flash.size = Vector2(400, 300)
	add_child(_flash)
	_label.position = Vector2(40, 20)
	_label.add_theme_font_size_override("font_size", 24)
	add_child(_label)
	_restart()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_M:
			_metronome_on = not _metronome_on
			if _metronome_on:
				_resync_metronome()
		KEY_B:
			_stream_index = (_stream_index + 1) % STREAMS.size()
			_restart()
		KEY_LEFT, KEY_RIGHT:
			_clock.web_start_offset_sec += OFFSET_STEP_SEC if key.keycode == KEY_RIGHT else -OFFSET_STEP_SEC
			_restart()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_resync_metronome()


## Next click on the next beat crossing: no wait, no double fire, no false wall-interval glitch.
func _resync_metronome() -> void:
	_last_beat = floori(_clock.get_beat(_clock.get_audio_time()))
	_last_click_usec = 0


func _process(_delta: float) -> void:
	var audio_time := _clock.get_audio_time()
	_update_metronome(audio_time)
	var song_time := _clock.get_song_time()
	var beat := _clock.get_beat(song_time)
	var step := _clock.get_step(song_time)
	_label.text = "%.0f BPM [B]   metronome %s [M]   web offset %+.0f ms [Left/Right]\naudio_time  %.4f\nsong_time   %.4f\nlatency     %.4f\nloop        %d\nbeat        %.3f\nstep        %d\n%s" % [
		_clock.bpm, "ON" if _metronome_on else "OFF", _clock.web_start_offset_sec * 1000.0, audio_time, song_time, _clock.get_output_latency(),
		_clock.get_loop_index(song_time), beat, step, _last_report]
	var on_beat := song_time >= 0.0 and beat - floorf(beat) < FLASH_BEATS
	_flash.color = IDLE_COLOR if not on_beat else (BAR_COLOR if step % BEATS_PER_BAR == 0 else BEAT_COLOR)


func _restart() -> void:
	_clock.start(STREAMS[_stream_index], BPMS[_stream_index])
	_last_beat = -1
	_stats_loop = 0
	_err_sum = 0.0
	_err_count = 0
	_err_max = 0.0
	_loop_means.clear()
	_run_max = 0.0
	_glitches = 0
	_last_report = ""
	print("--- %.0f BPM, loop %.4f s, web offset %+.0f ms ---" % [
			_clock.bpm, _clock.get_loop_length(), _clock.web_start_offset_sec * 1000.0])


## Clicks on each new beat of the mix-side clock and accumulates the trigger error.
func _update_metronome(audio_time: float) -> void:
	var beat := floori(_clock.get_beat(audio_time))
	if beat == _last_beat:
		return
	var step := _clock.get_step(audio_time)
	if _metronome_on:
		# ponytail: pitch_scale also retunes still-ringing voices; harmless while the click is far shorter than a beat.
		_click.pitch_scale = ACCENT_PITCH if step % BEATS_PER_BAR == 0 else 1.0
		_click.play()
	var now_usec := Time.get_ticks_usec()
	var previous_beat := _last_beat
	var previous_usec := _last_click_usec
	_last_beat = beat
	_last_click_usec = now_usec
	# The first click after start() is not a beat crossing: nothing to measure yet.
	if previous_beat < 0:
		return

	var beat_len := _clock.get_beat_length()
	var interval := (now_usec - previous_usec) / 1000000.0
	var interval_bad := previous_usec > 0 and absf(interval - beat_len) > beat_len * INTERVAL_TOLERANCE_BEATS
	if beat != previous_beat + 1 or interval_bad:
		_glitches += 1
		print("GLITCH beat %d -> %d, wall interval %.1f ms (expected %.1f ms)"
				% [previous_beat, beat, interval * 1000.0, beat_len * 1000.0])

	var loop := _clock.get_loop_index(audio_time)
	if loop != _stats_loop:
		_end_loop()
		_stats_loop = loop
	# Independent of MusicClock's beat grid: where the beat sits in a file rendered at bpm
	# (loop start + nominal step offset). A stream length off bpm must stay flat per loop, not grow.
	var expected := loop * _clock.get_loop_length() + step * 60.0 / _clock.bpm
	var err := audio_time - expected
	_err_sum += err
	_err_count += 1
	_err_max = maxf(_err_max, absf(err))
	_run_max = maxf(_run_max, absf(err))


func _end_loop() -> void:
	if _err_count == 0:
		return
	var mean := _err_sum / _err_count
	_loop_means.append(mean)
	_last_report = "loop %d | %.0f BPM | mean %+.2f ms | max |err| %.2f ms | glitches %d" % [
		_stats_loop, _clock.bpm, mean * 1000.0, _err_max * 1000.0, _glitches]
	print(_last_report)
	_err_sum = 0.0
	_err_count = 0
	_err_max = 0.0
	if _loop_means.size() % SUMMARY_LOOPS == 0:
		_print_summary()


func _print_summary() -> void:
	var first := _loop_means[0]
	var last := _loop_means[-1]
	var drift := absf(last - first)
	var drift_ok := drift < MAX_DRIFT_SEC
	var max_ok := _run_max < MAX_ERROR_SEC
	var wrap_ok := _glitches == 0
	print("=== SUMMARY %.0f BPM, %d loops ===" % [_clock.bpm, _loop_means.size()])
	print("  drift      first mean %+.2f ms, last mean %+.2f ms, |delta| %.2f ms (< %.0f)  %s" % [
		first * 1000.0, last * 1000.0, drift * 1000.0, MAX_DRIFT_SEC * 1000.0, "PASS" if drift_ok else "FAIL"])
	print("  max error  %.2f ms (< %.0f)  %s" % [_run_max * 1000.0, MAX_ERROR_SEC * 1000.0, "PASS" if max_ok else "FAIL"])
	print("  loop wrap  %d glitch(es)  %s" % [_glitches, "PASS" if wrap_ok else "FAIL"])
	print("  RESULT     %s" % ("PASS" if drift_ok and max_ok and wrap_ok else "FAIL"))
