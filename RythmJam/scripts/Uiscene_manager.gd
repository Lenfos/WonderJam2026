extends Control

@onready var placeholder_ui: VBoxContainer = $PlaceholderUI
@onready var start_menu: Control = $StartMenu
@onready var performance: Control = $Performance
@onready var performance_logic: Node2D = $"../../../PerformanceLogic"
@onready var performance_phase: PerformancePhase = $"../../../MusicSystem/PerformancePhase"
@onready var composition_phase: CompositionPhase = $"../../../MusicSystem/CompositionPhase"
@export var news: NewsData = preload("res://data/news/cat_mayor.tres")

func _ready() -> void:
	MusicBus.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(MusicBus.get_current_phase())   # pas de signal au lancement
	performance.visible = false
	performance_logic.visible = false

func _on_phase_changed(phase: MusicTypes.Phase) -> void:
	match phase:
		MusicTypes.Phase.COMPOSITION:
			start_menu.visible = false
			composition_phase.start(news)
		MusicTypes.Phase.COMPOSITION_REVIEW:
			pass
		MusicTypes.Phase.PERFORMANCE:
			performance.visible = true
			performance_logic.visible = true
			performance_phase.start(MusicBus.get_current_news(), composition_phase._composition, 1)
		MusicTypes.Phase.GAME_OVER:
			pass
