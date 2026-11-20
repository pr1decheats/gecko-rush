extends SceneTree
## Run with the editor against the exact exported pack; excluded from export.
## Official release templates intentionally disable external --script overrides.
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _has_mesh(node: Node) -> bool:
	if node is MeshInstance2D:
		return true
	for child: Node in node.get_children():
		if _has_mesh(child):
			return true
	return false

func _valid_tongue(geometry: Dictionary, limit: float) -> bool:
	var mouth: Variant = geometry.get("mouth")
	var tip: Variant = geometry.get("tip")
	return mouth is Vector2 and tip is Vector2 and mouth.is_finite() and tip.is_finite() and mouth.distance_to(tip) <= limit + 0.01

func _run() -> void:
	await process_frame
	var progress: Node = root.get_node("Progress")
	root.get_node("Audio").set_music_enabled(false)
	check(str(ProjectSettings.get_setting("application/config/version")) == "2.8.0", "Exported project version")
	check(progress.available_fps() == [60, 120, 240], "Desktop 240 FPS option survives export")
	progress.data.settings["fps"] = 240
	progress.settings_changed()
	check(Engine.max_fps == 240, "Desktop applies 240 FPS render cap")
	var visual: GDScript = load("res://scripts/gecko.gd")
	check(int(visual.get_script_constant_map().get("RENDERER_REVISION", 0)) == 27, "Exported compact live character renderer")
	check(progress.SKINS.size() == 21, "Free character and all twenty outfits remain available")
	check(not FileAccess.file_exists("res://assets/characters/catalog.json"), "Unused atlas catalog is excluded from the game")
	for skin: Dictionary in progress.SKINS:
		var id := str(skin["id"])
		var gecko: Node2D = visual.new()
		gecko.set_skin(id)
		root.add_child(gecko)
		gecko.set_process(false)
		gecko.mode = "run"
		check(gecko.skin_id == id and not _has_mesh(gecko), "Outfit uses the same live rig without warped atlas meshes: " + id)
		var mouth: Vector2 = gecko.get_mouth_position()
		check(mouth.is_finite() and mouth.length() < 120.0, "Mouth anchor stays on the compact head: " + id)
		gecko.eat_to(mouth + Vector2(-20.0, -10.0))
		gecko._process(0.035)
		check(gecko.is_eating() and _valid_tongue(gecko.get_tongue_geometry(), 105.0), "Tongue extends from the articulated mouth within reach: " + id)
		gecko.position += Vector2(0.0, -20000.0)
		gecko._process(0.055)
		check(_valid_tongue(gecko.get_tongue_geometry(), 105.0), "High-speed movement cannot stretch tongue across the screen: " + id)
		gecko.mode = "jump"
		gecko.launch()
		check(not gecko.is_eating(), "Jump cancels fly capture cleanly: " + id)
		gecko.reset_animation()
		gecko.mode = "sleep"
		check(gecko.get_mouth_position().is_finite() and not gecko.is_eating() and not _has_mesh(gecko), "Sleep retains the same connected rig: " + id)
		gecko.set_launch_pose(0.54)
		check(gecko.get_mouth_position().is_finite() and gecko.skin_id == id, "Wake pose retains outfit and head attachment: " + id)
		gecko.queue_free()
	await process_frame
	print("RELEASE_RUNTIME: %d checks, %d failures; live articulated outfits=21, bounded tongue=105, desktop_cap=%d" % [checks, failures, Engine.max_fps])
	quit(0 if failures == 0 else 1)
