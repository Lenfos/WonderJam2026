extends VBoxContainer
## Debug sequencer grid AND reference example for the real UI. Used by sequencer_test.tscn and
## placeholder_ui.tscn. Only uses MusicBus signals and the data classes (see docs/CONTRACT.md):
## clicks are sent as cell_toggle_requested, the grid is redrawn from composition_changed.
## Keys: C = clear.

const ACTIVE_COLORS: Array[Color] = [Color.ORANGE_RED, Color.GOLD, Color.DODGER_BLUE, Color.MEDIUM_PURPLE]
const IDLE_COLOR := Color(0.25, 0.25, 0.25)
const PLAYHEAD_BOOST := 0.45
const BEATS_PER_BAR := 4
const CELL_SIZE := Vector2(36, 36)

## The UI's own copy of the grid, kept in sync from composition_changed. Never sent to music code.
var _grid := Composition.new()
var _buttons: Array[Button] = []  # index = lane * STEP_COUNT + step
var _playhead: int = -1
var _headline := Label.new()
var _time := Label.new()
var _notes := Label.new()


func _ready() -> void:
	for label in [_headline, _time, _notes]:
		add_child(label)
	var help := Label.new()
	help.text = "C = clear"
	add_child(help)
	for lane in MusicTypes.LANE_COUNT:
		var row := HBoxContainer.new()
		add_child(row)
		var name_label := Label.new()
		name_label.text = str(MusicTypes.Lane.keys()[lane]).capitalize()
		name_label.custom_minimum_size.x = 60
		row.add_child(name_label)
		for step in MusicTypes.STEP_COUNT:
			if step > 0 and step % BEATS_PER_BAR == 0:
				row.add_child(VSeparator.new())
			var button := Button.new()
			button.custom_minimum_size = CELL_SIZE
			button.focus_mode = Control.FOCUS_NONE  # Space must not click the last clicked cell
			button.pressed.connect(func() -> void: MusicBus.cell_toggle_requested.emit(lane, step))
			row.add_child(button)
			_buttons.append(button)

	MusicBus.composition_started.connect(_on_composition_started)
	MusicBus.composition_changed.connect(_on_composition_changed)
	MusicBus.composition_time_changed.connect(func(s: int) -> void: _time.text = "%d s left" % s)
	MusicBus.step_changed.connect(_on_step_changed)
	MusicBus.composition_finished.connect(_on_composition_finished)
	_redraw_all()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		# Only toggles of cells that must change.
		KEY_C:
			for lane in MusicTypes.LANE_COUNT:
				for step in MusicTypes.STEP_COUNT:
					if _grid.is_active(lane, step):
						MusicBus.cell_toggle_requested.emit(lane, step)


func _on_composition_started(p_news: NewsData, _duration_sec: float) -> void:
	_headline.text = p_news.headline
	_grid.clear()
	_playhead = -1
	_redraw_all()


func _on_composition_changed(lane: int, step: int, active: bool) -> void:
	_grid.set_cell(lane, step, active)
	_redraw_cell(lane, step)
	_notes.text = "%d notes" % _grid.count_notes()


func _on_step_changed(step: int) -> void:
	var previous := _playhead
	_playhead = step
	for lane in MusicTypes.LANE_COUNT:
		if previous >= 0:
			_redraw_cell(lane, previous)
		_redraw_cell(lane, step)


func _on_composition_finished(composition: Composition) -> void:
	_playhead = -1
	_redraw_all()
	_time.text = "Done"
	print("composition_finished, %d notes:\n%s" % [composition.count_notes(), composition])


func _redraw_all() -> void:
	for lane in MusicTypes.LANE_COUNT:
		for step in MusicTypes.STEP_COUNT:
			_redraw_cell(lane, step)
	_notes.text = "%d notes" % _grid.count_notes()


func _redraw_cell(lane: int, step: int) -> void:
	var color := ACTIVE_COLORS[lane] if _grid.is_active(lane, step) else IDLE_COLOR
	if step == _playhead:
		color = color.lightened(PLAYHEAD_BOOST)
	_buttons[lane * MusicTypes.STEP_COUNT + step].modulate = color
