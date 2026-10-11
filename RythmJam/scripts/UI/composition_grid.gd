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

@onready var _grid: GridContainer = %Grid
@onready var _bars: Control = %Bars
@onready var _column: Control = %PlayingColumn
@onready var _playhead: Control = %Playhead
@onready var _finished_button: TextureButton = %finishedButton

var _buttons: Array[TextureButton] = []  # index = lane * STEP_COUNT + step
var _beat_length := 0.0
var _playing_step := -1
var _bar_style := StyleBoxFlat.new()
var _column_style := StyleBoxFlat.new()


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
	_set_playing(false)


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


func _on_composition_started(news: NewsData, _duration_sec: float) -> void:
	_beat_length = 60.0 / news.bpm
	for button in _buttons:
		button.texture_normal = cell_texture
	_set_playing(true)


func _on_composition_changed(lane: int, step: int, active: bool) -> void:
	_buttons[lane * MusicTypes.STEP_COUNT + step].texture_normal = active_cell_texture if active else cell_texture


# Ends the composition early: the music side answers with composition_finished.
func _on_finished_pressed() -> void:
	MusicBus.finish_composition_requested.emit()


func _set_playing(playing: bool) -> void:
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
