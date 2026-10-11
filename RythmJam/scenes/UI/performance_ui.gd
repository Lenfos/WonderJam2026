extends Control

@onready var crowd: Control = $Crowd
var score := 0

func addScore(points):
	score += points
	if score <= 0:
		score = 0
	crowd.set_score(score)
