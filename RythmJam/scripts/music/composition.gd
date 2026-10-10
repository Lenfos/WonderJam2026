class_name Composition
extends RefCounted
## The player's sequencer grid: LANE_COUNT x STEP_COUNT on/off cells.
## Pure data, emits nothing: whoever edits it emits MusicBus.composition_changed.
## lane is a MusicTypes.Lane value, step is 0..STEP_COUNT-1.

# Flat storage, index = lane * STEP_COUNT + step.
var _cells: Array[bool] = []


func _init() -> void:
	_cells.resize(MusicTypes.LANE_COUNT * MusicTypes.STEP_COUNT)
	_cells.fill(false)


## Flips a cell and returns its new state.
func toggle(lane: int, step: int) -> bool:
	var i := _index(lane, step)
	_cells[i] = not _cells[i]
	return _cells[i]


func set_cell(lane: int, step: int, active: bool) -> void:
	_cells[_index(lane, step)] = active


func is_active(lane: int, step: int) -> bool:
	return _cells[_index(lane, step)]


## State of every lane at this step, indexed by MusicTypes.Lane.
func get_column(step: int) -> Array[bool]:
	var column: Array[bool] = []
	for lane in MusicTypes.LANE_COUNT:
		column.append(is_active(lane, step))
	return column


## Number of active cells, all lanes included.
func count_notes() -> int:
	return _cells.count(true)


func clear() -> void:
	_cells.fill(false)


## Independent copy: editing one never changes the other.
func duplicate_composition() -> Composition:
	var copy := Composition.new()
	copy._cells = _cells.duplicate()
	return copy


func _to_string() -> String:
	var lines := PackedStringArray()
	for lane in MusicTypes.LANE_COUNT:
		var row: String = str(MusicTypes.Lane.keys()[lane]).rpad(6)
		for step in MusicTypes.STEP_COUNT:
			row += "X" if is_active(lane, step) else "."
		lines.append(row)
	return "\n".join(lines)


# ponytail: bounds checked by assert only (stripped in release builds), a bad index there wraps to another lane.
func _index(lane: int, step: int) -> int:
	assert(lane >= 0 and lane < MusicTypes.LANE_COUNT, "lane out of range")
	assert(step >= 0 and step < MusicTypes.STEP_COUNT, "step out of range")
	return lane * MusicTypes.STEP_COUNT + step
