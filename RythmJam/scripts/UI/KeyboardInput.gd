extends MarginContainer

@export var keycodes: Array[Key] = [KEY_D, KEY_F, KEY_J, KEY_K]
@export var beam_width := 0.0   # largeur en pixels, 0 = largeur de la touche
@export var beam_angles: Array[float] = [9.0, 3.0, -3.0, -9.0]   # inclinaison par colonne, en degrés
@export var lane_colors: Array[Color] = [
	Color("#ff2d3d"), Color("#ffd23f"), Color("#3fe0ff"), Color("#b36bff")]
@export var press_sfx: AudioStream
@export var beam_height := 260.0   # hauteur du faisceau de lumière au-dessus de la touche

@onready var keys: Array[Control] = [
	$HBoxContainer/D_Key, $HBoxContainer/F_Key,
	$HBoxContainer/J_Key, $HBoxContainer/K_Key]

var _beams: Array[TextureRect] = []
var _bursts: Array[CPUParticles2D] = []
var _pressed: Array[bool] = [false, false, false, false]
var _tweens: Dictionary = {}
var _sfx_player: AudioStreamPlayer


func _ready() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.stream = press_sfx
	add_child(_sfx_player)

	await get_tree().process_frame   # on attend la taille calculée par le container
	for i in keys.size():
		var k := keys[i]
		k.pivot_offset = k.size / 2.0
		k.resized.connect(func(): k.pivot_offset = k.size / 2.0)
		_beams.append(_make_beam(k, lane_colors[i], i))
		_bursts.append(_make_burst(k, lane_colors[i]))


# ------------------------------------------------------------ création des effets

func _make_beam(k: Control, color: Color, i: int) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(color, 0.8), Color(color, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 1)   # fort en bas, transparent en haut
	tex.fill_to = Vector2(0, 0)
	tex.width = 8
	tex.height = 128

	var w := beam_width if beam_width > 0.0 else k.size.x

	var b := TextureRect.new()
	b.texture = tex
	b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	b.stretch_mode = TextureRect.STRETCH_SCALE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.show_behind_parent = true
	b.size = Vector2(w, beam_height)
	# Centré sur la touche, la base du faisceau est dans la touche
	b.position = Vector2((k.size.x - w) / 2.0, k.size.y * 0.4 - beam_height)
	# Pivot en bas au centre : le faisceau tourne depuis la touche
	b.pivot_offset = Vector2(w / 2.0, beam_height)
	b.rotation_degrees = beam_angles[i] if i < beam_angles.size() else 0.0
	b.modulate.a = 0.0
	k.add_child(b)
	return b


func _make_burst(k: Control, color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 14
	p.lifetime = 0.45
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 450)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([color.lerp(Color.WHITE, 0.4), Color(color, 0.0)])
	p.color_ramp = ramp
	p.position = Vector2(k.size.x / 2.0, k.size.y * 0.2)
	k.add_child(p)
	return p


# ------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var i := keycodes.find(event.physical_keycode)
		if i == -1:
			return
		if event.pressed:
			press(i)
		else:
			release(i)


func _tw(i: int) -> Tween:
	if _tweens.has(i) and _tweens[i]:
		_tweens[i].kill()
	var t := create_tween()
	_tweens[i] = t
	return t


func press(i: int) -> void:
	_pressed[i] = true
	var k := keys[i]
	var tint := lane_colors[i].lerp(Color.WHITE, 0.55)
	var t := _tw(i).set_parallel(true)
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(k, "scale", Vector2.ONE * 0.86, 0.05)
	#t.tween_property(k, "rotation_degrees", randf_range(-3.0, 3.0), 0.05)
	t.tween_property(k, "modulate", tint * 1.15, 0.05)
	t.tween_property(_beams[i], "modulate:a", 0.55, 0.05)
	_bursts[i].restart()
	if press_sfx:
		_sfx_player.pitch_scale = randf_range(0.95, 1.08)
		_sfx_player.play()


func release(i: int) -> void:
	_pressed[i] = false
	var k := keys[i]
	var t := _tw(i).set_parallel(true)
	t.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_property(k, "scale", Vector2.ONE, 0.4)
	t.tween_property(k, "rotation_degrees", 0.0, 0.3)
	t.tween_property(k, "modulate", Color.WHITE, 0.2)
	t.tween_property(_beams[i], "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)


# ------------------------------------------------------------ à appeler depuis ton gameplay

# Note réussie : gros flash + explosion de particules. perfect = version plus forte.
func hit(i: int, perfect := false) -> void:
	var k := keys[i]
	_bursts[i].amount = 26 if perfect else 14
	_bursts[i].restart()
	_beams[i].modulate.a = 1.0
	var t := create_tween().set_parallel(true)
	t.tween_property(_beams[i], "modulate:a", 0.55 if _pressed[i] else 0.0, 0.25)
	var pop := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(k, "scale", Vector2.ONE * (1.3 if perfect else 1.18), 0.08)
	pop.tween_property(k, "scale", Vector2.ONE * (0.86 if _pressed[i] else 1.0), 0.2)


# Note ratée : la touche rougit et tremble
func miss(i: int) -> void:
	var k := keys[i]
	var t := create_tween()
	t.tween_property(k, "modulate", Color(1.0, 0.35, 0.35), 0.04)
	for n in 4:
		t.tween_property(k, "rotation_degrees", 6.0 if n % 2 == 0 else -6.0, 0.04)
	t.tween_property(k, "rotation_degrees", 0.0, 0.04)
	t.tween_property(k, "modulate", Color.WHITE, 0.2)


# À appeler sur chaque temps de la musique : les touches "respirent" en rythme
func beat_pulse(strength := 0.07) -> void:
	for i in keys.size():
		if _pressed[i]:
			continue
		var k := keys[i]
		var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(k, "scale", Vector2.ONE * (1.0 + strength), 0.06)
		t.tween_property(k, "scale", Vector2.ONE, 0.18)
