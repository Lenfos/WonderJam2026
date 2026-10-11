extends Control

@export var person_texture: Texture2D
@export var max_people := 120
@export var score_per_person := 10      # 1 spectateur tous les X points
@export var rows := 4
@export var person_height := 48.0       # hauteur d'un spectateur au premier plan
@export var back_row_scale := 0.75      # taille du dernier rang (effet de profondeur)
@export var x_jitter := 14.0
@export var y_jitter := 10.0
@export var spawn_interval := 0.06      # délai entre deux apparitions quand le score saute
@export var use_palette := false
@export var palette: Array[Color] = []  # utilisé si use_palette est coché
@export_range(0.0, 0.9) var center_gap := 0.5   # part de la largeur laissée vide au centre (0.5 = la moitié)
var _slots: Array[Dictionary] = []
var _shown := 0
var _revealing := false
var _target := 0
var _spawned: Array[Control] = []

var _people: Array[Control] = []
var _hop_timer: Timer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hop_timer = Timer.new()
	_hop_timer.wait_time = 0.25
	_hop_timer.timeout.connect(_random_hop)
	add_child(_hop_timer)
	_hop_timer.start()
	await get_tree().process_frame
	_build_slots()

func _random_hop() -> void:
	if _people.is_empty():
		return
	var p: Control = _people.pick_random()
	if not is_instance_valid(p) or p.has_meta("hopping"):
		return
	p.set_meta("hopping", true)
	var y := p.position.y
	var t := create_tween()
	t.tween_property(p, "position:y", y - randf_range(5.0, 10.0), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(p, "position:y", y, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await t.finished
	if is_instance_valid(p):
		p.remove_meta("hopping")


func _build_slots() -> void:
	var per_row := int(ceil(float(max_people) / rows))
	var per_side := int(ceil(per_row / 2.0))
	var side_w := size.x * (1.0 - center_gap) / 2.0
	var row_spacing := size.y / float(maxi(rows, 1))

	for r in rows:
		var depth := 1.0 if rows == 1 else float(r) / float(rows - 1)   # 0 = fond, 1 = devant
		var s := lerpf(back_row_scale, 1.0, depth)
		for side in 2:
			var x_start := 0.0 if side == 0 else size.x - side_w
			for c in per_side:
				var x := x_start + (c + 0.5) * side_w / per_side + randf_range(-x_jitter, x_jitter)
				var y := (r + 1) * row_spacing + randf_range(-y_jitter, y_jitter)
				_slots.append({"pos": Vector2(x, y), "row": r, "depth": depth, "scale": s})

	_slots.shuffle()                 # ordre d'apparition aléatoire
	_slots.resize(mini(_slots.size(), max_people))


# À appeler à chaque changement de score
func set_score(score: int) -> void:
	_target = clampi(score / score_per_person, 0, _slots.size())
	if not _revealing:
		_update()


func reset() -> void:
	for c in get_children():
		c.queue_free()
	_spawned.clear()
	_shown = 0
	_target = 0
	_slots.clear()
	_build_slots()


# Fait converger le nombre de spectateurs vers la cible, dans les deux sens
func _update() -> void:
	_revealing = true
	while _shown != _target:
		if _shown < _target:
			_spawn(_slots[_shown])
			_shown += 1
		else:
			_shown -= 1
			_despawn(_spawned.pop_back())
		await get_tree().create_timer(spawn_interval).timeout
	_revealing = false


# Un seul tween "actif" par spectateur : le nouveau remplace l'ancien
func _track(p: Control) -> Tween:
	if p.has_meta("tween"):
		var old: Tween = p.get_meta("tween")
		if old and old.is_valid():
			old.kill()
	var t := p.create_tween()   # lié au spectateur : il disparaît avec lui
	p.set_meta("tween", t)
	return t


func _spawn(slot: Dictionary) -> void:
	var p := TextureRect.new()
	p.texture = person_texture
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var h: float = person_height * slot["scale"]
	var aspect := 1.0
	if person_texture:
		aspect = float(person_texture.get_width()) / float(person_texture.get_height())
	p.size = Vector2(h * aspect, h)
	var feet: Vector2 = slot["pos"]
	var target_pos := feet - Vector2(p.size.x / 2.0, p.size.y)
	p.pivot_offset = Vector2(p.size.x / 2.0, p.size.y)
	p.modulate = _random_color(slot["depth"])
	p.z_index = slot["row"]

	p.position = target_pos + Vector2(0, 24)
	p.scale = Vector2.ZERO
	var base_alpha := p.modulate.a
	p.modulate.a = 0.0
	add_child(p)
	_spawned.append(p)

	var t := _track(p)
	t.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(p, "scale", Vector2.ONE, 0.4)
	t.tween_property(p, "position:y", target_pos.y, 0.4)
	t.tween_property(p, "modulate:a", base_alpha, 0.2)
	await t.finished
	_idle(p, target_pos.y)


func _despawn(p: Control) -> void:
	if not is_instance_valid(p):
		return
	var t := _track(p)   # coupe l'animation d'apparition ou d'idle en cours
	t.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(p, "scale", Vector2.ZERO, 0.25)
	t.tween_property(p, "position:y", p.position.y + 20.0, 0.25)
	t.tween_property(p, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(p.queue_free)


func _idle(p: Control, base_y: float) -> void:
	if not is_instance_valid(p):
		return
	var t := _track(p)
	t.set_loops()
	t.tween_interval(randf_range(1.5, 5.0))
	t.tween_property(p, "position:y", base_y - randf_range(5.0, 10.0), 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(p, "position:y", base_y, 0.2) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _random_color(depth: float) -> Color:
	var col: Color
	if use_palette and palette.size() > 0:
		col = palette.pick_random()
	else:
		col = Color.from_hsv(randf(), randf_range(0.4, 0.7), randf_range(0.75, 1.0))
	# Les rangs du fond sont plus sombres
	return col.darkened(lerpf(0.35, 0.0, depth))
