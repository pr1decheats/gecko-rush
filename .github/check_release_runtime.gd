extends SceneTree
## Run against the exact exported pack; this file itself is excluded from export.
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var progress: Node = root.get_node("Progress")
	root.get_node("Audio").set_music_enabled(false)
	check(str(ProjectSettings.get_setting("application/config/version")) == "2.6.0", "Exported project version")
	check(progress.available_fps() == [60, 120, 240], "Desktop 240 FPS option survives export")
	progress.data.settings["fps"] = 240
	progress.settings_changed()
	check(Engine.max_fps == 240, "Desktop applies 240 FPS render cap")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/catalog.json"))
	check(catalog.get("skins", {}).size() == 21, "All illustrated characters are exported")
	var visual: GDScript = load("res://scripts/gecko.gd")
	for id: String in catalog["skins"]:
		var gecko: Node2D = visual.new()
		gecko.set_skin(id)
		root.add_child(gecko)
		gecko.set_process(false)
		gecko.mode = "run"
		check(gecko._sync_detailed_visual() and gecko._detailed_run.visible, "Exported run atlas: " + id)
		gecko.mode = "sleep"
		check(gecko._sync_detailed_visual() and gecko._detailed_sleep.visible, "Exported sleep atlas: " + id)
		check(gecko._detailed_run.texture.get_width() > 1000 and gecko._detailed_sleep.texture.get_width() > 1000, "Full resolution textures load through export remaps: " + id)
		gecko.queue_free()
	await process_frame
	print("RELEASE_RUNTIME: %d checks, %d failures; illustrated geckos=21, poses=42, desktop_cap=%d" % [checks, failures, Engine.max_fps])
	quit(0 if failures == 0 else 1)
