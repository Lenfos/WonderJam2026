extends Control

@export var receptor_rects: Array[TextureRect] = []
@export var spawner: Node2D   
@onready var crowd: Control = $Crowd
var score := 0

func _ready():
	spawner.hit_position_ready.connect(_on_hit_position_ready)

func addScore(points):
	score += points
	if score <= 0:
		score = 0
	crowd.set_score(score)
	
func _on_hit_position_ready(positions: Array[Vector2]):
	return
	
