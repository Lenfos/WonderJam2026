extends Node
## Autoload "MusicBus": the only channel between music/gameplay code and UI.
## Music code emits, UI code listens. No state, no logic here.
## Exception: *_requested signals go the other way (UI emits, music code listens and answers
## with a state signal), so the UI never calls music code directly.

# Signals are emitted from other scripts, so this file never "uses" them itself.
@warning_ignore_start("unused_signal")

## UI -> MUSIC. Emitted BY THE UI when the player clicks a grid cell. The UI must not change the
## cell itself: it waits for composition_changed (ignored outside the composition phase).
signal cell_toggle_requested(lane: int, step: int)

## COMPOSITION phase starts: the grid is empty, the backing track plays, the countdown runs.
## Listen: UI, to show the headline and reset the grid.
signal composition_started(news: NewsData, duration_sec: float)

## COMPOSITION phase. Seconds left, rounded up. Fires once per whole second (and once at start), not every frame.
## Listen: countdown UI.
signal composition_time_changed(seconds_left: int)

## COMPOSITION phase. Fires each time the sequencer playhead reaches a new step (0..STEP_COUNT-1).
## Listen: grid UI, to highlight the current column.
signal step_changed(step: int)

## COMPOSITION phase. Fires after a grid cell changed state (player click, clear, preset...).
## Listen: grid UI, to redraw that cell.
signal composition_changed(lane: int, step: int, active: bool)

## Fires once when the composition phase ends (timer out or player done).
## `composition` is a frozen copy: read it, never edit it.
## Listen: UI, to switch to the rhythm view and build the note highway.
signal composition_finished(composition: Composition)

## PERFORMANCE phase. Fires when the player hits a note on `lane`; the note is used up.
## `judgment` is PERFECT, GOOD or BAD, never MISS (misses go through note_missed).
## Listen: rhythm UI (hit feedback, remove the note), anchor/crowd reactions.
signal note_hit(lane: int, judgment: MusicTypes.Judgment)

## PERFORMANCE phase. Fires when a note on `lane` leaves the BAD window without being hit.
## Listen: rhythm UI (miss feedback, remove the note).
signal note_missed(lane: int)

## PERFORMANCE phase. Fires whenever the combo or the multiplier changes:
## PERFECT/GOOD hit (combo up), BAD hit (multiplier down, combo kept),
## missed note or key press with no note within BAD_WINDOW_SEC (combo reset).
## Listen: combo counter UI.
signal combo_changed(combo: int, multiplier: float)

## Fires whenever the TV ratings change. `audimat` is a viewer count, with no upper bound.
## Listen: ratings counter UI.
signal audimat_changed(audimat: int)

## Fires once at the end of a round. `success` is true when `audimat` reached the round threshold.
## Listen: results screen / round flow UI.
signal round_finished(success: bool, audimat: int)
