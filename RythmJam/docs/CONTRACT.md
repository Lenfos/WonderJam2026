# Contrat musique ↔ UI

Pour toi qui fais l'UI. Tu n'as jamais besoin d'ouvrir le code de `scripts/music/` : tout ce qu'il te faut est ici. Si le jeu ne se comporte pas comme ce doc le dit, c'est un bug : préviens-moi.

---

## 1. En bref

- Le côté musique **décide de tout** : il possède le déroulement de la partie (phases, chrono, score, jugement des touches).
- Ton UI **affiche** et **envoie des demandes**. Elle ne décide rien : même pour allumer une case, elle demande et attend la réponse.
- Tout passe par l'autoload **`MusicBus`** : tu écoutes ses signaux, tu émets ses signaux `*_requested`, tu lis ses getters `get_*()`.
- Ne référence **jamais** un nœud ou un script musique (`GameManager`, `MusicClock`, `PerformancePhase`…). Seules exceptions, les classes de données : `MusicTypes`, `NewsData`, `NoteData`, `Composition`.
- Exemple complet qui marche : `scenes/debug/placeholder_ui.gd`.

---

## 2. Brancher ton UI

`scenes/main.tscn` est la scène principale du projet :

```
Main
├── MusicSystem        ← côté musique : ne rien modifier ici
│   ├── MusicClock
│   ├── SequencerPlayer
│   ├── CompositionPhase
│   ├── PerformancePhase
│   └── GameManager    ← pilote toute la partie
└── UIRoot             ← ton UI ici
	└── PlaceholderUI  ← UI provisoire, à remplacer par ta scène
```

**Voir le jeu tourner avant de commencer :** lance le projet (F5). L'UI provisoire joue une partie entière, moche mais complète, en n'utilisant que `MusicBus`. C'est ta référence : `scenes/debug/placeholder_ui.gd` (toutes les phases) et `scenes/debug/sequencer_grid.gd` (la grille de composition). Dans sa grille, `R` remplit au hasard et `C` vide tout.

**Brancher ta scène :** dans `scenes/main.tscn`, supprime `PlaceholderUI` et instancie ta scène sous `UIRoot`. `UIRoot` est un simple `Node` : ta scène peut être un `Control` (mets-le en plein écran, preset *Full Rect*), un `CanvasLayer` ou un `Node2D`. Puis F5 comme avant.

**Le minimum vital :** suivre la phase et émettre une demande.

```gdscript
extends Control

@onready var _title_screen: Control = $TitleScreen
@onready var _play_button: Button = $TitleScreen/PlayButton


func _ready() -> void:
	MusicBus.phase_changed.connect(_on_phase_changed)
	# Un clic = une demande. La musique répond par phase_changed(NEWS_INTRO).
	_play_button.pressed.connect(MusicBus.start_game_requested.emit)
	# phase_changed n'est pas émis au lancement : lis la phase de départ (TITLE).
	_on_phase_changed(MusicBus.get_current_phase())


func _on_phase_changed(phase: MusicTypes.Phase) -> void:
	_title_screen.visible = phase == MusicTypes.Phase.TITLE
	print("Phase : ", MusicTypes.Phase.keys()[phase])
```

Pas besoin de déconnecter les signaux : Godot coupe les connexions quand ton nœud est libéré.

---

## 3. Le déroulement d'une partie

Une partie = une news, tirée au hasard (jamais deux fois de suite la même quand il y en a plusieurs). On ne peut pas perdre : la partie va toujours jusqu'au bout, et l'audimat final est le score, bon ou mauvais.

```
TITLE
  │ start_game_requested (bouton « Jouer »)
  ▼
NEWS_INTRO
  │ continue_requested
  ▼
COMPOSITION
  │ fin du chrono, ou finish_composition_requested
  ▼
COMPOSITION_REVIEW
  │ continue_requested
  ▼
PERFORMANCE
  │ automatique : fin du morceau
  ▼
GAME_OVER
  │ restart_requested (bouton « Rejouer »)
  ▼
TITLE
```

### Règles valables partout

- **Change d'écran dans `phase_changed`, remplis-le avec les signaux de la phase.** `phase_changed` arrive en premier, puis les signaux propres à la nouvelle phase (`game_started`, `composition_started`…), dans la même frame.
- Quand `phase_changed` arrive, les getters `MusicBus.get_*()` renvoient déjà les valeurs de la nouvelle phase.
- **Au lancement**, pas de `phase_changed` : lis `MusicBus.get_current_phase()` dans ton `_ready` (c'est `TITLE`).
- **Une demande émise hors de sa phase est ignorée** (warning dans la console, rien ne plante).
- **Une seule demande par clic.** Un double-clic envoie deux demandes : la seconde est ignorée (warning dans la console). Cache ou désactive le bouton dès le clic.
- Si la fenêtre perd le focus, la musique, le chrono et `get_song_time()` se mettent en pause, puis reprennent.

### `TITLE` : écran titre

- **À l'écran** : le titre du jeu, un bouton « Jouer ».
- **Musique** : rien ne joue.
- **À écouter** : rien de spécifique. Après « Rejouer », tout est remis à zéro : `get_current_news()` = `null`, `get_audimat()` = 0.- **À émettre** : `start_game_requested()` au clic sur « Jouer ».
- **Sortie** : → `NEWS_INTRO`.

### `NEWS_INTRO` : le flash info

- **À l'écran** : « FLASH SPÉCIAL », le titre de la news. Optionnel : la consigne bonus (`news.special_criterion`, voir §5).
- **Musique** : rien ne joue.
- **À écouter** :
  - `game_started(news: NewsData)`, juste après `phase_changed(NEWS_INTRO)`. `news.headline` = le titre.
- **À émettre** : `continue_requested()` quand le joueur est prêt (bouton « Continuer »). Pas de minuteur : la phase attend ce clic, tu peux jouer ton anim d'intro avant d'afficher le bouton.
- **Sortie** : → `COMPOSITION`, le chrono démarre aussitôt.
- **Attention** : après « Rejouer », l'audimat repasse à 0 **sans** `audimat_changed`. Remets ton compteur à zéro dans `game_started` (ou lis `MusicBus.get_audimat()`).

### `COMPOSITION` : le joueur compose

- **À l'écran** : la grille 4 × 16. Une ligne par piste, dans l'ordre `KICK`, `SNARE`, `BRASS`, `BELLS` ; une colonne par pas, de 0 à 15, à grouper par 4 (une mesure). La colonne en cours de lecture surlignée, le titre de la news, le chrono, un bouton « J'ai fini ».
- **Musique** : la backing track tourne en boucle et la grille est jouée en direct : une case allumée s'entend au prochain passage de la tête de lecture. Allumer une case joue aussi son son tout de suite.
- **À écouter** :
  - `composition_started(news: NewsData, duration_sec: float)` : début de phase, la grille est vide, vide la tienne. `duration_sec` = durée totale du chrono (45 s pour l'instant).
  - `composition_time_changed(seconds_left: int)` : secondes restantes, arrondi au-dessus. Une fois au départ, puis une fois par seconde (pas à chaque frame), et `0` à la fin.
  - `composition_changed(lane: int, step: int, active: bool)` : une case a changé, `active` = son nouvel état. Redessine-la.
  - `step_changed(step: int)` : la tête de lecture arrive sur la colonne `step`. Surligne-la et éteins la colonne que tu avais surlignée (pas forcément `step - 1` : après un gros ralentissement, un pas peut être sauté).
  - `composition_finished(composition: Composition)` (optionnel) : la grille finale. Copie figée : lis-la, ne la modifie jamais.
- **À émettre** :
  - `cell_toggle_requested(lane: int, step: int)` au clic sur une case. **Ne change pas la case toi-même** : attends `composition_changed`. (Ignoré sans warning hors de cette phase.)
  - `finish_composition_requested()` au clic sur « J'ai fini ».
- **Sortie** : chrono à 0 ou « J'ai fini » → `COMPOSITION_REVIEW`. Tu reçois dans la même frame `composition_time_changed(0)`, `phase_changed(COMPOSITION_REVIEW)`, `composition_evaluated` et `composition_finished` : ne compte pas sur l'ordre entre `composition_finished` et `phase_changed`.

Pour garder ta propre copie de la grille (c'est ce que fait `sequencer_grid.gd`) : une `Composition.new()` à toi, `clear()` dans `composition_started`, `set_cell(lane, step, active)` dans `composition_changed`. Elle ne sert qu'à l'affichage : ne l'envoie jamais côté musique.

### `COMPOSITION_REVIEW` : le verdict

- **À l'écran** : la note de la composition (`quality` en % ou en étoiles), le multiplicateur obtenu (« x1.50 »), les commentaires. La grille finale peut rester affichée, sans tête de lecture.
- **Musique** : la backing track continue, mais la grille n'est plus jouée (plus de `step_changed`).
- **À écouter** :
  - `composition_evaluated(quality: float, multiplier: float, comments: PackedStringArray)`, juste après `phase_changed(COMPOSITION_REVIEW)`. `quality` de 0 à 1 = adéquation de la grille à la news. `multiplier` = multiplicateur appliqué à l'audimat de la performance, de x0,5 (grille ratée ou vide) à x1,5 (grille parfaite). `comments` = 1 à 3 remarques courtes en français, une ligne chacune, prêtes à afficher (toujours au moins une).
- **À émettre** : `continue_requested()` (bouton « Continuer »).
- **Sortie** : → `PERFORMANCE`.

### `PERFORMANCE` : le direct (jeu de rythme)

- **À l'écran** : le plateau TV. Le présentateur et ses sous-titres, les 4 pistes de notes qui défilent (touches D F J K) avec la ligne de frappe, le décompte « 3, 2, 1, GO », le combo, l'audimat, des gags selon le chaos. Pour faire défiler les notes : §4.
- **Musique** : la backing track redémarre, 4 temps de décompte, puis la composition est jouée automatiquement 3 fois de suite. Une boucle (16 temps) = une phrase du présentateur. Quand le joueur rate une note, sa piste se tait jusqu'à la prochaine note touchée sur cette piste.
- **À écouter**, dans l'ordre d'arrivée :
  - `chaos_level_changed(0.0)`, `combo_changed(0, 1.0)` et `audimat_changed(0)` : remise à zéro, juste après `phase_changed(PERFORMANCE)`.
  - `performance_started(chart: Array, lead_time_sec: float)` : `chart` = toutes les notes à jouer (`Array` de `NoteData`, triées par temps). `lead_time_sec` = secondes avant le premier temps du chart (la durée du décompte). Crée tes notes ici. `chart` peut être vide (grille vide) : la phase se déroule quand même.
  - `countdown_beat(beats_left: int)` : à chaque temps du décompte, `4`, `3`, `2`, `1`, puis `0` sur le premier temps du chart (« GO »).
  - `anchor_line_changed(line_index: int)` : au début de chaque boucle. Le texte : `MusicBus.get_current_news().anchor_lines[line_index]` (index toujours valide).
  - `note_hit(note_index: int, lane: int, judgment: MusicTypes.Judgment)` : note touchée. `judgment` = `PERFECT`, `GOOD` ou `BAD`, jamais `MISS`. Retire la note `note_index`, affiche le feedback.
  - `note_missed(note_index: int, lane: int)` : note passée sans être touchée. Retire-la, feedback d'échec.
  - `combo_changed(combo: int, multiplier: float)` : le combo ou le multiplicateur de score a changé (règles ci-dessous).
  - `audimat_changed(audimat: int)` : l'audimat a changé (à chaque note touchée). C'est un nombre de téléspectateurs, sans plafond.
  - `chaos_level_changed(level: float)` : 0 = plateau calme, 1 = chaos total (présentateur qui craque, décor qui tombe, problèmes techniques…). Il monte beaucoup à chaque note ratée, un peu à chaque `BAD`, et redescend à chaque `PERFECT` ou `GOOD`.
  - `step_changed(step: int)` (optionnel) : comme en composition, si tu affiches la grille. Jamais pendant le décompte.
- **À émettre** : **rien**. Les touches D F J K sont lues et jugées côté musique : n'envoie pas les appuis, ne juge rien toi-même. (Pour éclairer une piste quand sa touche est enfoncée : §4.)
- **Sortie** : automatique à la fin de la 3ᵉ boucle → `GAME_OVER`. Les notes pas encore jugées reçoivent d'abord `note_missed`, puis tu reçois dans la même frame `phase_changed(GAME_OVER)` et `game_finished`.

Ce que donne un appui sur une touche (écart = distance en temps à la prochaine note de cette piste) :

| Appui | Signal de note | Combo | Multiplicateur |
|---|---|---|---|
| Écart ≤ 0,050 s (`PERFECT_WINDOW_SEC`) | `note_hit(…, PERFECT)` | +1 | +0,5 tous les 8 de combo, max x3 |
| Écart ≤ 0,100 s (`GOOD_WINDOW_SEC`) | `note_hit(…, GOOD)` | +1 | +0,5 tous les 8 de combo, max x3 |
| Écart ≤ 0,150 s (`BAD_WINDOW_SEC`) | `note_hit(…, BAD)` | gardé | −0,5, min x1 |
| Aucune note à moins de 0,150 s | aucun | remis à 0 | remis à x1 |
| *(pas d'appui)* note dépassée de plus de 0,150 s | `note_missed` | remis à 0 | remis à x1 |

Chaque changement de combo ou de multiplicateur émet `combo_changed` (rien si les deux sont inchangés, par exemple un appui dans le vide avec un combo déjà à 0). Chaque note n'est jugée qu'une fois. Une note touchée rapporte d'autant plus d'audimat que le jugement est bon et le multiplicateur haut (et que la composition a été bien notée).

### `GAME_OVER` : fin de partie

- **À l'écran** : l'audimat obtenu (c'est le score : ni victoire ni défaite), un bouton « Rejouer ».
- **Musique** : rien ne joue.
- **À écouter** :
  - `game_finished(audimat: int)`, juste après `phase_changed(GAME_OVER)`. `audimat` = le score final. **Remplis l'écran ici**, pas dans `phase_changed`.
  - Getters à jour : `MusicBus.get_audimat()` (final) et `MusicBus.get_current_news()`.
- **À émettre** : `restart_requested()` (bouton « Rejouer »).
- **Sortie** : → `TITLE`, tout est remis à zéro.

---

## 4. Faire défiler les notes

Le principe : **la position d'une note se recalcule à chaque frame à partir du temps de la musique, jamais en cumulant `delta`.**

- `MusicBus.get_song_time()` = le temps du morceau **que le joueur entend** (latence audio déjà retirée), en secondes.
- `note.time_sec` = la valeur de `get_song_time()` à laquelle la note doit être frappée.
- Donc une note est **sur la ligne de frappe** quand `get_song_time() == note.time_sec`, et elle en est à `(note.time_sec - MusicBus.get_song_time()) * SCROLL_SPEED` pixels.

Pièges :

- `get_song_time()` **ne repart pas de 0** au début de la performance : au premier temps du chart, il vaut déjà plusieurs secondes. Compare toujours à `note.time_sec`, jamais à 0.
- Il se fige quand la musique s'arrête ou que la fenêtre perd le focus : tes notes se figent avec, sans rien à faire.
- Plusieurs notes peuvent avoir le même `time_sec` (accord sur plusieurs pistes).
- `chart[i].index == i` : avec un `note_index` reçu, `chart[note_index]` te redonne la note.

Exemple complet, à copier dans un `Node2D` (une piste = une colonne, les notes descendent vers la ligne). Toutes les notes sont créées d'un coup : au plus 192 (64 cases × 3 boucles), c'est très bien.

```gdscript
extends Node2D
## Piste de notes : les notes descendent vers la ligne de frappe (y = HIT_LINE_Y).

const SCROLL_SPEED := 500.0  # pixels par seconde : plus grand = notes plus espacées
const HIT_LINE_Y := 600.0
const LANE_WIDTH := 100.0

var _chart: Array = []  # les NoteData reçus dans performance_started
var _sprites: Dictionary[int, Node2D] = {}  # note_index -> note encore à l'écran


func _ready() -> void:
	MusicBus.phase_changed.connect(_on_phase_changed)
	MusicBus.performance_started.connect(_on_performance_started)
	MusicBus.note_hit.connect(_on_note_hit)
	MusicBus.note_missed.connect(_on_note_missed)


func _process(_delta: float) -> void:
	var now := MusicBus.get_song_time()
	for index: int in _sprites:
		var note: NoteData = _chart[index]  # chart[i].index == i
		_sprites[index].position = Vector2(note.lane * LANE_WIDTH, HIT_LINE_Y - (note.time_sec - now) * SCROLL_SPEED)


func _on_performance_started(chart: Array, _lead_time_sec: float) -> void:
	_chart = chart
	for note: NoteData in chart:
		var sprite := _create_note()
		add_child(sprite)
		_sprites[note.index] = sprite


func _on_note_hit(note_index: int, _lane: int, _judgment: MusicTypes.Judgment) -> void:
	_remove_note(note_index)  # + ton feedback PERFECT / GOOD / BAD


func _on_note_missed(note_index: int, _lane: int) -> void:
	_remove_note(note_index)  # + ton feedback d'échec


# Fin de la performance : libère les notes restantes.
func _on_phase_changed(phase: MusicTypes.Phase) -> void:
	if phase != MusicTypes.Phase.PERFORMANCE:
		for index: int in _sprites.keys():
			_remove_note(index)


func _remove_note(note_index: int) -> void:
	_sprites[note_index].queue_free()
	_sprites.erase(note_index)


func _create_note() -> Node2D:
	var note := Polygon2D.new()  # remplace par ta vraie note (Sprite2D, scène instanciée…)
	note.polygon = PackedVector2Array([Vector2(-40, -10), Vector2(40, -10), Vector2(40, 10), Vector2(-40, 10)])
	return note
```

Pour aller plus loin :

- **Touches** : la piste `lane` correspond à l'action d'input `MusicTypes.lane_action(lane)` (`"lane_0"` à `"lane_3"`, touches physiques D F J K). Pour l'affichage seulement, par exemple allumer le récepteur d'une piste : `Input.is_action_pressed(MusicTypes.lane_action(lane))`. Le jugement reste côté musique.
- **Fenêtres de jugement** (pour dessiner une zone autour de la ligne) : `MusicTypes.PERFECT_WINDOW_SEC`, `GOOD_WINDOW_SEC`, `BAD_WINDOW_SEC`, avant ou après la note. En pixels : `fenêtre * SCROLL_SPEED`.
- **Décompte** : au moment de `performance_started`, le premier temps du chart tombe à `get_song_time() + lead_time_sec`. Pratique pour une barre de progression.
- **Animer en rythme** : `step_changed` tombe sur chaque temps (en composition et en performance). Pour une anim continue : `fposmod(MusicBus.get_song_time(), 60.0 / news.bpm)` ≈ secondes écoulées depuis le dernier temps.

---

## 5. Référence rapide

### Getters `MusicBus`

Lisibles à tout moment, y compris dans `_ready` ; valeur par défaut sans risque hors partie.

| Getter | Renvoie | Hors partie |
|---|---|---|
| `get_current_phase() -> MusicTypes.Phase` | La phase en cours | `TITLE` |
| `get_current_news() -> NewsData` | La news de la partie, de `NEWS_INTRO` à `GAME_OVER` inclus | `null` |
| `get_audimat() -> int` | Audimat : 0 jusqu'à la performance, en direct pendant, final en `GAME_OVER` | `0` |
| `get_song_time() -> float` | Temps du morceau entendu, en secondes (§4) | figé quand rien ne joue |

### `MusicTypes` : constantes et enums

Jamais instancié : on écrit `MusicTypes.LANE_COUNT`, `MusicTypes.Lane.KICK`…

- `LANE_COUNT` = 4, `STEP_COUNT` = 16. Un pas = un temps au `bpm` de la news.
- `STEPS_PER_BAR` = 4 : pas par mesure. Pratique pour grouper les colonnes de la grille : un temps fort est un pas où `step % STEPS_PER_BAR == 0` (pas 0, 4, 8, 12).
- `Lane` : `KICK`, `SNARE`, `BRASS`, `BELLS`, dans l'ordre d'affichage (touches D F J K). Partout, `lane` est un `int` de 0 à 3 et `step` un `int` de 0 à 15.
- `Judgment` : `PERFECT`, `GOOD`, `BAD`, `MISS`.
- `Phase` : `TITLE`, `NEWS_INTRO`, `COMPOSITION`, `COMPOSITION_REVIEW`, `PERFORMANCE`, `GAME_OVER`.
- `SpecialCriterion` (consigne bonus d'une news, remplie ou non) :
  - `VARIETY` : chaque piste a au moins une note.
  - `DOWNBEAT_HITS` : chaque temps fort (pas 0, 4, 8, 12, voir `STEPS_PER_BAR`) a au moins une note, n'importe quelle piste.
  - `FINAL_HIT` : au moins une note sur le dernier pas (`STEP_COUNT - 1`).
  - `RISING_DENSITY` : strictement plus de notes sur les pas 8 à 15 que sur les pas 0 à 7, toutes pistes confondues.
  - `SILENCE` : au plus 75 % des notes attendues (somme des `target_density` × `STEP_COUNT`).
- Nom lisible d'une valeur : `MusicTypes.Phase.keys()[phase]` → `"COMPOSITION"`.

### `NewsData` : une news

| Champ | Pour l'UI |
|---|---|
| `headline: String` | Le titre à afficher |
| `anchor_lines: PackedStringArray` | Les phrases du présentateur, dans l'ordre (`anchor_line_changed`) |
| `bpm: float` | Animer en rythme : un temps dure `60.0 / bpm` secondes |
| `special_criterion: MusicTypes.SpecialCriterion` | La consigne bonus, si tu veux l'afficher |
| `target_density: PackedFloat32Array` | Densité attendue de 0 à 1 par piste (indexée par `Lane`), si tu veux un indice visuel |
| `id: StringName` | Identifiant unique, ex. `&"cat_mayor"` (pour choisir un décor par news) |

Les autres champs servent à la musique : ignore-les.

### `NoteData` : une note du chart (lecture seule)

`index: int` (position dans le chart = le `note_index` des signaux), `lane: int`, `time_sec: float` (§4).

### `Composition` : une grille

Lecture : `is_active(lane, step) -> bool`, `get_column(step) -> Array[bool]` (les 4 pistes d'un pas), `count_notes() -> int`. Modification (`set_cell(lane, step, active)`, `clear()`) uniquement sur ta propre copie locale, jamais sur celle reçue de `composition_finished`.

---

## 6. Encore provisoire côté musique

Les signatures ne bougeront pas : tu peux tout brancher dès maintenant.

- **Une seule news** (`cat_mayor`), avec une boucle et des sons provisoires : chaque partie joue la même.
- **Équilibrage** : les gains d'audimat sont des valeurs de test.

---

## 7. Points ouverts (à trancher ensemble)

1. **Appui dans le vide** : il remet le combo à zéro (via `combo_changed`), mais aucun signal ne dit sur quelle piste. Si tu veux un feedback dédié, on ajoute `stray_pressed(lane)`.
