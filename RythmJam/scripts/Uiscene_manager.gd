extends Control

@onready var perform_ui: Control = $PerformUI
@onready var placeholder_ui: VBoxContainer = $PlaceholderUI


@onready var _screens := {
	#MusicTypes.Phase.TITLE: $TitleScreen,
	#MusicTypes.Phase.NEWS_INTRO: $NewsIntroScreen,
	MusicTypes.Phase.COMPOSITION: placeholder_ui,
	#MusicTypes.Phase.COMPOSITION_REVIEW: $ReviewScreen,
	MusicTypes.Phase.PERFORMANCE: perform_ui,
	#MusicTypes.Phase.RESULTS: $ResultsScreen,
	#MusicTypes.Phase.GAME_OVER: $GameOverScreen,
}
""""
func _ready() -> void:
	MusicBus.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(MusicBus.get_current_phase())   # pas de signal au lancement

func _on_phase_changed(phase: MusicTypes.Phase) -> void:
	for p in _screens:
		_screens[p].visible = (p == phase)
		print(phase)"""
