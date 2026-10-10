extends VBoxContainer
## Debug harness for the COMPOSITION phase alone, without the RoundManager: the debug grid plus
## the music nodes. Keys: Space = start, E = finish early (grid keys: C = clear, R = random fill).

## Round-flow side, not UI: in the game, the RoundManager starts and ends the phase.
@export var news: NewsData = preload("res://data/news/cat_mayor.tres")

@onready var _phase: CompositionPhase = $CompositionPhase


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_phase.start(news)
		KEY_E:
			_phase.finish_early()
