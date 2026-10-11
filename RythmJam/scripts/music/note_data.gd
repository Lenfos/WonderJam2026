class_name NoteData
extends RefCounted
## One note of the performance chart (see MusicBus.performance_started). Read it, never edit it.

## Position in the chart: the note_index carried by MusicBus.note_hit / note_missed.
var index: int
## MusicTypes.Lane value.
var lane: int
## MusicBus.get_song_time() at which the note must be hit.
var time_sec: float


func _init(p_index: int, p_lane: int, p_time_sec: float) -> void:
	index = p_index
	lane = p_lane
	time_sec = p_time_sec


## Every active cell of `composition`, played `loops` times in a row, sorted by time then lane.
## `first_beat` is the clock beat of step 0 of the first loop; one step = one beat of `beat_length` s.
static func build_chart(composition: Composition, beat_length: float, first_beat: int, loops: int) -> Array[NoteData]:
	var chart: Array[NoteData] = []
	for loop in loops:
		for step in MusicTypes.STEP_COUNT:
			var beat := first_beat + loop * MusicTypes.STEP_COUNT + step
			for ilane in MusicTypes.LANE_COUNT:
				if composition.is_active(ilane, step):
					chart.append(NoteData.new(chart.size(), ilane, beat * beat_length))
	return chart
