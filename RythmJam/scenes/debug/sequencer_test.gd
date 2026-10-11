extends Node
## Debug harness for the COMPOSITION phase alone, without the GameManager: a grid UI plus the
## music nodes. Used by sequencer_test.tscn (debug grid) and composition_test.tscn (real UI).
## Keys: Space = start (restart), E = finish early (debug grid keys: C = clear, R = random fill).

## Game-flow side, not UI: in the game, the GameManager starts and ends the phase.
@export var news: NewsData = preload("res://data/news/cat_mayor.tres")

## Starts the phase on launch instead of waiting for Space.
@export var autostart := false

@onready var _phase: CompositionPhase = $CompositionPhase


func _ready() -> void:
	# Stands in for the GameManager, which answers this request in the game.
	MusicBus.finish_composition_requested.connect(_phase.finish_early)
	if autostart:
		_phase.start(news)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_phase.start(news)
		KEY_E:
			_phase.finish_early()
