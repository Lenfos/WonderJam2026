extends Control
## Composition review, shown over the grid in COMPOSITION_REVIEW: the character slides in from the
## right, the bubble pops, the title types out, the composition gets 1 to 5 stars (half steps) from the
## evaluator's quality, a verdict line types out, then the multiplier counts up and a Continue button.
## Continue plays the transition to the performance.
## Only talks to MusicBus.

const STAR_COUNT := 5
## Stars given for quality 0 and quality 1, snapped to STAR_STEP in between.
const MIN_STARS := 1.0
const MAX_STARS := 5.0
const STAR_STEP := 0.5
## Star pop: spins in from this angle.
const STAR_SPIN_DEGREES := -120.0

@export_group("Stars")
@export var star_texture: Texture2D
@export var star_size := Vector2(40, 38)
## Tint of the empty part of a star.
@export var empty_star_tint := Color(0.2, 0.2, 0.25, 0.35)

@export_group("Verdict")
## Verdict below mid_min_stars.
@export_multiline var low_verdict := "Ouch... the viewers are already zapping."
## Verdict from mid_min_stars to below high_min_stars.
@export_multiline var mid_verdict := "Not bad! The studio is nodding along."
## Verdict from high_min_stars up.
@export_multiline var high_verdict := "Prime time material! Phones are ringing!"
@export var mid_min_stars := 3.0
@export var high_min_stars := 4.5
## Verdict text color per tier.
@export var low_color := Color("#ff4d5a")
@export var mid_color := Color("#2a2a35")
@export var high_color := Color("#e8890c")

@export_group("Timing")
@export var slide_duration := 0.7
@export var bubble_pop_duration := 0.35
@export var star_pop_duration := 0.2
## Seconds per typed character.
@export var char_delay := 0.03
## A blip every this many typed characters (spaces stay silent).
@export var blip_every_chars := 3
## Seconds to count the multiplier up from 0.
@export var multiplier_count_duration := 0.5

@export_group("Juice")
## Darkening of the grid behind the review.
@export var dim_alpha := 0.3
## The bubble pops in tilted by this angle and straightens.
@export var bubble_start_rotation := -6.0
## Bubble and character leave while the transition bands cross. 0 = no exit animation.
@export var exit_duration := 0.3

@export_group("Transition")
## Transition to the performance, same as the start menu's.
@export var transition_text := "ON AIR..."
@export var transition_hold := 2.0
## Empty = the title's font.
@export var transition_font: Font
@export var transition_font_size := 56
@export var transition_font_color := Color.WHITE
## 0 = no outline.
@export var transition_outline_size := 0
@export var transition_outline_color := Color.BLACK

@export_group("Sounds")
## Played when the character slides in (and when the transition bands cross). Empty = silent.
@export var whoosh_sfx: AudioStream
## Typewriter blip, same as the start menu's. Empty = silent.
@export var blip_sfx: AudioStream
@export var blip_volume_db := -15.0
## Played on each star pop (pitch rises star after star). Empty = reuses blip_sfx.
@export var star_sfx: AudioStream
@export var hover_sfx: AudioStream
@export var click_sfx: AudioStream
## Played on a high verdict and when the multiplier lands. Empty = silent.
@export var success_sfx: AudioStream

@onready var _character: TextureRect = $Character
@onready var _bubble: TextureRect = $Bubble
@onready var _rate_label: Label = %RateLabel
@onready var _stars: HBoxContainer = %Stars
@onready var _verdict_label: Label = %VerdictLabel
@onready var _multiplier_label: Label = %MultiplierLabel
@onready var _continue_button: TextureButton = %ContinueButton

var _char_home := Vector2.ZERO
var _bubble_home := Vector2.ZERO
var _star_bars: Array[TextureProgressBar] = []
var _fills: Array[float] = []
var _tweens: Array[Tween] = []
var _btn_tween: Tween
var _button_ready := false
var _final_multiplier := 1.0
var _last_tick_ms := 0
var _dim: ColorRect
var _whoosh_player: AudioStreamPlayer
var _blip_player: AudioStreamPlayer
var _star_player: AudioStreamPlayer
var _hover_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer
var _success_player: AudioStreamPlayer


## Quality 0-1 to stars: MIN_STARS to MAX_STARS in STAR_STEP steps.
static func stars_for(quality: float) -> float:
	return snappedf(lerpf(MIN_STARS, MAX_STARS, clampf(quality, 0.0, 1.0)), STAR_STEP)


## Pops `bar` (scale 0, value = its final fill) inside tween `t`: spins and overshoots in gray like an
## empty star, filling up to its value as it lands.
static func tween_star_pop(t: Tween, bar: TextureProgressBar, duration: float) -> void:
	var fill := bar.value
	bar.value = 0.0
	bar.rotation_degrees = STAR_SPIN_DEGREES
	t.tween_property(bar, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(bar, "rotation_degrees", 0.0, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(bar, "value", fill, duration).set_ease(Tween.EASE_IN)


func verdict_for(stars: float) -> String:
	if stars >= high_min_stars:
		return high_verdict
	if stars >= mid_min_stars:
		return mid_verdict
	return low_verdict


## 0 = low, 1 = mid, 2 = high.
func tier_for(stars: float) -> int:
	if stars >= high_min_stars:
		return 2
	if stars >= mid_min_stars:
		return 1
	return 0


func _ready() -> void:
	visible = false
	_char_home = _character.position
	_bubble_home = _bubble.position
	_character.pivot_offset = Vector2(_character.size.x / 2.0, _character.size.y)
	_bubble.pivot_offset = Vector2(_bubble.size.x, _bubble.size.y * 0.75)  # Tail side, toward the character.
	_continue_button.resized.connect(func() -> void: _continue_button.pivot_offset = _continue_button.size / 2.0)
	_multiplier_label.resized.connect(func() -> void: _multiplier_label.pivot_offset = _multiplier_label.size / 2.0)

	_whoosh_player = _make_player(whoosh_sfx, 0.0)
	_blip_player = _make_player(blip_sfx, blip_volume_db)
	_star_player = _make_player(star_sfx if star_sfx else blip_sfx, -8.0)
	_hover_player = _make_player(hover_sfx, -6.0)
	_click_player = _make_player(click_sfx, 0.0)
	_success_player = _make_player(success_sfx, -2.0)

	# Soft darkening of what is behind the review, drawn first.
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	move_child(_dim, 0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	# A star = a progress bar: the empty star underneath, the filled part over it (0, 0.5 or 1).
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
		_stars.add_child(bar)
		_star_bars.append(bar)

	_continue_button.pressed.connect(_on_continue_pressed)
	_continue_button.mouse_entered.connect(_on_btn_hover.bind(true))
	_continue_button.mouse_exited.connect(_on_btn_hover.bind(false))
	_continue_button.focus_entered.connect(_on_btn_hover.bind(true))
	_continue_button.focus_exited.connect(_on_btn_hover.bind(false))
	_continue_button.button_down.connect(_on_btn_down)
	_continue_button.button_up.connect(_on_btn_up)

	MusicBus.composition_evaluated.connect(_on_composition_evaluated)
	MusicBus.phase_changed.connect(func(phase: MusicTypes.Phase) -> void:
		if phase != MusicTypes.Phase.COMPOSITION_REVIEW:
			_hide())


func _on_composition_evaluated(quality: float, multiplier: float, _comments: PackedStringArray) -> void:
	_kill_tweens()
	var stars := stars_for(quality)
	var tier := tier_for(stars)
	var colors: Array[Color] = [low_color, mid_color, high_color]
	_final_multiplier = multiplier
	_verdict_label.text = verdict_for(stars)
	_verdict_label.add_theme_color_override("font_color", colors[tier])
	# No "x" prefix: Kenney Future draws X like an H.
	_multiplier_label.text = "MULTIPLIER 0.00"

	# Hidden state before the entrance.
	visible = true
	_dim.color.a = 0.0
	_character.position = Vector2(get_viewport_rect().size.x, _char_home.y)
	_character.scale = Vector2.ONE
	_bubble.position = _bubble_home
	_bubble.scale = Vector2.ZERO
	_bubble.rotation_degrees = bubble_start_rotation
	_rate_label.visible_characters = 0
	_verdict_label.visible_characters = 0
	_fills.clear()
	for i in STAR_COUNT:
		var fill := clampf(stars - i, 0.0, 1.0)
		_fills.append(fill)
		_star_bars[i].value = fill
		_star_bars[i].scale = Vector2.ZERO
		_star_bars[i].modulate = Color.WHITE
		_star_bars[i].self_modulate = Color.WHITE
	_stars.scale = Vector2.ONE
	_multiplier_label.modulate = Color(1, 1, 1, 0)
	_multiplier_label.scale = Vector2.ONE
	_multiplier_label.pivot_offset = _multiplier_label.size / 2.0
	_continue_button.scale = Vector2.ZERO
	_continue_button.rotation_degrees = 0.0
	_continue_button.modulate = Color.WHITE
	_continue_button.self_modulate = Color.WHITE
	_continue_button.disabled = true
	_button_ready = false

	# Slide in, bubble pops, title types, stars pop one by one, verdict types, multiplier counts up, Continue.
	var t := _new_tween()
	t.tween_callback(_sfx.bind(_whoosh_player, 1.0))
	t.tween_property(_dim, "color:a", dim_alpha, 0.3)
	t.parallel().tween_property(_character, "position:x", _char_home.x, slide_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_bubble, "scale", Vector2.ONE, bubble_pop_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_bubble, "rotation_degrees", 0.0, bubble_pop_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween_typewriter(t, _rate_label)
	for i in STAR_COUNT:
		t.tween_callback(_star_sfx.bind(i))
		tween_star_pop(t, _star_bars[i], star_pop_duration)
		t.tween_callback(_star_landed.bind(i))
	t.tween_callback(_on_stars_done.bind(tier))
	_tween_typewriter(t, _verdict_label)
	t.tween_property(_multiplier_label, "modulate:a", 1.0, 0.15)
	t.tween_method(_show_multiplier, 0.0, multiplier, multiplier_count_duration) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_callback(_multiplier_landed)
	t.tween_property(_continue_button, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		_continue_button.disabled = false
		_button_ready = true
		_start_idle())


# Types `label` out inside tween `t`, with a blip every few characters like the start menu.
func _tween_typewriter(t: Tween, label: Label) -> void:
	var count := label.text.length()
	t.tween_method(_type_to.bind(label), 0, count, count * char_delay)


func _type_to(shown: int, label: Label) -> void:
	if shown == label.visible_characters:
		return
	label.visible_characters = shown
	if shown % blip_every_chars == 0 and label.text[shown - 1] != " ":
		_sfx(_blip_player, randf_range(0.9, 1.15))


# ------------------------------------------------------------ stars

# The pitch rises star after star; empty stars thud lower.
func _star_sfx(i: int) -> void:
	_sfx(_star_player, 0.85 + i * 0.1 if _fills[i] > 0.0 else 0.6)


func _star_landed(i: int) -> void:
	if _fills[i] <= 0.0:
		return
	var bar := _star_bars[i]
	_burst_at(bar.global_position + bar.size / 2.0, 6 if _fills[i] >= 1.0 else 3, Color(1.0, 0.85, 0.3), 0.5, 100.0)


func _on_stars_done(tier: int) -> void:
	# The whole row swells once.
	_stars.pivot_offset = _stars.size / 2.0
	var t := _new_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_stars, "scale", Vector2.ONE * 1.1, 0.1)
	t.tween_property(_stars, "scale", Vector2.ONE, 0.2)

	if tier == 2:
		_sfx(_success_player, 1.0)
		_burst_at(_stars.global_position + _stars.size / 2.0, 30, Color(1.0, 0.85, 0.3), 1.0, 220.0)
		_hop_character()
	elif tier == 0:
		_shake(_bubble)
		for bar in _star_bars:   # a sad little dimming of the stars
			bar.modulate = Color(0.8, 0.8, 0.9)


# ------------------------------------------------------------ multiplier

func _show_multiplier(value: float) -> void:
	_multiplier_label.text = "MULTIPLIER %.2f" % value
	var now := Time.get_ticks_msec()
	if now - _last_tick_ms > 60:
		_last_tick_ms = now
		var progress := value / maxf(_final_multiplier, 0.001)
		_sfx(_blip_player, 0.8 + progress * 0.7)


func _multiplier_landed() -> void:
	_sfx(_success_player, 1.2)
	_multiplier_label.scale = Vector2.ONE * 1.3
	_multiplier_label.modulate = Color(1.8, 1.6, 1.6)
	var t := _new_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_multiplier_label, "scale", Vector2.ONE, 0.4)
	t.tween_property(_multiplier_label, "modulate", Color.WHITE, 0.4)


# ------------------------------------------------------------ idle

# Same idle as the start menu: the character breathes, the bubble sways. The stars shine in turn
# and the Continue button glows.
func _start_idle() -> void:
	var c := _new_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	c.tween_property(_character, "scale", Vector2(1.02, 0.97), 1.0)
	c.tween_property(_character, "scale", Vector2(0.99, 1.02), 1.0)
	var b := _new_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	b.tween_property(_bubble, "rotation_degrees", 1.5, 1.4)
	b.tween_property(_bubble, "rotation_degrees", -1.5, 1.4)

	var shine := _new_tween().set_loops()
	shine.tween_interval(2.0)
	for i in STAR_COUNT:
		if _fills[i] > 0.0:
			shine.tween_property(_star_bars[i], "self_modulate", Color(1.7, 1.6, 1.3), 0.12)
			shine.tween_property(_star_bars[i], "self_modulate", Color.WHITE, 0.25)

	# self_modulate so it never fights the hover (which uses modulate).
	var g := _new_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	g.tween_property(_continue_button, "self_modulate", Color(1.4, 1.25, 1.25), 0.7)
	g.tween_property(_continue_button, "self_modulate", Color.WHITE, 0.7)


func _hop_character() -> void:
	var y := _char_home.y
	var t := _new_tween()
	t.tween_property(_character, "position:y", y - 28.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_character, "position:y", y, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _shake(node: Control, strength := 6.0, duration := 0.25) -> void:
	var origin := node.position
	var t := _new_tween()
	for i in 6:
		t.tween_property(node, "position",
			origin + Vector2(randf_range(-strength, strength), randf_range(-strength, strength)),
			duration / 6.0)
	t.tween_property(node, "position", origin, 0.03)


func _burst_at(pos: Vector2, amount: int, color: Color, lifetime: float, speed: float) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 300)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([color, Color(color, 0.0)])
	p.color_ramp = ramp
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)


# ------------------------------------------------------------ Continue button

func _kill_btn_tween() -> void:
	if _btn_tween and _btn_tween.is_valid():
		_btn_tween.kill()


func _on_btn_hover(entering: bool) -> void:
	if not _button_ready:
		return
	_kill_btn_tween()
	_btn_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_btn_tween.tween_property(_continue_button, "scale", Vector2.ONE * (1.12 if entering else 1.0), 0.18)
	_btn_tween.tween_property(_continue_button, "rotation_degrees", -2.0 if entering else 0.0, 0.18)
	_btn_tween.tween_property(_continue_button, "modulate", Color(1.25, 1.2, 1.2) if entering else Color.WHITE, 0.18)
	if entering:
		_sfx(_hover_player, randf_range(0.95, 1.05))


func _on_btn_down() -> void:
	if not _button_ready:
		return
	_kill_btn_tween()
	_btn_tween = create_tween()
	_btn_tween.tween_property(_continue_button, "scale", Vector2.ONE * 0.9, 0.06)


func _on_btn_up() -> void:
	if not _button_ready:
		return
	_kill_btn_tween()
	var target := 1.12 if (_continue_button.is_hovered() or _continue_button.has_focus()) else 1.0
	_btn_tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_btn_tween.tween_property(_continue_button, "scale", Vector2.ONE * target, 0.4)


func _on_continue_pressed() -> void:
	if not _button_ready:
		return
	_button_ready = false
	_continue_button.disabled = true
	_sfx(_click_player, 1.0)
	_play_exit()
	_play_transition()


# Bubble shrinks, character leaves, the dim fades, while the transition bands cross over them.
func _play_exit() -> void:
	if exit_duration <= 0.0:
		return
	_kill_tweens()   # stops the idle loops
	var t := create_tween().set_parallel(true)
	t.tween_property(_bubble, "scale", Vector2.ZERO, exit_duration * 0.7) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(_character, "position:x", get_viewport_rect().size.x, exit_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(_dim, "color:a", 0.0, exit_duration)


# ------------------------------------------------------------ transition

# Copy of the start menu's transition: bands cross, the text pops, the performance screen swaps in
# while everything is covered, then the bands leave.
func _play_transition() -> void:
	var vp := get_viewport_rect().size
	var layer := CanvasLayer.new()
	layer.layer = 100  # Above everything.
	# Not a child: phase_changed hides this review, the transition must outlive that.
	get_tree().root.add_child(layer)

	# Black safety background, so no gap shows between the tilted bands. It also blocks clicks
	# on the screens underneath while the transition plays.
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.size = vp
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(black)

	# Two tilted bands: red on top (from the left), blue below (from the right).
	var band_size := Vector2(vp.x * 1.7, vp.y * 0.8)
	var red := _make_band(Color("#ff2d3d"), band_size, -8.0)
	var blue := _make_band(Color("#1f0f8f"), band_size, -8.0)
	layer.add_child(red)
	layer.add_child(blue)

	var red_target := Vector2(vp.x / 2.0, vp.y * 0.3) - band_size / 2.0
	var blue_target := Vector2(vp.x / 2.0, vp.y * 0.7) - band_size / 2.0
	red.position = Vector2(-vp.x * 1.5, red_target.y)
	blue.position = Vector2(vp.x * 2.0, blue_target.y)

	var label := Label.new()
	label.text = transition_text
	label.size = vp
	label.pivot_offset = vp / 2.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var f: Font = transition_font if transition_font else _title_font()
	label.add_theme_font_override("font", f)
	label.add_theme_font_size_override("font_size", transition_font_size)
	label.add_theme_color_override("font_color", transition_font_color)
	label.add_theme_constant_override("outline_size", transition_outline_size)
	label.add_theme_color_override("font_outline_color", transition_outline_color)
	label.scale = Vector2.ZERO
	layer.add_child(label)

	# 1) The bands cross.
	_sfx(_whoosh_player, 1.15)
	var t := layer.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(red, "position:x", red_target.x, 0.5)
	t.tween_property(blue, "position:x", blue_target.x, 0.5).set_delay(0.08)
	t.tween_property(black, "color:a", 1.0, 0.4)
	await t.finished

	# 2) The text pops.
	var lt := layer.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lt.tween_property(label, "scale", Vector2.ONE, 0.3)
	await lt.finished

	# 3) Screen covered: switch to the performance, then hold.
	MusicBus.continue_requested.emit()
	await get_tree().create_timer(transition_hold).timeout

	# 4) Exit: the bands leave the way they came, the text shrinks away.
	var out := layer.create_tween().set_parallel(true)
	out.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	out.tween_property(red, "position:x", vp.x * 2.0, 0.5)
	out.tween_property(blue, "position:x", -vp.x * 1.5, 0.5).set_delay(0.08)
	out.tween_property(label, "scale", Vector2.ZERO, 0.25)
	out.tween_property(black, "color:a", 0.0, 0.3).set_delay(0.2)
	await out.finished

	layer.queue_free()


func _make_band(color: Color, band_size: Vector2, angle: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.size = band_size
	r.pivot_offset = band_size / 2.0
	r.rotation_degrees = angle
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# The title's font, whether it comes from a LabelSettings or from the theme.
func _title_font() -> Font:
	if _rate_label.label_settings and _rate_label.label_settings.font:
		return _rate_label.label_settings.font
	return _rate_label.get_theme_font("font")


# ------------------------------------------------------------ misc

func _hide() -> void:
	_kill_tweens()
	_kill_btn_tween()
	_button_ready = false
	_dim.color.a = 0.0
	visible = false


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


func _new_tween() -> Tween:
	var t := create_tween()
	_tweens.append(t)
	return t


func _kill_tweens() -> void:
	for t in _tweens:
		t.kill()
	_tweens.clear()
