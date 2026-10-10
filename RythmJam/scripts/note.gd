class_name Note
extends PathFollow2D
## Une note qui descend le long d'un Path2D.
## Position et scale sont recalculés chaque frame à partir du temps de la musique.
##
## Structure de scène attendue (note1.tscn) :
##   Note (PathFollow2D)  <- ce script
##   └── Sprite2D

const HIT_FX := preload("res://scenes/hitFX.tscn")

@export var scale_start := 0.3
@export var scale_end := 1.0
@export var ease_curve := 1.0          # >1 = grossit plus tard, <1 = grossit plus tôt
@export var fade_in_speed := 3.0       # plus grand = devient opaque plus vite
## Position de la ligne de frappe sur la courbe (1.0 = tout au bout).
## Mets 0.9 par exemple si ta courbe continue sous la ligne de frappe.
@export_range(0.1, 1.0) var ratio_at_hit := 1.0

var hit_time := 0.0       # = NoteData.time_sec
var travel_time := 2.0    # secondes de descente entre l'apparition et la ligne de frappe

var _done := false

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	loop = false
	progress_ratio = 0.0
	visible = false
	_apply_visuals(0.0)


func _process(_delta: float) -> void:
	# t = 0 à l'apparition, 1 pile sur la ligne de frappe, >1 après
	var t := 1.0 - (hit_time - MusicBus.get_song_time()) / travel_time
	visible = t > 0.0
	t = maxf(t, 0.0)
	progress_ratio = minf(t * ratio_at_hit, 1.0)
	_apply_visuals(minf(t, 1.0))


func _apply_visuals(t: float) -> void:
	var s := lerpf(scale_start, scale_end, pow(t, ease_curve))
	sprite.scale = Vector2.ONE * s
	sprite.modulate.a = clampf(t * fade_in_speed, 0.0, 1.0)
	z_index = int(t * 100.0)   # la note la plus proche passe devant


## Appelé une seule fois, que ce soit un hit ou un miss.
func _finish() -> bool:
	if _done:
		return false
	_done = true
	set_process(false)   # sinon _apply_visuals écrase les tweens
	return true


func hit(color: Color = Color.WHITE) -> void:
	if not _finish():
		return

	# FX : enfant de la scène courante, pas de la note (elle va disparaître)
	var fx := HIT_FX.instantiate()
	get_tree().current_scene.add_child(fx)
	fx.global_position = global_position
	fx.z_index = 200
	if fx is CPUParticles2D:
		fx.color = color

	z_index = 150
	sprite.modulate = Color(3, 3, 3, 1)   # flash HDR (brille avec le Glow)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "scale", sprite.scale * 1.7, 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate", Color(color.r, color.g, color.b, 0.0), 0.15)
	tw.chain().tween_callback(queue_free)


func miss() -> void:
	if not _finish():
		return

	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "modulate", Color(1, 0.2, 0.2, 0.0), 0.35)
	tw.tween_property(sprite, "position:y", 60.0, 0.35)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
