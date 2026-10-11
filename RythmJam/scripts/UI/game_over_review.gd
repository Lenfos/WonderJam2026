extends Control
## Game over review: the panel pops in, composition / performance / total stars pop one by one, the
## audimat counts up as a real-world viewer count, a verdict, then the MENU button (reloads the game).
## Only talks to MusicBus.

const CompositionReview := preload("res://scripts/UI/composition_review.gd")
const STAR_COUNT := CompositionReview.STAR_COUNT

@export_group("Stars")
@export var star_texture: Texture2D
@export var star_size := Vector2(38, 36)
## Tint of the empty part of a star.
@export var empty_star_tint := Color(0.2, 0.2, 0.25, 0.35)

@export_group("Viewers")
## Real viewers per audimat point: 3 000 audimat x 400 = 1.2M viewers.
@export var viewers_per_point := 400
@export var count_up_duration := 1.5

@export_group("Verdict")
@export var low_verdict := "THE VIEWERS ZAPPED AWAY"
@export var mid_verdict := "NOT BAD, YOU COOKED"
@export var high_verdict := "PRIME TIME LEGEND"
@export var mid_min_stars := 3.0
@export var high_min_stars := 4.5

@export_group("Timing")
@export var panel_pop_duration := 0.45
@export var star_pop_duration := 0.15

@export_group("Sounds")
## Played on each star pop. Empty = silent.
@export var blip_sfx: AudioStream
@export var hover_sfx: AudioStream
@export var click_sfx: AudioStream
@export var whoosh_sfx: AudioStream
## Tick du compteur de viewers. Vide = réutilise blip_sfx.
@export var tick_sfx: AudioStream

@export_group("Look")
@export var dim_alpha := 0.45
@export var low_color := Color("#ff4d5a")
@export var mid_color := Color("#2a2a35")
@export var high_color := Color("#e8890c")

@onready var _panel: Control = %Panel
@onready var _character: TextureRect = %Character
@onready var _star_rows: Array[HBoxContainer] = [%CompositionStars, %PerformanceStars, %TotalStars]
@onready var _viewers_label: Label = %ViewersLabel
@onready var _verdict_label: Label = %VerdictLabel
@onready var _menu_button: TextureButton = %MenuButton

var _composition_stars := CompositionReview.MIN_STARS
# Performance accuracy: sum of hit weights over judged notes.
var _hit_weight := 0.0
var _judged_notes := 0
var _bars: Array[TextureProgressBar] = []
var _blip_player: AudioStreamPlayer
var _dim: ColorRect
var _hover_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer
var _whoosh_player: AudioStreamPlayer
var _tick_player: AudioStreamPlayer
var _menu_ready := false
var _menu_tween: Tween
var _viewers_target := 0
var _last_tick := 0


## Hit weight 0-1: the judgment's audimat points relative to a PERFECT.
static func hit_weight(judgment: MusicTypes.Judgment) -> float:
	var points: Dictionary = PerformancePhase.HIT_AUDIMAT
	return float(points[judgment]) / float(points[MusicTypes.Judgment.PERFECT])


## 1 234 -> "1.2K", 3 400 000 -> "3.40M".
static func format_viewers(viewers: int) -> String:
	if viewers >= 1_000_000:
		return "%.2fM" % (viewers / 1_000_000.0)
	if viewers >= 1_000:
		return "%.1fK" % (viewers / 1_000.0)
	return str(viewers)


func _ready() -> void:
	visible = false
	_blip_player = _make_player(blip_sfx, -15.0)
	_hover_player = _make_player(hover_sfx, 0.0)
	_click_player = _make_player(click_sfx, 0.0)
	_whoosh_player = _make_player(whoosh_sfx, 0.0)
	_tick_player = _make_player(tick_sfx if tick_sfx else blip_sfx, -18.0)

	# Fond assombri derrière tout le reste
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	move_child(_dim, 0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	for row in _star_rows:
		for i in STAR_COUNT:
			var bar := TextureProgressBar.new()
			bar.texture_under = star_texture
			bar.texture_progress = star_texture
			bar.tint_under = empty_star_tint
			bar.nine_patch_stretch = true
			bar.custom_minimum_size = star_size
			bar.pivot_offset = star_size / 2.0
			bar.max_value = 1.0
			bar.step = 0.0  # Smooth fill tween; values are already snapped to STAR_STEP.
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(bar)
			_bars.append(bar)

	_menu_button.resized.connect(func() -> void: _menu_button.pivot_offset = _menu_button.size / 2.0)
	_menu_button.pressed.connect(_on_menu_pressed)
	_menu_button.mouse_entered.connect(_on_menu_hover.bind(true))
	_menu_button.mouse_exited.connect(_on_menu_hover.bind(false))
	_menu_button.focus_entered.connect(_on_menu_hover.bind(true))
	_menu_button.focus_exited.connect(_on_menu_hover.bind(false))
	_menu_button.button_down.connect(_on_menu_down)
	_menu_button.button_up.connect(_on_menu_up)
	MusicBus.composition_evaluated.connect(func(quality: float, _m: float, _c: PackedStringArray) -> void:
		_composition_stars = CompositionReview.stars_for(quality))
	MusicBus.performance_started.connect(func(_chart: Array, _lead: float) -> void:
		_hit_weight = 0.0
		_judged_notes = 0)
	MusicBus.note_hit.connect(func(_i: int, _l: int, judgment: MusicTypes.Judgment) -> void:
		_hit_weight += hit_weight(judgment)
		_judged_notes += 1)
	MusicBus.note_missed.connect(func(_i: int, _l: int) -> void: _judged_notes += 1)
	MusicBus.game_finished.connect(_on_game_finished)


func _on_game_finished(audimat: int) -> void:
	var accuracy := _hit_weight / _judged_notes if _judged_notes > 0 else 0.0
	var performance_stars := CompositionReview.stars_for(accuracy)
	var total_stars := snappedf((_composition_stars + performance_stars) / 2.0, CompositionReview.STAR_STEP)
	var row_stars: Array[float] = [_composition_stars, performance_stars, total_stars]

	var tier := 2 if total_stars >= high_min_stars else 1 if total_stars >= mid_min_stars else 0
	var verdicts: Array[String] = [low_verdict, mid_verdict, high_verdict]
	var colors: Array[Color] = [low_color, mid_color, high_color]
	_verdict_label.text = verdicts[tier]
	_verdict_label.add_theme_color_override("font_color", colors[tier])

	# Hidden state before the entrance.
	visible = true
	_dim.color.a = 0.0
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2.ZERO
	_panel.rotation_degrees = -5.0
	var char_home_x := _character.position.x
	_character.position.x += get_viewport_rect().size.x / 2.0
	for i in _bars.size():
		@warning_ignore("integer_division")
		_bars[i].value = clampf(row_stars[i / STAR_COUNT] - i % STAR_COUNT, 0.0, 1.0)
		_bars[i].scale = Vector2.ZERO
	_viewers_target = audimat * viewers_per_point
	_last_tick = 0
	_viewers_label.text = "0 VIEWERS"
	_viewers_label.scale = Vector2.ONE
	_viewers_label.pivot_offset = Vector2(0.0, _viewers_label.size.y / 2.0)
	_verdict_label.pivot_offset = _verdict_label.size / 2.0
	_verdict_label.scale = Vector2.ONE * 1.6
	_verdict_label.modulate.a = 0.0
	_menu_button.pivot_offset = _menu_button.size / 2.0
	_menu_button.scale = Vector2.ZERO
	_menu_button.disabled = true
	_menu_ready = false

	var t := create_tween()
	t.tween_callback(_sfx.bind(_whoosh_player, 1.0))
	t.tween_property(_dim, "color:a", dim_alpha, 0.3)
	t.parallel().tween_property(_panel, "scale", Vector2.ONE, panel_pop_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_panel, "rotation_degrees", 0.0, panel_pop_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_character, "position:x", char_home_x, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	for i in _bars.size():
		# Le pitch monte étoile après étoile
		t.tween_callback(_sfx.bind(_blip_player, 0.85 + i * 0.03))
		CompositionReview.tween_star_pop(t, _bars[i], star_pop_duration)
		if i % STAR_COUNT == STAR_COUNT - 1:
			@warning_ignore("integer_division")
			var row := i / STAR_COUNT
			t.tween_callback(_row_done.bind(row, row_stars[row]))

	t.tween_method(_show_viewers, 0, _viewers_target, count_up_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_callback(_viewers_done)
	t.tween_property(_verdict_label, "modulate:a", 1.0, 0.2)
	t.parallel().tween_property(_verdict_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_menu_button, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		_menu_button.disabled = false
		_menu_ready = true
		_menu_button.grab_focus())


# Chaque rangée de 5 étoiles pulse quand elle est finie ; le total déclenche en plus des étincelles
func _row_done(row_index: int, stars: float) -> void:
	var row := _star_rows[row_index]
	row.pivot_offset = row.size / 2.0
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(row, "scale", Vector2.ONE * 1.12, 0.1)
	t.tween_property(row, "scale", Vector2.ONE, 0.2)
	if row_index == _star_rows.size() - 1:
		_sfx(_click_player, 1.2)
		_burst_at(row, int(stars * 8.0) + 8)


func _viewers_done() -> void:
	_sfx(_click_player, 0.9)
	_viewers_label.scale = Vector2.ONE * 1.3
	_viewers_label.modulate = Color(1.8, 1.6, 1.6)
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_viewers_label, "scale", Vector2.ONE, 0.4)
	t.tween_property(_viewers_label, "modulate", Color.WHITE, 0.4)


func _burst_at(node: Control, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.7
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 220.0
	p.gravity = Vector2(0, 300)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.3), Color(1.0, 0.85, 0.3, 0.0)])
	p.color_ramp = ramp
	add_child(p)
	p.global_position = node.global_position + node.size / 2.0
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _show_viewers(viewers: int) -> void:
	_viewers_label.text = "%s VIEWERS" % format_viewers(viewers)
	# Tick qui monte en pitch pendant le comptage (limité à ~16/s)
	var now := Time.get_ticks_msec()
	if now - _last_tick > 60:
		_last_tick = now
		var progress := float(viewers) / maxf(float(_viewers_target), 1.0)
		_sfx(_tick_player, 0.8 + progress * 0.8)


func _start_idle() -> void:
	_character.pivot_offset = Vector2(_character.size.x / 2.0, _character.size.y)
	var c := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	c.tween_property(_character, "scale", Vector2(1.02, 0.97), 1.0)
	c.tween_property(_character, "scale", Vector2(0.99, 1.02), 1.0)
	# Le panneau se balance très légèrement
	var p := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	p.tween_property(_panel, "rotation_degrees", 0.6, 1.8)
	p.tween_property(_panel, "rotation_degrees", -0.6, 1.8)
	# Le bouton MENU brille doucement (self_modulate pour ne pas gêner le hover)
	var g := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	g.tween_property(_menu_button, "self_modulate", Color(1.4, 1.25, 1.25), 0.7)
	g.tween_property(_menu_button, "self_modulate", Color.WHITE, 0.7)


# ------------------------------------------------------------ bouton MENU

func _kill_menu_tween() -> void:
	if _menu_tween and _menu_tween.is_valid():
		_menu_tween.kill()


func _on_menu_hover(entering: bool) -> void:
	if not _menu_ready:
		return
	_kill_menu_tween()
	_menu_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_menu_tween.tween_property(_menu_button, "scale", Vector2.ONE * (1.12 if entering else 1.0), 0.18)
	_menu_tween.tween_property(_menu_button, "rotation_degrees", -2.0 if entering else 0.0, 0.18)
	_menu_tween.tween_property(_menu_button, "modulate", Color(1.25, 1.2, 1.2) if entering else Color.WHITE, 0.18)
	if entering:
		_sfx(_hover_player, randf_range(0.95, 1.05))


func _on_menu_down() -> void:
	if not _menu_ready:
		return
	_kill_menu_tween()
	_menu_tween = create_tween()
	_menu_tween.tween_property(_menu_button, "scale", Vector2.ONE * 0.9, 0.06)


func _on_menu_up() -> void:
	if not _menu_ready:
		return
	_kill_menu_tween()
	var target := 1.12 if (_menu_button.is_hovered() or _menu_button.has_focus()) else 1.0
	_menu_tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_menu_tween.tween_property(_menu_button, "scale", Vector2.ONE * target, 0.4)


func _on_menu_pressed() -> void:
	_menu_ready = false
	_menu_button.disabled = true
	_sfx(_click_player, 1.0)
	_shake(_character)

	# Fondu au noir au-dessus de tout avant le reload
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	var t := create_tween()
	t.tween_property(black, "color:a", 1.0, 0.45).set_delay(0.15)
	await t.finished

	MusicBus.restart_requested.emit()
	# ponytail: full reload is the reset (start menu, grid, notes); a per-screen reset if it gets slow.
	get_tree().reload_current_scene()


func _shake(node: Control, strength := 6.0, duration := 0.2) -> void:
	var origin := node.position
	var t := create_tween()
	for i in 6:
		t.tween_property(node, "position",
			origin + Vector2(randf_range(-strength, strength), randf_range(-strength, strength)),
			duration / 6.0)
	t.tween_property(node, "position", origin, 0.03)


func _make_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


func _sfx(player: AudioStreamPlayer, pitch: float) -> void:
	if player.stream:
		player.pitch_scale = pitch
		player.play()
