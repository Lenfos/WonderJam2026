extends Node2D
## Piste de notes : crée les notes du chart, réagit à note_hit / note_missed,
## affiche les jugements, le shake et le feedback des touches.
##
## Structure attendue :
##   NoteTrack (Node2D)      <- ce script
##   ├── Playfield (Node2D)  <- secoué au shake (mets-y tes 4 Path2D)
##   │   ├── Lane0 (Path2D) ... Lane3
##   └── HitMarkers          <- 4 Marker2D à l'endroit de la ligne de frappe de chaque lane

const NOTE_SCENE_1 := preload("res://scenes/note1.tscn")
const NOTE_SCENE_2 := preload("res://scenes/note_2.tscn")
const NOTE_SCENE_3 := preload("res://scenes/note_3.tscn")
const NOTE_SCENE_4 := preload("res://scenes/note_4.tscn")


@export var lanes: Array[Path2D] = []             # 4 Path2D : KICK, SNARE, BRASS, BELLS
@export var hit_markers: Array[Node2D] = []       # 4 positions de ligne de frappe (popups)
@export var receptors: Array[CanvasItem] = []     # optionnel : 4 sprites qui s'allument à l'appui
@export var playfield: Node2D                     # optionnel : nœud à secouer
@export var travel_time := 2.0

@onready var performance: Control = $"../../CanvasLayer/GameUi/Performance"

# Jugement -> [texte, couleur]
const JUDGMENT_STYLE := {
	MusicTypes.Judgment.PERFECT: ["Excellent", Color.GOLD],
	MusicTypes.Judgment.GOOD: ["Good", Color.LIME_GREEN],
	MusicTypes.Judgment.BAD: ["Ok", Color.ORANGE],
	MusicTypes.Judgment.MISS: ["Missed", Color.RED],
}

var _notes: Dictionary[int, Note] = {}   # note_index -> note à l'écran
var _chaos := 0.0
var _shake_tween: Tween
var _playfield_origin := Vector2.ZERO


func _ready() -> void:
	if playfield:
		_playfield_origin = playfield.position
	MusicBus.performance_started.connect(_on_performance_started)
	MusicBus.note_hit.connect(_on_note_hit)
	MusicBus.note_missed.connect(_on_note_missed)
	MusicBus.phase_changed.connect(_on_phase_changed)
	MusicBus.chaos_level_changed.connect(func(level: float) -> void: _chaos = level)


func _process(_delta: float) -> void:
	for lane in receptors.size():
		var pressed := Input.is_action_pressed(MusicTypes.lane_action(lane))
		receptors[lane].modulate = Color(2, 2, 2) if pressed else Color.WHITE



func _on_performance_started(chart: Array, _lead_time_sec: float) -> void:
	_clear_notes()
	for data: NoteData in chart:
		var note: Note
		match data.lane:
			0: note = NOTE_SCENE_1.instantiate()
			1: note = NOTE_SCENE_2.instantiate()
			2: note = NOTE_SCENE_3.instantiate()
			3: note = NOTE_SCENE_4.instantiate()

		note.hit_time = data.time_sec
		note.travel_time = travel_time
		lanes[data.lane].add_child(note)
		_notes[data.index] = note


func _on_note_hit(index: int, lane: int, judgment: MusicTypes.Judgment) -> void:
	var color: Color = JUDGMENT_STYLE[judgment][1]
	if _notes.has(index):
		_notes[index].hit(color)
		_notes.erase(index)
	_show_judgment(judgment, lane)
	if judgment == MusicTypes.Judgment.PERFECT:
		performance.addScore(100)
		_shake(2.0, 0.1)   # micro-shake, optionnel
	elif judgment == MusicTypes.Judgment.GOOD:
		performance.addScore(50)


func _on_note_missed(index: int, lane: int) -> void:
	if _notes.has(index):
		_notes[index].miss()
		_notes.erase(index)
	_show_judgment(MusicTypes.Judgment.MISS, lane)
	_shake(lerpf(6.0, 14.0, _chaos), 0.2)   # plus le chaos monte, plus ça secoue
	performance.addScore(-70)


func _on_phase_changed(phase: MusicTypes.Phase) -> void:
	if phase != MusicTypes.Phase.PERFORMANCE:
		_clear_notes()


func _clear_notes() -> void:
	for note: Note in _notes.values():
		if is_instance_valid(note):
			note.queue_free()
	_notes.clear()


# --- Jugements --------------------------------------------------------------

func _show_judgment(judgment: MusicTypes.Judgment, lane: int) -> void:
	var style: Array = JUDGMENT_STYLE[judgment]

	var label := Label.new()
	label.text = style[0]
	label.modulate = style[1]
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.z_index = 300
	add_child(label)

	var size := label.get_minimum_size()
	var anchor: Vector2 = hit_markers[lane].global_position if lane < hit_markers.size() else global_position
	label.global_position = anchor + Vector2(-size.x / 2.0, -60.0)
	label.pivot_offset = size / 2.0
	label.scale = Vector2.ONE * 1.4  

	var end_y := label.position.y - 40.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(label, "scale", Vector2.ONE, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "position:y", end_y, 0.5)
	tw.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.2)
	tw.chain().tween_callback(label.queue_free)


# --- Shake ------------------------------------------------------------------

func _shake(intensity: float, duration: float) -> void:
	if playfield == null:
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	for i in 6:
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * intensity
		_shake_tween.tween_property(playfield, "position", _playfield_origin + offset, duration / 6.0)
	_shake_tween.tween_property(playfield, "position", _playfield_origin, 0.05)
