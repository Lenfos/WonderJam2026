extends HBoxContainer
## Debug: one box per lane lights up while its key is held; prints lane + timestamp on press.

const IDLE_COLOR := Color(0.15, 0.15, 0.15)
const HELD_COLOR := Color(0.2, 0.7, 0.3)

var _boxes: Array[ColorRect] = []


func _ready() -> void:
	for lane in MusicTypes.LANE_COUNT:
		var key := InputMap.action_get_events(MusicTypes.lane_action(lane))[0] as InputEventKey
		var label := Label.new()
		label.text = "%s\n%s" % [MusicTypes.Lane.keys()[lane], key.as_text_physical_keycode()]
		var box := ColorRect.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(label)
		add_child(box)
		_boxes.append(box)


func _process(_delta: float) -> void:
	for lane in MusicTypes.LANE_COUNT:
		var held := Input.is_action_pressed(MusicTypes.lane_action(lane))
		_boxes[lane].color = HELD_COLOR if held else IDLE_COLOR


func _input(event: InputEvent) -> void:
	for lane in MusicTypes.LANE_COUNT:
		if event.is_action_pressed(MusicTypes.lane_action(lane)):
			# ponytail: engine uptime, not song time; use MusicClock.get_song_time() once it exists.
			print("lane %d pressed at %.3f s" % [lane, Time.get_ticks_usec() / 1_000_000.0])
