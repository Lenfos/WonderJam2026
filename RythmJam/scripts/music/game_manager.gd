class_name GameManager
extends Node
## Single source of truth for the game flow (see the phase diagram in docs/CONTRACT.md):
## TITLE -> NEWS_INTRO -> COMPOSITION -> COMPOSITION_REVIEW -> PERFORMANCE -> GAME_OVER -> TITLE.
## Moves on only on MusicBus requests (UI) or phase-end signals (phases). A request that is invalid
## in the current phase is ignored with a warning. State is updated before any signal fires, and
## phase_changed fires before the new phase's own signals.

@export var config: GameConfig = preload("res://data/game_config.tres")
@export var clock: MusicClock
@export var composition_phase: CompositionPhase
@export var performance_phase: PerformancePhase

var _phase := MusicTypes.Phase.TITLE
## The game's news, from NEWS_INTRO to GAME_OVER; null in TITLE.
var _news: NewsData
## News of the latest game, kept across restarts so the next draw picks another one.
var _last_news: NewsData
var _composition: Composition
var _multiplier := 1.0
## Mirrored from MusicBus.audimat_changed, final from performance_finished.
var _audimat := 0


# _enter_tree, not _ready: UI nodes may read the MusicBus getters in their own _ready.
func _enter_tree() -> void:
	MusicBus.set_game_manager(self)


func _ready() -> void:
	MusicBus.start_game_requested.connect(_on_start_game_requested)
	MusicBus.continue_requested.connect(_on_continue_requested)
	MusicBus.finish_composition_requested.connect(_on_finish_composition_requested)
	MusicBus.restart_requested.connect(_on_restart_requested)
	MusicBus.composition_finished.connect(_on_composition_finished)
	MusicBus.performance_finished.connect(_on_performance_finished)
	MusicBus.audimat_changed.connect(func(audimat: int) -> void: _audimat = audimat)


func get_song_time() -> float:
	return clock.get_song_time()


func get_current_phase() -> MusicTypes.Phase:
	return _phase


## null in TITLE.
func get_current_news() -> NewsData:
	return _news


func get_audimat() -> int:
	return _audimat


func get_threshold() -> int:
	return config.threshold


func _on_start_game_requested() -> void:
	if not _is_request_valid(MusicTypes.Phase.TITLE, "start_game_requested"):
		return
	var news := config.draw_news(_last_news)
	if news == null:
		return  # Empty news pool, already reported by draw_news.
	_news = news
	_last_news = news
	_set_phase(MusicTypes.Phase.NEWS_INTRO)
	MusicBus.game_started.emit(_news, get_threshold())


func _on_continue_requested() -> void:
	match _phase:
		MusicTypes.Phase.NEWS_INTRO:
			_set_phase(MusicTypes.Phase.COMPOSITION)
			composition_phase.start(_news, config.composition_duration_sec)
		MusicTypes.Phase.COMPOSITION_REVIEW:
			_set_phase(MusicTypes.Phase.PERFORMANCE)
			performance_phase.start(_news, _composition, _multiplier)
		_:
			_warn_ignored("continue_requested")


func _on_finish_composition_requested() -> void:
	if _is_request_valid(MusicTypes.Phase.COMPOSITION, "finish_composition_requested"):
		composition_phase.finish_early()


func _on_restart_requested() -> void:
	if not _is_request_valid(MusicTypes.Phase.GAME_OVER, "restart_requested"):
		return
	_news = null
	_composition = null
	_multiplier = 1.0
	_audimat = 0
	_set_phase(MusicTypes.Phase.TITLE)


func _on_composition_finished(composition: Composition) -> void:
	if _phase != MusicTypes.Phase.COMPOSITION:
		push_warning("GameManager: composition_finished ignored in phase %s" % _phase_name(_phase))
		return
	_composition = composition
	var evaluation := CompositionEvaluator.evaluate(composition, _news)
	_multiplier = evaluation["multiplier"]
	_set_phase(MusicTypes.Phase.COMPOSITION_REVIEW)
	MusicBus.composition_evaluated.emit(evaluation["quality"], evaluation["multiplier"], evaluation["comments"])


func _on_performance_finished(audimat: int) -> void:
	if _phase != MusicTypes.Phase.PERFORMANCE:
		push_warning("GameManager: performance_finished ignored in phase %s" % _phase_name(_phase))
		return
	_audimat = audimat
	_set_phase(MusicTypes.Phase.GAME_OVER)
	MusicBus.game_finished.emit(_audimat >= get_threshold(), _audimat)


func _set_phase(phase: MusicTypes.Phase) -> void:
	if OS.is_debug_build():
		print("[GameManager] %s -> %s" % [_phase_name(_phase), _phase_name(phase)])
	_phase = phase
	MusicBus.phase_changed.emit(phase)


func _is_request_valid(expected: MusicTypes.Phase, request: String) -> bool:
	if _phase == expected:
		return true
	_warn_ignored(request)
	return false


func _warn_ignored(request: String) -> void:
	push_warning("GameManager: %s ignored in phase %s" % [request, _phase_name(_phase)])


func _phase_name(phase: MusicTypes.Phase) -> String:
	return MusicTypes.Phase.keys()[phase]
