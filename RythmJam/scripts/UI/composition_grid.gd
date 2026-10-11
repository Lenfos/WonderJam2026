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
## Seconds of one prompt fade (out, then in again).
@export var start_prompt_blink_sec := 0.6

@export_group("Timer")
## At or below this many seconds left, the timer turns low_time_color.
@export var low_time_sec := 10
@export var low_time_color := Color(1.0, 0.3, 0.3)

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
## Display copy of the grid (docs/CONTRACT.md): which cells the clear key must toggle off.
var _composition := Composition.new()


func _ready() -> void:
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


# _input, not _unhandled_input: a focused button must not swallow the start key.
func _input(event: InputEvent) -> void:
	if (_waiting_start or _playing) and event.is_action_pressed(start_action):
		get_viewport().set_input_as_handled()
		_hide_start_prompt()
		MusicBus.composition_start_requested.emit()
	elif _playing and event.is_action_pressed(clear_action):
		get_viewport().set_input_as_handled()
		for lane in MusicTypes.LANE_COUNT:
			for step in MusicTypes.STEP_COUNT:
				if _composition.is_active(lane, step):
					MusicBus.cell_toggle_requested.emit(lane, step)


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
	_start_prompt.modulate.a = 1.0
	_prompt_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	_prompt_tween.tween_property(_start_prompt, "modulate:a", 0.3, start_prompt_blink_sec)
	_prompt_tween.tween_property(_start_prompt, "modulate:a", 1.0, start_prompt_blink_sec)


func _hide_start_prompt() -> void:
	_waiting_start = false
	_start_prompt.visible = false
	if _prompt_tween:
		_prompt_tween.kill()


func _on_composition_started(news: NewsData, _duration_sec: float) -> void:
	_hide_start_prompt()
	_beat_length = 60.0 / news.bpm
	_composition.clear()
	for button in _buttons:
		button.texture_normal = cell_texture
	_set_playing(true)


func _on_time_changed(seconds_left: int) -> void:
	_time_label.visible = true
	@warning_ignore("integer_division")
	_time_label.text = "%d:%02d" % [seconds_left / 60, seconds_left % 60]
	_time_label.modulate = low_time_color if seconds_left <= low_time_sec else Color.WHITE


func _on_composition_changed(lane: int, step: int, active: bool) -> void:
	_composition.set_cell(lane, step, active)
	_buttons[lane * MusicTypes.STEP_COUNT + step].texture_normal = active_cell_texture if active else cell_texture


# Ends the composition early: the music side answers with composition_finished.
func _on_finished_pressed() -> void:
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
