extends Node
## Autoload "MusicBus": the only channel between music/gameplay code and UI (docs/CONTRACT.md).
## Music code emits state signals, UI code listens. *_requested signals go the other way: the UI
## emits, music code (mostly the RoundManager) listens and answers with a state signal, so the UI
## never calls music code directly. The getters relay the RoundManager's state for anytime reads.
## Within one transition, state (getters) is updated first, then phase_changed fires, then the new
## phase's own signals. A phase's *_finished signal fires before phase_changed to the next phase.

# Signals are emitted from other scripts, so this file never "uses" them itself.
@warning_ignore_start("unused_signal")

# --- UI -> MUSIC: requests. Each one is ignored, with a warning, outside the phase it belongs to. ---

## UI -> MUSIC. TITLE: the player clicked "Jouer". Answer: phase_changed(NEWS_INTRO) + round_started.
signal start_game_requested
## UI -> MUSIC. NEWS_INTRO, COMPOSITION_REVIEW, RESULTS: the player clicked "Continuer".
## Answer: phase_changed to the next phase (see the phase diagram).
signal continue_requested
## UI -> MUSIC. COMPOSITION: the player clicked "J'ai fini". Answer: composition_finished, then
## phase_changed(COMPOSITION_REVIEW) + composition_evaluated.
signal finish_composition_requested
## UI -> MUSIC. GAME_OVER: the player clicked "Rejouer". Answer: phase_changed(TITLE), all state reset.
signal restart_requested
## UI -> MUSIC. COMPOSITION: the player clicked a grid cell. The UI must not change the cell itself:
## it waits for composition_changed (silently ignored outside the composition phase).
signal cell_toggle_requested(lane: int, step: int)

# --- MUSIC -> UI: game flow. ---

## Every phase transition, emitted by the RoundManager. Not emitted at startup: read
## get_current_phase() in _ready (TITLE).
## Listen: UI, to switch screens.
signal phase_changed(phase: MusicTypes.Phase)

## NEWS_INTRO starts: a new round. `round_index` is 0-based (display it +1); `threshold` is the
## minimum audimat to pass this round.
## Listen: UI, to show the breaking news headline and the goal.
signal round_started(round_index: int, news: NewsData, threshold: int)

## GAME_OVER starts. `won` is true when every round passed; `total_audimat` sums all played rounds.
## Listen: game over screen.
signal game_finished(won: bool, total_audimat: int)

# --- MUSIC -> UI: COMPOSITION phase. ---

## COMPOSITION phase starts: the grid is empty, the backing track plays, the countdown runs.
## Listen: UI, to show the headline and reset the grid.
signal composition_started(news: NewsData, duration_sec: float)

## COMPOSITION phase. Seconds left, rounded up. Fires once per whole second (and once at start), not every frame.
## Listen: countdown UI.
signal composition_time_changed(seconds_left: int)

## COMPOSITION and PERFORMANCE phases. Fires each time the sequencer playhead reaches a new step
## (0..STEP_COUNT-1). Never during the performance count-in.
## Listen: grid UI, to highlight the current column.
signal step_changed(step: int)

## COMPOSITION phase. Fires after a grid cell changed state (player click, clear, preset...).
## Listen: grid UI, to redraw that cell.
signal composition_changed(lane: int, step: int, active: bool)

## Fires once when the composition phase ends (timer out or finish_composition_requested), before
## phase_changed(COMPOSITION_REVIEW). `composition` is a frozen copy: read it, never edit it.
## Listen: UI, if it needs the final grid.
signal composition_finished(composition: Composition)

## COMPOSITION_REVIEW starts. `quality` 0-1 is how well the grid fits the news, `multiplier` scales
## the performance audimat, `comments` are short French remarks to show the player.
## Listen: review screen.
signal composition_evaluated(quality: float, multiplier: float, comments: PackedStringArray)

# --- MUSIC -> UI: PERFORMANCE phase. ---

## PERFORMANCE starts. `chart` is an Array of NoteData sorted by time; NoteData.index is the note's
## position in it. `lead_time_sec` is the song time left until the chart's first beat (step 0 of the
## first loop, note or not): the count-in.
## Listen: rhythm UI, to build the note highway (scroll it with get_song_time()).
signal performance_started(chart: Array, lead_time_sec: float)

## PERFORMANCE count-in: fires on each count-in beat with the beats left before the chart starts
## (e.g. 4, 3, 2, 1), then once with 0 on the chart's first beat.
## Listen: countdown UI ("3, 2, 1, GO").
signal countdown_beat(beats_left: int)

## PERFORMANCE: fires at the start of each loop of the chart. `line_index` indexes the round's
## news.anchor_lines, always in range (loops past the last line fire nothing).
## Listen: anchor subtitles / speech bubble.
signal anchor_line_changed(line_index: int)

## PERFORMANCE. The player hit note `note_index` (NoteData.index) on `lane`; the note is used up.
## `judgment` is PERFECT, GOOD or BAD, never MISS (misses go through note_missed).
## Listen: rhythm UI (hit feedback, remove that note), anchor/crowd reactions.
signal note_hit(note_index: int, lane: int, judgment: MusicTypes.Judgment)

## PERFORMANCE. Note `note_index` on `lane` left the BAD window without being hit.
## Listen: rhythm UI (miss feedback, remove that note).
signal note_missed(note_index: int, lane: int)

## PERFORMANCE phase. Fires whenever the combo or the multiplier changes:
## PERFECT/GOOD hit (combo up), BAD hit (multiplier down, combo kept),
## missed note or key press with no note within BAD_WINDOW_SEC (combo reset).
## Listen: combo counter UI.
signal combo_changed(combo: int, multiplier: float)

## PERFORMANCE. How chaotic the live broadcast is, 0 (calm) to 1 (total mess). Fires 0 at the start
## of the performance, then whenever it changes.
## Listen: on-air gags (anchor losing it, props falling, technical difficulties...).
signal chaos_level_changed(level: float)

# --- MUSIC -> UI: score. ---

## Fires whenever the current round's TV ratings change (0 at the start of the performance).
## `audimat` is a viewer count, with no upper bound.
## Listen: ratings counter UI.
signal audimat_changed(audimat: int)

## Fires once at the end of the performance, before phase_changed(RESULTS). `success` is true when
## `audimat` reached the round threshold.
## Listen: results screen.
signal round_finished(success: bool, audimat: int)

# The RoundManager, registered by itself. Typed Node, not RoundManager: round_manager.gd depends on
# this autoload, so depending back on it would make a cycle.
var _round_manager: Node


## Called by the RoundManager only.
func set_round_manager(manager: Node) -> void:
	_round_manager = manager


## What the player hears right now, in seconds (MusicClock.get_song_time()). Use it for visuals,
## e.g. a note is on the hit line when get_song_time() == NoteData.time_sec. Frozen while no music
## plays; 0.0 when no RoundManager runs.
func get_song_time() -> float:
	if not is_instance_valid(_round_manager):
		return 0.0
	return _round_manager.get_song_time()


## TITLE when no RoundManager runs.
func get_current_phase() -> MusicTypes.Phase:
	if not is_instance_valid(_round_manager):
		return MusicTypes.Phase.TITLE
	return _round_manager.get_current_phase()


## The current round's news; null outside a game (TITLE).
func get_current_news() -> NewsData:
	if not is_instance_valid(_round_manager):
		return null
	return _round_manager.get_current_news()


## The current round's audimat: 0 from round_started, live during the performance, final in RESULTS.
func get_audimat() -> int:
	if not is_instance_valid(_round_manager):
		return 0
	return _round_manager.get_audimat()


## The current round's minimum audimat; 0 outside a game.
func get_threshold() -> int:
	if not is_instance_valid(_round_manager):
		return 0
	return _round_manager.get_threshold()
