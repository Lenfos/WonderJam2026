extends Control

@export var receptor_rects: Array[TextureRect] = []
@export var spawner: Node2D

@export_group("Start prompt")
## Starts the performance once the prompt shows. Space by default.
@export var start_action: StringName = &"start_composition"
## Seconds between entering PERFORMANCE and showing the prompt: the review's transition plays
## meanwhile (its transition_hold + ~0.5 s exit), and the start key is ignored until then.
@export var start_prompt_delay := 2.6
## Seconds of one prompt fade (out, then in again).
@export var start_prompt_blink_sec := 0.6

@onready var crowd: Control = $Crowd
@onready var _start_prompt: Label = %StartPrompt
var score := 0
var _waiting_start := false
var _prompt_tween: Tween

func _ready():
	spawner.hit_position_ready.connect(_on_hit_position_ready)
	MusicBus.phase_changed.connect(_on_phase_changed)

func addScore(points):
	score += points
	if score <= 0:
		score = 0
	crowd.set_score(score)

func _on_hit_position_ready(positions: Array[Vector2]):
	return


# _input, not _unhandled_input: a focused button must not swallow the start key.
func _input(event: InputEvent) -> void:
	if _waiting_start and event.is_action_pressed(start_action):
		get_viewport().set_input_as_handled()
		_hide_start_prompt()
		MusicBus.performance_start_requested.emit()


# Entering PERFORMANCE: nothing plays until the prompt shows and the player presses start.
func _on_phase_changed(phase: MusicTypes.Phase) -> void:
	_hide_start_prompt()
	if phase == MusicTypes.Phase.PERFORMANCE:
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
