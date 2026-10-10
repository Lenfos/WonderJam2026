class_name RoundManager
extends Node
## Single source of truth for the game flow (see the phase diagram in docs/CONTRACT.md):
## TITLE -> NEWS_INTRO -> COMPOSITION -> COMPOSITION_REVIEW -> PERFORMANCE -> RESULTS
## -> next round's NEWS_INTRO, or GAME_OVER -> TITLE.
## Moves on only on MusicBus requests (UI) or phase-end signals (phases). A request that is invalid
## in the current phase is ignored with a warning. State is updated before any signal fires, and
## phase_changed fires before the new phase's own signals.

@export var config: GameConfig = preload("res://data/game_config.tres")
@export var clock: MusicClock
@export var composition_phase: CompositionPhase
@export var performance_phase: PerformancePhase

var _phase := MusicTypes.Phase.TITLE
## News of each round, drawn at game start.
var _rounds: Array[NewsData] = []
## 0-based index in _rounds; -1 outside a game.
var _round_index := -1
var _composition: Composition
var _multiplier := 1.0
var _round_success := false
## Current round's audimat, mirrored from MusicBus.audimat_changed.
var _audimat := 0
var _total_audimat := 0


# _enter_tree, not _ready: UI nodes may read the MusicBus getters in their own _ready.
func _enter_tree() -> void:
	MusicBus.set_round_manager(self)


func _ready() -> void:
	MusicBus.start_game_requested.connect(_on_start_game_requested)
	MusicBus.continue_requested.connect(_on_continue_requested)
	MusicBus.finish_composition_requested.connect(_on_finish_composition_requested)
	MusicBus.restart_requested.connect(_on_restart_requested)
	MusicBus.composition_finished.connect(_on_composition_finished)
	MusicBus.round_finished.connect(_on_round_finished)
	MusicBus.audimat_changed.connect(func(audimat: int) -> void: _audimat = audimat)


func get_song_time() -> float:
	return clock.get_song_time()


func get_current_phase() -> MusicTypes.Phase:
	return _phase


## null outside a game.
func get_current_news() -> NewsData:
	return _rounds[_round_index] if _round_index >= 0 else null


func get_audimat() -> int:
	return _audimat


## 0 outside a game.
func get_threshold() -> int:
	return config.get_threshold(_round_index) if _round_index >= 0 else 0


func _on_start_game_requested() -> void:
	if not _is_request_valid(MusicTypes.Phase.TITLE, "start_game_requested"):
		return
	_rounds = config.draw_rounds()
	_total_audimat = 0
	_start_round(0)


func _on_continue_requested() -> void:
	match _phase:
		MusicTypes.Phase.NEWS_INTRO:
			_set_phase(MusicTypes.Phase.COMPOSITION)
			composition_phase.start(get_current_news(), config.composition_duration_sec)
		MusicTypes.Phase.COMPOSITION_REVIEW:
			_set_phase(MusicTypes.Phase.PERFORMANCE)
			performance_phase.start(get_current_news(), _composition, _multiplier, get_threshold())
		MusicTypes.Phase.RESULTS:
			if _round_success and _round_index + 1 < _rounds.size():
				_start_round(_round_index + 1)
			else:
				# A failed round ends the game, so the last round's result is the game's.
				_set_phase(MusicTypes.Phase.GAME_OVER)
				MusicBus.game_finished.emit(_round_success, _total_audimat)
		_:
			_warn_ignored("continue_requested")


func _on_finish_composition_requested() -> void:
	if _is_request_valid(MusicTypes.Phase.COMPOSITION, "finish_composition_requested"):
		composition_phase.finish_early()


func _on_restart_requested() -> void:
	if not _is_request_valid(MusicTypes.Phase.GAME_OVER, "restart_requested"):
		return
	_rounds.clear()
	_round_index = -1
	_composition = null
	_multiplier = 1.0
	_round_success = false
	_audimat = 0
	_total_audimat = 0
	_set_phase(MusicTypes.Phase.TITLE)


func _on_composition_finished(composition: Composition) -> void:
	if _phase != MusicTypes.Phase.COMPOSITION:
		push_warning("RoundManager: composition_finished ignored in phase %s" % _phase_name(_phase))
		return
	_composition = composition
	var evaluation := CompositionEvaluator.evaluate(composition, get_current_news())
	_multiplier = evaluation["multiplier"]
	_set_phase(MusicTypes.Phase.COMPOSITION_REVIEW)
	MusicBus.composition_evaluated.emit(evaluation["quality"], evaluation["multiplier"], evaluation["comments"])


func _on_round_finished(success: bool, audimat: int) -> void:
	if _phase != MusicTypes.Phase.PERFORMANCE:
		push_warning("RoundManager: round_finished ignored in phase %s" % _phase_name(_phase))
		return
	_round_success = success
	_audimat = audimat
	_total_audimat += audimat
	_set_phase(MusicTypes.Phase.RESULTS)


func _start_round(index: int) -> void:
	_round_index = index
	_composition = null
	_multiplier = 1.0
	_round_success = false
	_audimat = 0
	_set_phase(MusicTypes.Phase.NEWS_INTRO)
	MusicBus.round_started.emit(index, get_current_news(), get_threshold())


func _set_phase(phase: MusicTypes.Phase) -> void:
	if OS.is_debug_build():
		print("[RoundManager] round %d/%d: %s -> %s" % [_round_index + 1, _rounds.size(), _phase_name(_phase), _phase_name(phase)])
	_phase = phase
	MusicBus.phase_changed.emit(phase)


func _is_request_valid(expected: MusicTypes.Phase, request: String) -> bool:
	if _phase == expected:
		return true
	_warn_ignored(request)
	return false


func _warn_ignored(request: String) -> void:
	push_warning("RoundManager: %s ignored in phase %s" % [request, _phase_name(_phase)])


func _phase_name(phase: MusicTypes.Phase) -> String:
	return MusicTypes.Phase.keys()[phase]
