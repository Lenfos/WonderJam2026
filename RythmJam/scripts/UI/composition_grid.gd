extends Control
## Composition screen grid: LANE_COUNT rows (kick, snare, brass, bells) x STEP_COUNT steps,
## an instrument icon per row, steps grouped by STEPS_PER_BAR on shaded blocks.
## Only talks to MusicBus (docs/CONTRACT.md): clicks are sent as cell_toggle_requested, cells are
## redrawn from composition_changed, the playhead follows MusicBus.get_song_time().

@export var cell_texture: Texture2D
@export var active_cell_texture: Texture2D
## One per MusicTypes.Lane, in lane order.
@export var lane_icons: Array[Texture2D] = []
## Extra gap between two bars, on top of the grid's h_separation.
@export var bar_gap := 6.0
@export var bar_color := Color(0, 0, 0, 0.08)
@export var playing_column_color := Color(1.0, 0.85, 0.2, 0.45)

@export_group("Keys")
## Starts the composition; while composing, puts the bar back to step 0 (grid and timer kept). Space by default.
@export var start_action: StringName = &"start_composition"
## Clears every note of the grid, the bar keeps going. C by default.
@export var clear_action: StringName = &"clear_composition"

@export_group("Start prompt")
## Seconds between entering COMPOSITION and showing the prompt: the start menu transition plays
## meanwhile (its transition_hold + ~0.5 s exit), and the start key is ignored until then.
@export var start_prompt_delay := 2.6
## Seconds of one prompt pulse (half a cycle).
@export var start_prompt_blink_sec := 0.6

@export_group("Timer")
## At or below this many seconds left, the timer turns low_time_color.
@export var low_time_sec := 10
@export var low_time_color := Color(1.0, 0.3, 0.3)

@export_group("Juice")
## One color per lane (MusicTypes.Lane order), used for flashes and sparks. Missing entries fall back to white.
@export var lane_colors: Array[Color] = [
	Color("#ff4d5a"), Color("#ffd23f"), Color("#3fe0ff"), Color("#b36bff")]
## Pitch of the place sound, per lane. Missing entries fall back to 1.0.
@export var lane_pitches: Array[float] = [0.7, 0.9, 1.1, 1.4]
## How much active cells swell on the playing column.
@export var beat_pulse_strength := 0.18

@export_group("Juice sounds")
@export var place_sfx: AudioStream
@export var remove_sfx: AudioStream
@export var hover_sfx: AudioStream
@export var click_sfx: AudioStream
@export var start_sfx: AudioStream
## Low-time countdown tick.
@export var tick_sfx: AudioStream

@onready var _grid: GridContainer = %Grid
@onready var _bars: Control = %Bars
@onready var _column: Control = %PlayingColumn
@onready var _playhead: Control = %Playhead
@onready var _finished_button: TextureButton = %finishedButton
@onready var _start_prompt: Label = %StartPrompt
@onready var _time_label: Label = %TimeLabel
@onready var _keys_label: Label = %KeysLabel

var _buttons: Array[TextureButton] = []  # index = lane * STEP_COUNT + step
var _beat_length := 0.0
var _playing_step := -1
var _bar_style := StyleBoxFlat.new()
var _column_style := StyleBoxFlat.new()
var _waiting_start := false
var _playing := false
var _prompt_tween: Tween
var _prompt_loop: Tween
var _dismiss_tween: Tween
var _finished_tween: Tween
var _cell_tweens: Dictionary = {}
var _clearing := false
## Display copy of the grid (docs/CONTRACT.md): which cells the clear key must toggle off.
var _composition := Composition.new()

var _place_player: AudioStreamPlayer
var _remove_player: AudioStreamPlayer
var _hover_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer
var _start_player: AudioStreamPlayer
var _tick_player: AudioStreamPlayer


func _ready() -> void:
	_place_player = _make_player(place_sfx, -4.0)
	_remove_player = _make_player(remove_sfx, -6.0)
	_hover_player = _make_player(hover_sfx, -14.0)
	_click_player = _make_player(click_sfx, 0.0)
	_start_player = _make_player(start_sfx, 0.0)
	_tick_player = _make_player(tick_sfx, -6.0)

	@warning_ignore("integer_division")
	_grid.columns = 1 + MusicTypes.STEP_COUNT + MusicTypes.STEP_COUNT / MusicTypes.STEPS_PER_BAR
	for lane in MusicTypes.LANE_COUNT:
		var icon := TextureRect.new()
		icon.texture = lane_icons[lane]
		icon.tooltip_text = str(MusicTypes.Lane.keys()[lane]).capitalize()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_grid.add_child(icon)
		for step in MusicTypes.STEP_COUNT:
			if step % MusicTypes.STEPS_PER_BAR == 0:
				var spacer := Control.new()
				spacer.custom_minimum_size.x = bar_gap
				_grid.add_child(spacer)
			var button := TextureButton.new()
			button.texture_normal = cell_texture
			button.ignore_texture_size = true
			button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.size_flags_vertical = Control.SIZE_EXPAND_FILL
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func() -> void: MusicBus.cell_toggle_requested.emit(lane, step))
			button.resized.connect(func() -> void: button.pivot_offset = button.size / 2.0)
			button.mouse_entered.connect(_on_cell_hover.bind(button, true))
			button.mouse_exited.connect(_on_cell_hover.bind(button, false))
			_grid.add_child(button)
			_buttons.append(button)

	_bar_style.bg_color = bar_color
	_bar_style.set_corner_radius_all(8)
	_column_style.bg_color = playing_column_color
	_column_style.set_corner_radius_all(6)
	_bars.draw.connect(_draw_bars)
	_column.draw.connect(_draw_playing_column)
	_grid.sort_children.connect(_bars.queue_redraw)

	_finished_button.pressed.connect(_on_finished_pressed)
	_finished_button.resized.connect(func() -> void: _finished_button.pivot_offset = _finished_button.size / 2.0)
	_finished_button.mouse_entered.connect(_on_fin_hover.bind(true))
	_finished_button.mouse_exited.connect(_on_fin_hover.bind(false))
	_finished_button.button_down.connect(_on_fin_down)
	_finished_button.button_up.connect(_on_fin_up)

	MusicBus.composition_started.connect(_on_composition_started)
	MusicBus.composition_changed.connect(_on_composition_changed)
	MusicBus.composition_finished.connect(func(_c: Composition) -> void: _set_playing(false))
	MusicBus.phase_changed.connect(_on_phase_changed)
	MusicBus.composition_time_changed.connect(_on_time_changed)
	# Key names from the Input Map, so a rebind updates the texts.
	_start_prompt.text = "PRESS %s TO START" % _key_name(start_action)
	_keys_label.text = "%s : BAR TO START      %s : CLEAR" % [_key_name(start_action), _key_name(clear_action)]
	_time_label.visible = false
	_set_playing(false)
	_hide_start_prompt()


# Smooth playhead: enters a cell when that step sounds, the column under it is highlighted.
func _process(_delta: float) -> void:
	var beats := fposmod(MusicBus.get_song_time() / _beat_length, MusicTypes.STEP_COUNT)
	var step := floori(beats)
	var x := _cell_center_x(step)
	var next_x := _cell_center_x(step + 1) if step + 1 < MusicTypes.STEP_COUNT else 2.0 * x - _cell_center_x(step - 1)
	var half_cell := _cell_side() / 2.0
	_playhead.global_position.x = x - half_cell + (beats - step) * (next_x - x)
	if step != _playing_step:
		_playing_step = step
		_column.queue_redraw()
		_pulse_column(step)


# _input, not _unhandled_input: a focused button must not swallow the start key.
func _input(event: InputEvent) -> void:
	if (_waiting_start or _playing) and event.is_action_pressed(start_action):
		get_viewport().set_input_as_handled()
		_dismiss_start_prompt()
		MusicBus.composition_start_requested.emit()
	elif _playing and event.is_action_pressed(clear_action):
		get_viewport().set_input_as_handled()
		_clear_cascade()


# ------------------------------------------------------------ start prompt

# Entering COMPOSITION: the grid waits, frozen, until the prompt shows and the player presses start.
func _on_phase_changed(phase: MusicTypes.Phase) -> void:
	_hide_start_prompt()
	if phase == MusicTypes.Phase.COMPOSITION:
		_prompt_tween = create_tween()
		_prompt_tween.tween_interval(start_prompt_delay)
		_prompt_tween.tween_callback(_show_start_prompt)


func _show_start_prompt() -> void:
	_waiting_start = true
	_start_prompt.visible = true
	_start_prompt.pivot_offset = _start_prompt.size / 2.0
	_start_prompt.scale = Vector2.ONE * 0.5
	_start_prompt.modulate.a = 0.0
	_intro_wave()

	_prompt_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_prompt_tween.tween_property(_start_prompt, "scale", Vector2.ONE, 0.35)
	_prompt_tween.tween_property(_start_prompt, "modulate:a", 1.0, 0.2)
	_prompt_tween.chain().tween_callback(_start_prompt_pulse)


# The prompt "breathes" (scale + alpha) instead of just blinking.
func _start_prompt_pulse() -> void:
	var s := start_prompt_blink_sec
	_prompt_loop = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	_prompt_loop.tween_property(_start_prompt, "scale", Vector2.ONE * 1.06, s)
	_prompt_loop.parallel().tween_property(_start_prompt, "modulate:a", 0.5, s)
	_prompt_loop.tween_property(_start_prompt, "scale", Vector2.ONE, s)
	_prompt_loop.parallel().tween_property(_start_prompt, "modulate:a", 1.0, s)


# The player pressed start: the prompt swells and fades out.
func _dismiss_start_prompt() -> void:
	_waiting_start = false
	_kill(_prompt_tween)
	_kill(_prompt_loop)
	if not _start_prompt.visible:
		return
	_sfx(_start_player, 1.0)
	_dismiss_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dismiss_tween.tween_property(_start_prompt, "scale", Vector2.ONE * 1.6, 0.25)
	_dismiss_tween.tween_property(_start_prompt, "modulate:a", 0.0, 0.25)
	_dismiss_tween.chain().tween_callback(func() -> void: _start_prompt.visible = false)


func _hide_start_prompt() -> void:
	_waiting_start = false
	_kill(_prompt_tween)
	_kill(_prompt_loop)
	_kill(_dismiss_tween)
	_start_prompt.visible = false
	_start_prompt.scale = Vector2.ONE


# ------------------------------------------------------------ composition events

func _on_composition_started(news: NewsData, _duration_sec: float) -> void:
	# Started some other way than the key: no exit animation is running, hide the prompt right away.
	if _waiting_start:
		_hide_start_prompt()
	_beat_length = 60.0 / news.bpm
	_composition.clear()
	for button in _buttons:
		_kill(_cell_tweens.get(button))
		button.texture_normal = cell_texture
		button.scale = Vector2.ONE
		button.modulate = Color.WHITE
	_set_playing(true)


func _on_time_changed(seconds_left: int) -> void:
	var first := not _time_label.visible
	_time_label.visible = true
	@warning_ignore("integer_division")
	_time_label.text = "%d:%02d" % [seconds_left / 60, seconds_left % 60]
	var low := seconds_left <= low_time_sec
	_time_label.modulate = low_time_color if low else Color.WHITE
	_time_label.pivot_offset = _time_label.size / 2.0

	if first:
		_time_label.scale = Vector2.ZERO
		create_tween().tween_property(_time_label, "scale", Vector2.ONE, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif low:
		# One "beat" per second, higher pitched as time runs out.
		_time_label.scale = Vector2.ONE * 1.3
		create_tween().tween_property(_time_label, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_sfx(_tick_player, 1.0 + float(low_time_sec - seconds_left) * 0.05)


func _on_composition_changed(lane: int, step: int, active: bool) -> void:
	_composition.set_cell(lane, step, active)
	var b := _buttons[lane * MusicTypes.STEP_COUNT + step]
	b.texture_normal = active_cell_texture if active else cell_texture
	b.pivot_offset = b.size / 2.0
	var hover_scale := 1.12 if b.is_hovered() else 1.0

	var t := _cell_tween(b).set_parallel(true)
	if active:
		b.scale = Vector2.ONE * 0.6
		b.modulate = _bright(_lane_color(lane).lerp(Color.WHITE, 0.5), 1.5)
		t.tween_property(b, "scale", Vector2.ONE * hover_scale, 0.4) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "modulate", Color.WHITE, 0.3)
		if not _clearing:
			_burst(b, _lane_color(lane))
			_sfx(_place_player, _lane_pitch(lane) * randf_range(0.96, 1.04))
	else:
		b.scale = Vector2.ONE * 1.15
		t.tween_property(b, "scale", Vector2.ONE * hover_scale, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "modulate", Color.WHITE, 0.2)
		if not _clearing:
			_sfx(_remove_player, randf_range(0.9, 1.0))


# Ends the composition early: the music side answers with composition_finished.
func _on_finished_pressed() -> void:
	_sfx(_click_player, 1.0)
	MusicBus.finish_composition_requested.emit()


# First key bound to `action`, as printed on the keyboard ("SPACE", "C").
func _key_name(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key:
			var keycode := key.keycode if key.keycode != KEY_NONE else DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			return OS.get_keycode_string(keycode).to_upper()
	return str(action).to_upper()


func _set_playing(playing: bool) -> void:
	_playing = playing
	_keys_label.visible = playing
	_finished_button.disabled = not playing
	_playhead.visible = playing
	_column.visible = playing
	_playing_step = -1
	set_process(playing)

	# FINISHED is greyed out while not composing.
	_kill(_finished_tween)
	_finished_tween = create_tween().set_parallel(true)
	_finished_tween.tween_property(_finished_button, "modulate", Color.WHITE if playing else Color(1, 1, 1, 0.45), 0.25)
	_finished_tween.tween_property(_finished_button, "scale", Vector2.ONE, 0.25)
	if playing:
		_keys_label.modulate.a = 0.0
		create_tween().tween_property(_keys_label, "modulate:a", 1.0, 0.4)


# ------------------------------------------------------------ cells juice

func _kill(t: Tween) -> void:
	if t and t.is_valid():
		t.kill()


# One active tween per cell: the new one replaces the old one.
func _cell_tween(b: Control) -> Tween:
	_kill(_cell_tweens.get(b))
	var t := create_tween()
	_cell_tweens[b] = t
	return t


func _bright(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


func _lane_color(lane: int) -> Color:
	return lane_colors[lane] if lane < lane_colors.size() else Color.WHITE


func _lane_pitch(lane: int) -> float:
	return lane_pitches[lane] if lane < lane_pitches.size() else 1.0


func _on_cell_hover(b: TextureButton, entering: bool) -> void:
	if not _playing:
		return
	var t := _cell_tween(b).set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "scale", Vector2.ONE * (1.12 if entering else 1.0), 0.12)
	t.tween_property(b, "modulate", Color(1.2, 1.2, 1.2) if entering else Color.WHITE, 0.12)
	if entering:
		@warning_ignore("integer_division")
		var lane := _buttons.find(b) / MusicTypes.STEP_COUNT
		_sfx(_hover_player, _lane_pitch(lane) * 1.5 + randf_range(-0.03, 0.03))


# The playing column "beats": active cells pulse in their lane color, empty ones barely brighten.
func _pulse_column(step: int) -> void:
	for lane in MusicTypes.LANE_COUNT:
		var b := _buttons[lane * MusicTypes.STEP_COUNT + step]
		var base := 1.12 if b.is_hovered() else 1.0
		var t := _cell_tween(b).set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if _composition.is_active(lane, step):
			b.scale = Vector2.ONE * (base + beat_pulse_strength)
			b.modulate = _bright(_lane_color(lane).lerp(Color.WHITE, 0.6), 1.4)
			t.tween_property(b, "scale", Vector2.ONE * base, 0.22)
			t.tween_property(b, "modulate", Color.WHITE, 0.28)
		else:
			b.modulate = Color(1.12, 1.12, 1.12)
			t.tween_property(b, "modulate", Color.WHITE, 0.2)


# A wave crosses the grid when the start prompt shows up.
func _intro_wave() -> void:
	for lane in MusicTypes.LANE_COUNT:
		for step in MusicTypes.STEP_COUNT:
			var b := _buttons[lane * MusicTypes.STEP_COUNT + step]
			var t := _cell_tween(b)
			t.tween_interval((step + lane * 2) * 0.025)
			t.tween_property(b, "scale", Vector2.ONE * 1.25, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# CLEAR: notes vanish left to right instead of all at once.
func _clear_cascade() -> void:
	if _clearing:
		return
	_clearing = true
	_sfx(_remove_player, 0.7)
	var n := 0
	for step in MusicTypes.STEP_COUNT:
		for lane in MusicTypes.LANE_COUNT:
			if _composition.is_active(lane, step):
				MusicBus.cell_toggle_requested.emit(lane, step)
				n += 1
				if n % 2 == 0:
					await get_tree().create_timer(0.02).timeout
	_clearing = false


func _burst(b: Control, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 8
	p.lifetime = 0.4
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 130.0
	p.gravity = Vector2(0, 250)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([color.lerp(Color.WHITE, 0.4), Color(color, 0.0)])
	p.color_ramp = ramp
	add_child(p)
	p.global_position = b.global_position + b.size / 2.0
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


# ------------------------------------------------------------ FINISHED button

func _on_fin_hover(entering: bool) -> void:
	if _finished_button.disabled:
		return
	_kill(_finished_tween)
	_finished_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_finished_tween.tween_property(_finished_button, "scale", Vector2.ONE * (1.1 if entering else 1.0), 0.18)
	_finished_tween.tween_property(_finished_button, "rotation_degrees", -2.0 if entering else 0.0, 0.18)
	_finished_tween.tween_property(_finished_button, "modulate", Color(1.25, 1.2, 1.2) if entering else Color.WHITE, 0.18)
	if entering:
		_sfx(_hover_player, randf_range(0.95, 1.05))


func _on_fin_down() -> void:
	if _finished_button.disabled:
		return
	_kill(_finished_tween)
	_finished_tween = create_tween()
	_finished_tween.tween_property(_finished_button, "scale", Vector2.ONE * 0.9, 0.06)


func _on_fin_up() -> void:
	if _finished_button.disabled:
		return
	_kill(_finished_tween)
	_finished_tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_finished_tween.tween_property(_finished_button, "scale", Vector2.ONE * (1.1 if _finished_button.is_hovered() else 1.0), 0.4)


# ------------------------------------------------------------ audio

func _make_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	add_child(p)
	return p


func _sfx(player: AudioStreamPlayer, pitch: float) -> void:
	if player.stream:
		player.pitch_scale = pitch
		player.play()


# ------------------------------------------------------------ drawing

# One shaded block per bar. _bars and _grid share the same rect, so grid-local coords work.
func _draw_bars() -> void:
	for first_step in range(0, MusicTypes.STEP_COUNT, MusicTypes.STEPS_PER_BAR):
		var rect := _column_rect(first_step).merge(_column_rect(first_step + MusicTypes.STEPS_PER_BAR - 1))
		_bars.draw_style_box(_bar_style, rect.grow(bar_gap))


func _draw_playing_column() -> void:
	if _playing_step >= 0:
		_column.draw_style_box(_column_style, _column_rect(_playing_step).grow(bar_gap / 2.0))


# Grid-local rect covering the visible cells of a step, all lanes.
func _column_rect(step: int) -> Rect2:
	var top := _buttons[step]
	var bottom := _buttons[(MusicTypes.LANE_COUNT - 1) * MusicTypes.STEP_COUNT + step]
	var side := _cell_side()
	var x := top.position.x + (top.size.x - side) / 2.0
	var y := top.position.y + (top.size.y - side) / 2.0
	var bottom_y := bottom.position.y + (bottom.size.y + side) / 2.0
	return Rect2(x, y, side, bottom_y - y)


func _cell_center_x(step: int) -> float:
	var cell := _buttons[step]
	return cell.global_position.x + cell.size.x / 2.0


# Cells keep their texture square inside a possibly non-square button.
func _cell_side() -> float:
	return minf(_buttons[0].size.x, _buttons[0].size.y)
