# Contrat musique ↔ UI

Ce document décrit l'API que le code UI/rendu utilise pour parler au code musique/gameplay.

**Règle d'or :** les deux côtés communiquent **uniquement** par :
- les signaux de l'autoload `MusicBus` : la musique émet des **états**, l'UI émet des **requêtes** (signaux `*_requested`) ;
- les classes de données partagées : `MusicTypes`, `NewsData`, `Composition`.

Le code musique ne touche jamais aux nœuds UI, et l'UI ne touche pas aux scripts internes de `scripts/music/` (hors ces trois classes).

Fichiers : `scripts/music/music_types.gd`, `news_data.gd`, `composition.gd`, `music_bus.gd`.

---

## `MusicTypes` : constantes et enums

Classe statique, on ne l'instancie jamais : on écrit `MusicTypes.LANE_COUNT`, `MusicTypes.Lane.KICK`, etc.

| Nom | Valeur | Sens |
|---|---|---|
| `LANE_COUNT` | 4 | Nombre de pistes (lignes de la grille / colonnes du jeu de rythme) |
| `STEP_COUNT` | 16 | Nombre de pas de la grille. **1 pas = 1 temps** au BPM de la news |
| `PERFECT_WINDOW_SEC` | 0.050 | Écart max (en s, avant ou après la note) pour un PERFECT |
| `GOOD_WINDOW_SEC` | 0.100 | Écart max pour un GOOD |
| `BAD_WINDOW_SEC` | 0.150 | Écart max pour un BAD. Au-delà, l'appui est « dans le vide » et la note finit ratée |

| Enum | Valeurs |
|---|---|
| `Lane` | `KICK`, `SNARE`, `BRASS`, `BELLS` (dans l'ordre d'affichage ; touches D F J K) |
| `Judgment` | `PERFECT`, `GOOD`, `BAD`, `MISS` |
| `ScaleType` | `MAJOR_PENTATONIC`, `MINOR_PENTATONIC`, `WHOLE_TONE` |
| `SpecialCriterion` | `VARIETY` (toutes les pistes utilisées), `DOWNBEAT_HITS` (notes sur les pas 0, 4, 8, 12), `FINAL_HIT` (note sur le dernier pas), `RISING_DENSITY` (plus de notes en 2ᵉ moitié), `SILENCE` (peu de notes) |

Partout dans l'API, `lane` est un `int` égal à une valeur de `MusicTypes.Lane` (0 à 3) et `step` un `int` de 0 à `STEP_COUNT - 1`.

---

## `NewsData` : une news (Resource, un `.tres` par news)

Rangées dans `data/news/`. Exemple : `data/news/cat_mayor.tres`.

| Champ | Type | Utile pour l'UI ? |
|---|---|---|
| `id` | `StringName` | Identifiant unique (`&"cat_mayor"`) |
| `headline` | `String` | **Oui** : le titre affiché à l'écran |
| `anchor_lines` | `PackedStringArray` | **Oui** : les phrases lues par le présentateur, dans l'ordre |
| `bpm` | `float` | **Oui** pour la vitesse de défilement : 1 pas dure `60.0 / bpm` secondes |
| `scale` | `MusicTypes.ScaleType` | Non (côté musique) |
| `target_density` | `PackedFloat32Array` | Peut-être (indice visuel) : densité attendue 0–1 par piste, indexée par `Lane` |
| `special_criterion` | `MusicTypes.SpecialCriterion` | Peut-être (afficher la consigne bonus) |
| `backing_track` | `AudioStream` | Non (côté musique) |
| `brass_melody`, `bells_melody` | `PackedInt32Array` | **Non, l'UI ne s'en sert pas** (côté musique) : un **degré de la gamme** `scale` par pas (0 = tonique, 5 = tonique à l'octave en pentatonique, négatif = octave en dessous). Des degrés plutôt que des demi-tons : une mélodie ne peut jamais sortir de la gamme |

`validate()` renvoie la liste des erreurs lisibles (tableaux de mauvaise taille, BPM ≤ 0, degré de mélodie à plus de 2 octaves de la tonique, backing track manquante). Liste vide = news utilisable.

---

## `Composition` : la grille du joueur (RefCounted)

Grille de `LANE_COUNT × STEP_COUNT` cases on/off. C'est de la donnée pure : elle n'émet aucun signal.

| Méthode | Rôle |
|---|---|
| `is_active(lane, step) -> bool` | La case est-elle allumée ? |
| `get_column(step) -> Array[bool]` | Les 4 pistes d'un pas, indexées par `Lane` |
| `count_notes() -> int` | Nombre total de cases allumées |
| `toggle(lane, step) -> bool` | Inverse une case, renvoie son nouvel état |
| `set_cell(lane, step, active)` | Fixe une case |
| `clear()` | Éteint tout |
| `duplicate_composition() -> Composition` | Copie indépendante |
| `print(composition)` | Affiche la grille en ASCII (`X` / `.`) pour déboguer |

Côté UI, **on ne fait que lire** (`is_active`, `get_column`, `count_notes`). Pour modifier la grille, l'UI émet `cell_toggle_requested` (voir plus bas). L'UI peut garder sa propre `Composition` comme copie locale, mise à jour depuis `composition_changed` (c'est ce que fait la scène de debug).

---

## `MusicBus` : les signaux (autoload)

Accessible partout sous le nom `MusicBus`. La musique émet, l'UI écoute. **Exception** : les signaux `*_requested` vont dans l'autre sens. L'UI les émet, la musique répond par un signal d'état. L'UI n'appelle donc jamais directement le code musique.

### UI → musique (requêtes)

| Signal | Qui l'émet | Réponse de la musique |
|---|---|---|
| `cell_toggle_requested(lane: int, step: int)` | **L'UI**, quand le joueur clique une case | `composition_changed(lane, step, active)`. L'UI ne change pas la case elle-même : elle attend ce signal. Ignoré hors phase de composition |

```gdscript
# Clic sur une case :
MusicBus.cell_toggle_requested.emit(lane, step)
```

### Phase composition

| Signal | Quand il est émis | Qui écoute |
|---|---|---|
| `composition_started(news: NewsData, duration_sec: float)` | Début de la phase : grille vide, la backing track démarre, le chrono part de `duration_sec` | UI : afficher `news.headline`, vider la grille |
| `composition_time_changed(seconds_left: int)` | Secondes restantes (arrondi au-dessus), **une fois par seconde** (et une fois au départ), pas à chaque frame. Le chrono se met en pause si la fenêtre perd le focus | Affichage du chrono |
| `step_changed(step: int)` | À chaque fois que la tête de lecture du séquenceur passe à un nouveau pas | Grille : surligner la colonne courante |
| `composition_changed(lane: int, step: int, active: bool)` | Après chaque changement d'une case (clic, effacement, preset…). `active` = nouvel état | Grille : redessiner cette case |
| `composition_finished(composition: Composition)` | Une fois, à la fin de la composition (chrono écoulé ou joueur qui valide). `composition` est une copie figée : la lire, jamais la modifier | UI : passer à la vue rythme et construire les notes à faire défiler |

### Phase performance (jeu de rythme)

Règles d'un appui sur une touche (écart = distance en temps à la note la plus proche de la piste) :

| Situation | Résultat | Effet |
|---|---|---|
| Écart ≤ `PERFECT_WINDOW_SEC` (0.050 s) | `note_hit(lane, PERFECT)` | Combo +1 |
| Écart ≤ `GOOD_WINDOW_SEC` (0.100 s) | `note_hit(lane, GOOD)` | Combo +1 |
| Écart ≤ `BAD_WINDOW_SEC` (0.150 s) | `note_hit(lane, BAD)` | Combo conservé, multiplicateur en baisse |
| Aucune note à moins de 0.150 s | appui dans le vide (aucun signal de note) | Combo remis à zéro |
| Note dépassée de plus de 0.150 s sans appui | `note_missed(lane)` | Combo remis à zéro |

Chaque note n'est jugée qu'une fois : après `note_hit` ou `note_missed`, elle disparaît.

| Signal | Quand il est émis | Qui écoute |
|---|---|---|
| `note_hit(lane: int, judgment: MusicTypes.Judgment)` | Le joueur a touché une note sur `lane`. `judgment` vaut `PERFECT`, `GOOD` ou `BAD`, **jamais** `MISS` | UI rythme : feedback selon le jugement, retirer la note |
| `note_missed(lane: int)` | Une note de `lane` est sortie de la fenêtre BAD sans être touchée | UI rythme : feedback d'échec, retirer la note |
| `combo_changed(combo: int, multiplier: float)` | Dès que le combo ou le multiplicateur change (voir les règles ci-dessus) | Compteur de combo |

### Score et fin de round

L'audimat est un **nombre de téléspectateurs** (`int`, sans plafond) : le but est d'en avoir le plus possible.

| Signal | Quand il est émis | Qui écoute |
|---|---|---|
| `audimat_changed(audimat: int)` | À chaque changement du nombre de téléspectateurs | Compteur d'audimat |
| `round_finished(success: bool, audimat: int)` | Une fois, à la fin du round. `success` = l'audimat a atteint le seuil du round | Écran de résultats / enchaînement des rounds |

### Ordre d'un round

```
composition : composition_started(news, duration_sec)
           → step_changed (en boucle) + composition_time_changed (chaque seconde)
             + cell_toggle_requested (UI) → composition_changed (musique)
           → composition_finished(composition)
performance : note_hit / note_missed + combo_changed + audimat_changed
           → round_finished(success, audimat)
```

---

## Timing

Pour tout ce qui est **visuel** (position des notes qui défilent, animation en rythme), utiliser `MusicClock.get_song_time()` (temps que le joueur entend réellement), jamais un cumul de `delta`. La note du pas `step` doit arriver sur la ligne de frappe à `step * 60.0 / bpm` secondes après le début du morceau.

`MusicClock` n'existe pas encore : c'est la prochaine brique côté musique.

---

## Exemple : une UI qui écoute `MusicBus`

Exemple complet et jouable de la phase composition : `scenes/debug/sequencer_test.tscn` (script `sequencer_test.gd`). Il n'utilise que `MusicBus` et les classes de données, exactement comme la vraie UI devra le faire.

```gdscript
extends Control

@onready var _combo_label: Label = $ComboLabel
@onready var _audimat_label: Label = $AudimatLabel


func _ready() -> void:
	MusicBus.note_hit.connect(_on_note_hit)
	MusicBus.note_missed.connect(_on_note_missed)
	MusicBus.combo_changed.connect(_on_combo_changed)
	MusicBus.audimat_changed.connect(_on_audimat_changed)
	MusicBus.composition_finished.connect(_on_composition_finished)


func _on_note_hit(lane: int, judgment: MusicTypes.Judgment) -> void:
	match judgment:
		MusicTypes.Judgment.PERFECT:
			print("PERFECT sur ", MusicTypes.Lane.keys()[lane])
		MusicTypes.Judgment.GOOD:
			print("GOOD sur ", MusicTypes.Lane.keys()[lane])
		MusicTypes.Judgment.BAD:
			print("BAD sur ", MusicTypes.Lane.keys()[lane])


func _on_note_missed(lane: int) -> void:
	print("Raté sur ", MusicTypes.Lane.keys()[lane])


func _on_combo_changed(combo: int, multiplier: float) -> void:
	_combo_label.text = "x%d (%.1f)" % [combo, multiplier]


func _on_audimat_changed(audimat: int) -> void:
	_audimat_label.text = "%d téléspectateurs" % audimat


func _on_composition_finished(composition: Composition) -> void:
	for step in MusicTypes.STEP_COUNT:
		for lane in MusicTypes.LANE_COUNT:
			if composition.is_active(lane, step):
				pass  # créer la note à faire défiler pour (lane, step)
```

Pas besoin de déconnecter : Godot coupe les connexions quand le nœud est libéré.

---

## Points ouverts (à trancher ensemble)

1. **Bouton « j'ai fini »** : les clics de case passent par `cell_toggle_requested`. Il manque la requête pour terminer la composition en avance. Proposition : `composition_finish_requested()`.
2. **Début de round** : `composition_started` transmet la `NewsData` (titre, phrases, BPM). Reste à savoir si on veut aussi `performance_started()`.
3. **Seuil d'audimat** : combien de téléspectateurs faut-il pour réussir chaque round ?
4. **Identité des notes** : `note_hit` ne donne que la piste. L'UI doit retirer la plus ancienne note non jouée de cette piste (c'est aussi ce que fera le juge). Suffisant ?
5. **Appui dans le vide** : il remet le combo à zéro (visible via `combo_changed`), mais aucun signal ne dit sur quelle piste. Si l'UI veut faire clignoter la piste, on ajoute `stray_pressed(lane)`.
