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
	_verdict_label.text = high_verdict if total_stars >= high_min_stars \
		else mid_verdict if total_stars >= mid_min_stars else low_verdict

	# Hidden state before the entrance.
	visible = true
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2.ZERO
	var char_home_x := _character.position.x
	_character.position.x += get_viewport_rect().size.x / 2.0
	for i in _bars.size():
		@warning_ignore("integer_division")
		_bars[i].value = clampf(row_stars[i / STAR_COUNT] - i % STAR_COUNT, 0.0, 1.0)
		_bars[i].scale = Vector2.ZERO
	_viewers_label.text = "0 VIEWERS"
	_verdict_label.modulate.a = 0.0
	_menu_button.scale = Vector2.ZERO
	_menu_button.disabled = true

	# Panel pops, character slides in, stars pop row by row, viewers count up, verdict, MENU.
	var t := create_tween()
	t.tween_property(_panel, "scale", Vector2.ONE, panel_pop_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_character, "position:x", char_home_x, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for bar in _bars:
		t.tween_callback(_sfx.bind(_blip_player, randf_range(0.9, 1.15)))
		CompositionReview.tween_star_pop(t, bar, star_pop_duration)
	t.tween_method(_show_viewers, 0, audimat * viewers_per_point, count_up_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_property(_verdict_label, "modulate:a", 1.0, 0.25)
	t.tween_property(_menu_button, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		_menu_button.disabled = false
		_menu_button.grab_focus()
		_start_idle())


func _show_viewers(viewers: int) -> void:
	_viewers_label.text = "%s VIEWERS" % format_viewers(viewers)


# Same idle as the start menu: the character breathes from its feet.
func _start_idle() -> void:
	_character.pivot_offset = Vector2(_character.size.x / 2.0, _character.size.y)
	var c := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	c.tween_property(_character, "scale", Vector2(1.02, 0.97), 1.0)
	c.tween_property(_character, "scale", Vector2(0.99, 1.02), 1.0)


func _on_menu_pressed() -> void:
	_menu_button.disabled = true
	MusicBus.restart_requested.emit()
	# ponytail: full reload is the reset (start menu, grid, notes); a per-screen reset if it gets slow.
	get_tree().reload_current_scene()


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
