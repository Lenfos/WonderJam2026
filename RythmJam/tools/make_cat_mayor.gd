extends SceneTree
## Builds data/news/cat_mayor.tres and lets Godot serialize it. Re-run after editing the values.
## From the repo root: godot --headless --path RythmJam --script res://tools/make_cat_mayor.gd

const OUTPUT_PATH := "res://data/news/cat_mayor.tres"


func _init() -> void:
	var news := NewsData.new()
	news.id = &"cat_mayor"
	news.headline = "Un chat élu maire de la ville"
	news.anchor_lines = PackedStringArray([
		"Flash spécial : un chat vient d'être élu maire de la ville.",
		"Il l'emporte largement, loin devant ses rivaux humains.",
		"Sa première mesure : la sieste obligatoire pour tous.",
	])
	news.bpm = 110.0
	news.scale = MusicTypes.ScaleType.MAJOR_PENTATONIC
	news.special_criterion = MusicTypes.SpecialCriterion.VARIETY
	news.backing_track = load("res://audio/placeholder/test_loop_110.wav")
	# Placeholder values, to tune with the real music. Melodies are scale degrees (5 = root an octave up).
	news.target_density = PackedFloat32Array([0.5, 0.25, 0.25, 0.25])
	news.brass_melody = PackedInt32Array([0, 1, 2, 1, 2, 3, 4, 3, 2, 3, 4, 5, 4, 3, 1, 0])
	news.bells_melody = PackedInt32Array([2, 3, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 6, 5, 4, 5])

	var errors := news.validate()
	if not errors.is_empty():
		push_error("cat_mayor invalid, not saved: %s" % [errors])
	else:
		var err := ResourceSaver.save(news, OUTPUT_PATH)
		if err != OK:
			push_error("Could not save %s: %s" % [OUTPUT_PATH, error_string(err)])
		else:
			print("Saved %s" % OUTPUT_PATH)
	quit()
