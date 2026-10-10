extends VBoxContainer
## Placeholder UI of scenes/main.tscn, until the real UI scene replaces it under UIRoot.
## Also a reference example of the whole contract (docs/CONTRACT.md): it only uses MusicBus
## (requests out; state signals and getters in) and the shared data classes, never a music node.
## The composition grid is the debug sequencer grid.

const SEQUENCER_GRID := preload("res://scenes/debug/sequencer_grid.tscn")
## Phases that show the grid: composing it, reviewing it, hearing it played.
const GRID_PHASES := [MusicTypes.Phase.COMPOSITION, MusicTypes.Phase.COMPOSITION_REVIEW, MusicTypes.Phase.PERFORMANCE]

var _phase_label := Label.new()
var _news_label := Label.new()
var _audimat_label := Label.new()
var _info_label := Label.new()
var _song_time_label := Label.new()
## MusicTypes.Phase -> the Button shown in that phase. PERFORMANCE has none.
var _buttons := {}
var _grid: Control


func _ready() -> void:
	for label in [_phase_label, _news_label, _audimat_label, _info_label, _song_time_label]:
		add_child(label)
	var bar := HBoxContainer.new()
	add_child(bar)
	_add_button(bar, MusicTypes.Phase.TITLE, "Jouer", MusicBus.start_game_requested)
	_add_button(bar, MusicTypes.Phase.NEWS_INTRO, "Continuer", MusicBus.continue_requested)
	_add_button(bar, MusicTypes.Phase.COMPOSITION, "J'ai fini", MusicBus.finish_composition_requested)
	_add_button(bar, MusicTypes.Phase.COMPOSITION_REVIEW, "Continuer", MusicBus.continue_requested)
	_add_button(bar, MusicTypes.Phase.GAME_OVER, "Rejouer", MusicBus.restart_requested)
	_grid = SEQUENCER_GRID.instantiate()
	add_child(_grid)

	MusicBus.phase_changed.connect(_on_phase_changed)
	MusicBus.game_started.connect(_on_game_started)
	MusicBus.composition_evaluated.connect(_on_composition_evaluated)
	MusicBus.performance_started.connect(_on_performance_started)
	MusicBus.countdown_beat.connect(_on_countdown_beat)
	MusicBus.anchor_line_changed.connect(_on_anchor_line_changed)
	MusicBus.audimat_changed.connect(func(audimat: int) -> void: _audimat_label.text = "Audimat : %d" % audimat)
	MusicBus.game_finished.connect(_on_game_finished)
	# phase_changed only fires on transitions: read the starting phase once.
	_on_phase_changed(MusicBus.get_current_phase())


# Per-frame reads go through the getters, not signals. Only processed during PERFORMANCE.
func _process(_delta: float) -> void:
	_song_time_label.text = "Temps du morceau : %.2f s" % MusicBus.get_song_time()


# Shows the phase's button and widgets. Texts come from the phase's own signals, which fire right after.
func _on_phase_changed(phase: MusicTypes.Phase) -> void:
	_phase_label.text = "Phase : %s" % MusicTypes.Phase.keys()[phase]
	for button_phase in _buttons:
		_buttons[button_phase].visible = button_phase == phase
	_grid.visible = phase in GRID_PHASES
	_song_time_label.visible = phase == MusicTypes.Phase.PERFORMANCE
	set_process(phase == MusicTypes.Phase.PERFORMANCE)
	match phase:
		MusicTypes.Phase.TITLE:
			_news_label.text = ""
			_audimat_label.text = ""
			_info_label.text = "Appuie sur Jouer"
		MusicTypes.Phase.COMPOSITION:
			_info_label.text = "Compose ! Clique les cases, puis J'ai fini"


func _on_game_started(news: NewsData) -> void:
	_news_label.text = news.headline
	_audimat_label.text = "Audimat : %d" % MusicBus.get_audimat()
	_info_label.text = "FLASH SPÉCIAL : %s" % news.headline


func _on_composition_evaluated(quality: float, multiplier: float, comments: PackedStringArray) -> void:
	_info_label.text = "Qualité : %d %%   Multiplicateur : x%.2f\n%s" % [roundi(quality * 100.0), multiplier, "\n".join(comments)]


func _on_performance_started(chart: Array, lead_time_sec: float) -> void:
	_info_label.text = "%d notes à jouer, départ dans %.1f s" % [chart.size(), lead_time_sec]


func _on_countdown_beat(beats_left: int) -> void:
	_info_label.text = "%d..." % beats_left if beats_left > 0 else "GO !"


func _on_anchor_line_changed(line_index: int) -> void:
	_info_label.text = "Présentateur : « %s »" % MusicBus.get_current_news().anchor_lines[line_index]


func _on_game_finished(audimat: int) -> void:
	_info_label.text = "FIN DE L'ÉMISSION\n%s\n%d téléspectateurs" % [MusicBus.get_current_news().headline, audimat]


func _add_button(bar: HBoxContainer, phase: MusicTypes.Phase, text: String, request: Signal) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(request.emit)
	bar.add_child(button)
	_buttons[phase] = button
