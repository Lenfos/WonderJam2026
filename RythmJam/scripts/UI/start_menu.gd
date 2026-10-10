extends Control

@export var hover_sfx: AudioStream
@export var click_sfx: AudioStream
@export var whoosh_sfx: AudioStream   # son du slide
@export var blip_sfx: AudioStream     # son machine à écrire
@export var music: AudioStream
@export_file("*.tscn") var game_scene: String = "res://scenes/game.tscn"
@export var slide_distance := 0.0
@export var char_delay := 0.03      # secondes entre deux lettres (plus petit = plus rapide)
@export var newline_pause := 0.5    # pause à chaque retour à la ligne

@onready var bg: TextureRect = $TextureRect
@onready var menu_content: Control = $TextureRect/StartMenu
@onready var logo: Control = %logo
@onready var play_button: TextureButton = %playButton
@onready var quit_button: TextureButton = %quitButton

@onready var news: Control = $TextureRect/News
@onready var character: TextureRect = $TextureRect/News/character
@onready var dialogue_bg: TextureRect = $TextureRect/News/DialogueBG
@onready var dialogue_label: Label = $TextureRect/News/DialogueBG/DialogueLabel
@onready var start_button: TextureButton = $TextureRect/News/startButton

var _menu_buttons: Array[TextureButton] = []
var _all_buttons: Array[TextureButton] = []
var _tweens: Dictionary = {}
var _logo_tweens: Array[Tween] = []
var _menu_home: Vector2
var _news_home: Vector2
var _char_home: Vector2
var _last_char := 0

var _fade: ColorRect
var _hover_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer
var _whoosh_player: AudioStreamPlayer
var _blip_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer


func _ready() -> void:
	_menu_buttons = [play_button, quit_button]
	_all_buttons = [play_button, quit_button, start_button]
	_setup_audio()
	_setup_fade()

	# On attend que les Container calculent les tailles
	await get_tree().process_frame

	_menu_home = menu_content.position
	_news_home = news.position
	_char_home = character.position

	for b in _all_buttons:
		b.pivot_offset = b.size / 2.0
		b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
		b.mouse_entered.connect(_on_hover.bind(b, true))
		b.mouse_exited.connect(_on_hover.bind(b, false))
		b.focus_entered.connect(_on_hover.bind(b, true))
		b.focus_exited.connect(_on_hover.bind(b, false))
		b.button_down.connect(_on_press.bind(b))
		b.button_up.connect(_on_release.bind(b))
	play_button.pressed.connect(_on_play)
	quit_button.pressed.connect(_on_quit)
	start_button.pressed.connect(_on_start)

	_prepare_news()
	_play_intro()


# ------------------------------------------------------------ setup

func _make_player(stream: AudioStream, db := 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _sfx(p: AudioStreamPlayer, pitch := 1.0) -> void:
	if p.stream:
		p.pitch_scale = pitch
		p.play()


func _setup_audio() -> void:
	_hover_player = _make_player(hover_sfx, -15.0)
	_click_player = _make_player(click_sfx, 10.0)
	_whoosh_player = _make_player(whoosh_sfx)
	_blip_player = _make_player(blip_sfx, -15.0)
	_music_player = _make_player(music, -80.0)
	if music:
		_music_player.play()
		create_tween().tween_property(_music_player, "volume_db", -15.0, 2.0)


func _setup_fade() -> void:
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)  # dernier enfant = dessiné par-dessus tout
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.6)


func _prepare_news() -> void:
	# État "caché" de la partie News, avant l'arrivée
	character.pivot_offset = Vector2(character.size.x / 2.0, character.size.y)
	character.position.x += 300.0  # arrivera plus vite que le décor
	dialogue_bg.pivot_offset = Vector2(dialogue_bg.size.x, dialogue_bg.size.y * 0.85)  # côté de la queue de bulle
	dialogue_bg.scale = Vector2.ZERO
	dialogue_label.visible_characters = 0
	start_button.scale = Vector2.ZERO
	start_button.modulate.a = 0.0


# ------------------------------------------------------------ intro du menu

func _play_intro() -> void:
	var logo_target := logo.position
	logo.position.x -= 500.0
	logo.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(logo, "position:x", logo_target.x, 0.7).set_delay(0.3)
	t.tween_property(logo, "modulate:a", 1.0, 0.4).set_delay(0.3)

	var delay := 0.8
	for b in _menu_buttons:
		b.scale = Vector2.ZERO
		b.modulate.a = 0.0
		var bt := create_tween().set_parallel(true)
		bt.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		bt.tween_property(b, "scale", Vector2.ONE, 0.45).set_delay(delay)
		bt.tween_property(b, "modulate:a", 1.0, 0.25).set_delay(delay)
		delay += 0.15

	await get_tree().create_timer(delay + 0.4).timeout
	for b in _menu_buttons:
		b.set_meta("ready", true)
	play_button.grab_focus()
	_animate_logo(logo_target.y)


func _animate_logo(base_y: float) -> void:
	var f := create_tween().set_loops()
	f.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	f.tween_property(logo, "position:y", base_y - 6.0, 1.3)
	f.tween_property(logo, "position:y", base_y + 6.0, 1.3)
	var fl := create_tween().set_loops()
	fl.tween_interval(3.5)
	fl.tween_property(logo, "modulate", Color(1.7, 1.35, 1.35), 0.07)
	fl.tween_property(logo, "modulate", Color.WHITE, 0.3)
	_logo_tweens = [f, fl]


# ------------------------------------------------------------ boutons (hover / press)

func _kill(b: Control) -> void:
	if _tweens.has(b) and _tweens[b]:
		_tweens[b].kill()


func _on_hover(b: TextureButton, entering: bool) -> void:
	if not b.get_meta("ready", false):
		return
	_kill(b)
	var t := create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "scale", Vector2.ONE * (1.12 if entering else 1.0), 0.18)
	t.tween_property(b, "rotation_degrees", -2.0 if entering else 0.0, 0.18)
	t.tween_property(b, "modulate", Color(1.25, 1.2, 1.2) if entering else Color.WHITE, 0.18)
	_tweens[b] = t
	if entering:
		_sfx(_hover_player, randf_range(0.95, 1.05))


func _on_press(b: TextureButton) -> void:
	if not b.get_meta("ready", false):
		return
	_kill(b)
	var t := create_tween()
	t.tween_property(b, "scale", Vector2.ONE * 0.9, 0.06)
	_tweens[b] = t


func _on_release(b: TextureButton) -> void:
	if not b.get_meta("ready", false):
		return
	_kill(b)
	var target := 1.12 if (b.is_hovered() or b.has_focus()) else 1.0
	var t := create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "scale", Vector2.ONE * target, 0.4)
	_tweens[b] = t


# ------------------------------------------------------------ PLAY : slide vers News

# Déplace le menu ET la partie News ensemble
func _slide(x_offset: float, dur: float, trans: Tween.TransitionType, ease_type: Tween.EaseType) -> Tween:
	var t := create_tween().set_parallel(true).set_trans(trans).set_ease(ease_type)
	t.tween_property(menu_content, "position:x", _menu_home.x + x_offset, dur)
	t.tween_property(news, "position:x", _news_home.x + x_offset, dur)
	return t


func _on_play() -> void:
	for b in _menu_buttons:
		b.disabled = true
		b.set_meta("ready", false)
		b.focus_mode = Control.FOCUS_NONE
	_sfx(_click_player)

	# Distance = écart entre le menu et News (News doit être pile à droite du menu)
	var dist := slide_distance if slide_distance > 0.0 else _news_home.x - _menu_home.x
	# 1) Petit recul (anticipation)
	await _slide(30.0, 0.15, Tween.TRANS_QUAD, Tween.EASE_OUT).finished

	# 2) Le slide vers la gauche
	_sfx(_whoosh_player)
	var s := _slide(-dist, 0.8, Tween.TRANS_EXPO, Tween.EASE_IN_OUT)

	# Le perso arrive plus vite que le décor, avec un petit rebond (parallaxe)
	var ct := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ct.tween_property(character, "position:x", _char_home.x, 0.9).set_delay(0.25)

	await s.finished
	for lt in _logo_tweens:
		lt.kill()  # inutile de faire flotter un logo hors écran
	_play_news_intro()


func _on_quit() -> void:
	for b in _menu_buttons:
		b.disabled = true
		b.set_meta("ready", false)
	_sfx(_click_player)
	var t := create_tween().set_parallel(true)
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	t.tween_property(_music_player, "volume_db", -80.0, 0.35)
	await t.finished
	get_tree().quit()


# ------------------------------------------------------------ intro de News

func _play_news_intro() -> void:
	_start_news_idle()

	# 1) La bulle pop depuis le côté du perso
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(dialogue_bg, "scale", Vector2.ONE, 0.35)
	await t.finished

	# 2) Texte en machine à écrire
	await _typewriter()

	# 3) Le bouton START pop avec un rebond élastique
	var fade_in := create_tween()
	fade_in.tween_property(start_button, "modulate:a", 1.0, 0.2)
	var st := create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	st.tween_property(start_button, "scale", Vector2.ONE, 0.6)
	await st.finished
	start_button.set_meta("ready", true)
	start_button.grab_focus()
	_start_glow()


func _typewriter() -> void:
	var text := dialogue_label.text
	dialogue_label.visible_characters = 0
	for i in text.length():
		dialogue_label.visible_characters = i + 1
		var c := text[i]
		if c == "\n":
			await get_tree().create_timer(newline_pause).timeout
		elif c in [".", "!", "?"]:
			await get_tree().create_timer(char_delay + 0.25).timeout
		elif c == ",":
			await get_tree().create_timer(char_delay + 0.12).timeout
		else:
			if c != " " and i % 3 == 0:
				_sfx(_blip_player, randf_range(0.9, 1.15))
			await get_tree().create_timer(char_delay).timeout
	dialogue_label.visible_characters = -1



func _start_news_idle() -> void:
	# Le perso "respire" (squash & stretch depuis les pieds)
	var c := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	c.tween_property(character, "scale", Vector2(1.02, 0.97), 1.0)
	c.tween_property(character, "scale", Vector2(0.99, 1.02), 1.0)
	# La bulle se balance légèrement
	var b := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	b.tween_property(dialogue_bg, "rotation_degrees", 1.5, 1.4)
	b.tween_property(dialogue_bg, "rotation_degrees", -1.5, 1.4)


func _start_glow() -> void:
	# self_modulate pour ne pas entrer en conflit avec le hover (qui utilise modulate)
	var g := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	g.tween_property(start_button, "self_modulate", Color(1.4, 1.25, 1.25), 0.7)
	g.tween_property(start_button, "self_modulate", Color.WHITE, 0.7)


# ------------------------------------------------------------ START

func _on_start() -> void:
	start_button.disabled = true
	start_button.set_meta("ready", false)
	_sfx(_click_player)
	_shake(character)
	var t := create_tween().set_parallel(true)
	t.tween_property(_fade, "color:a", 1.0, 0.5).set_delay(0.2)
	t.tween_property(_music_player, "volume_db", -80.0, 0.7)
	await t.finished
	get_tree().change_scene_to_file(game_scene)


func _shake(node: Control, strength := 6.0, duration := 0.2) -> void:
	var origin := node.position
	var t := create_tween()
	for i in 6:
		t.tween_property(node, "position",
			origin + Vector2(randf_range(-strength, strength), randf_range(-strength, strength)),
			duration / 6.0)
	t.tween_property(node, "position", origin, 0.03)
