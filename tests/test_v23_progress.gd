extends SceneTree
## Difficulty pacing, capped XP, skill gates, migration, and durable run identity.

const TUNING = preload("res://scripts/tuning.gd")
var p: Node
var checks := 0
var failures := 0
var save_path: String

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func fresh() -> void:
	p.data = p._defaults()
	p.data["settings"]["music"] = false
	# Avoid disk writes for farming simulations; explicit persistence checks below
	# re-enable normal writes against their own isolated save path.
	p._loading = true

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	p = load("res://scripts/progress.gd").new()
	save_path = "user://v23_progress_%d.json" % Time.get_ticks_usec()
	p.save_file = save_path
	root.add_child(p)
	await process_frame
	fresh()
	var previous_start := 0.0
	var previous_late := 0.0
	var previous_xp := 0.0
	for world: Dictionary in p.WORLDS:
		var id: String = world["id"]
		var profile: Dictionary = TUNING.profile_for(id)
		var late_speed: float = TUNING.speed_at(12000.0 * TUNING.PIXELS_PER_METRE, id)
		check(profile["start_speed"] > previous_start and late_speed > previous_late, id + " has a distinct increasing pace at the start and beyond 12km")
		check(late_speed > TUNING.MAX_SPEED and TUNING.speed_at(50000.0 * TUNING.PIXELS_PER_METRE, id) > late_speed, id + " keeps accelerating beyond the deprecated compatibility ceiling")
		check(profile["xp_multiplier"] > previous_xp, id + " rewards difficulty with more XP")
		check(TUNING.speed_at(-100.0, id) == profile["start_speed"], id + " clamps negative distance")
		check(TUNING.speed_at(1.0e12, id) > late_speed, id + " has no final distance or speed cap")
		check(is_equal_approx(TUNING.run_speed_at(100000.0, 45.0, id), float(profile["night_speed"])), id + " uses its own slow fixed pace at night")
		var last_speed: float = profile["start_speed"]
		var increasing := true
		for metres: int in range(0, 3501, 25):
			var speed: float = TUNING.speed_at(float(metres) * TUNING.PIXELS_PER_METRE, id)
			increasing = increasing and speed >= last_speed
			last_speed = speed
		check(increasing, id + " acceleration is monotonic")
		check(TUNING.speed_at(640.0, id) > profile["start_speed"] and TUNING.speed_at(640.0, id) < float(profile["start_speed"]) * 1.02, id + " starts with a small gain across the first ten metres")
		check(absf(TUNING.run_speed_at(64000.0, 39.999, id) - TUNING.min_speed_at(64000.0, id)) < 0.01, id + " dusk joins the local night curve continuously")
		check(absf(TUNING.run_speed_at(64000.0, 60.001, id) - TUNING.min_speed_at(64000.0, id)) < 0.01, id + " dawn begins continuously")
		previous_start = profile["start_speed"]
		previous_late = late_speed
		previous_xp = profile["xp_multiplier"]
	var mutable: Dictionary = TUNING.profile_for("jungle")
	mutable["start_speed"] = 99999.0
	check(TUNING.profile_for("jungle")["start_speed"] == 800.0, "Profile callers cannot mutate shared tuning")
	check(TUNING.profile_for("unknown") == TUNING.profile_for("jungle"), "Unknown profiles use a safe Easy fallback")
	check(TUNING.speed_at(1234.0) == TUNING.speed_at(1234.0, "jungle"), "Legacy speed signature remains valid")
	check(TUNING.run_speed_at(1234.0, 12.0) == TUNING.run_speed_at(1234.0, 12.0, "jungle"), "Legacy run-speed signature remains valid")
	check(p.get_level() == 1 and p.is_world_unlocked("jungle"), "A new profile starts on Easy")
	check(not p.is_world_unlocked("sky"), "A new profile cannot select Insane")
	var first: Dictionary = p.finish_run({"world_id": "jungle", "height": 100.0, "passed": 4, "jumps": 1, "coins": 2, "run_id": "short"})
	check(first["xp"] == 26 and first["xp"] < 35, "Easy first-run XP is slower than v2.2, including the same achievement")
	var repeat: Dictionary = p.finish_run({"height": 100.0, "passed": 5, "run_id": "repeat"})
	check(repeat["xp"] == 6 and repeat["xp"] < 12, "Easy repeat XP is slower than v2.2")
	fresh()
	for index: int in 12:
		var before: int = p.data["xp"]
		var farm: Dictionary = p.finish_run({"world_id": "jungle", "height": 10000000.0, "passed": 100000, "jumps": 10000, "coins": 10000, "run_id": "easy_farm_%d" % index})
		check(farm["xp"] == int(p.data["xp"]) - before, "Farm result reports only actual XP awarded")
	check(p.data["xp"] == p.xp_for_level(5) and p.get_level() == 5, "Unlimited Easy farming stops exactly at level5")
	check("height_5000" in p.data["achievements"] and "coins_1000" in p.data["achievements"], "Farming test includes one-time achievement bonuses")
	check(p.is_world_unlocked("canyon") and not p.is_world_unlocked("ice") and not p.is_world_unlocked("sky"), "Easy alone never unlocks higher difficulties")
	check(p.world_xp_status("jungle")["capped"], "Easy UI reports its reached XP ceiling")
	var spoofed: Dictionary = p.finish_run({"world_id": "sky", "height": 10000000, "run_id": "locked_spoof"})
	check(spoofed["world_id"] == "jungle" and spoofed["xp"] == 0, "A locked world's submitted ID cannot bypass the XP gate")
	var status: Dictionary = p.world_unlock_status("ice")
	check(status["level_required"] == 12 and status["previous_world"] == "canyon" and status["required_metres"] == 450.0 and status["best_metres"] == 0.0, "Unlock status exposes the actual previous-world skill requirement")
	fresh()
	p.data["xp"] = p.xp_for_level(50)
	check(not p.is_world_unlocked("canyon") and not p.is_world_unlocked("sky"), "High global XP alone does not bypass fresh-profile skill gates")
	var inherited_xp: int = p.data["xp"]
	var capped: Dictionary = p.finish_run({"world_id": "jungle", "height": 5000, "jumps": 100, "coins": 1000, "run_id": "keep_old_xp"})
	check(p.data["xp"] == inherited_xp and capped["xp"] == 0, "Ceilings never remove XP already above them")
	fresh()
	p.data["xp"] = p.xp_for_level(5)
	p.data["world_stats"]["jungle"] = p._empty_world_stats()
	p.data["world_stats"]["jungle"]["best_height"] = 299.99
	check(not p.is_world_unlocked("canyon"), "A short previous-world record cannot satisfy a skill gate")
	p.data["world_stats"]["jungle"]["best_height"] = 300.0
	check(p.is_world_unlocked("canyon"), "The exact previous-world skill threshold satisfies its gate")
	p.data["xp"] = p.xp_for_level(5) - 1
	check(not p.is_world_unlocked("canyon"), "Meeting the skill threshold still requires the level threshold")
	fresh()
	p.data["xp"] = p.xp_for_level(5) - 1
	var exact: Dictionary = p.finish_run({"height": 300.0, "jumps": 1, "run_id": "exact_cap"})
	check(exact["xp"] == 1 and p.data["xp"] == p.xp_for_level(5), "Base XP and achievements stop truthfully on the exact next-world threshold")
	check(p.is_world_unlocked("canyon"), "Reaching the exact cap can unlock the next world without a deadlock")
	fresh()
	for index: int in range(p.WORLDS.size() - 1):
		var id: String = p.WORLDS[index]["id"]
		var next_id: String = p.WORLDS[index + 1]["id"]
		check(p.select_world(id), "Progression chain can enter " + id)
		p._loading = true
		var chain: Dictionary = p.finish_run({"world_id": id, "height": 10000000.0, "jumps": 1000, "passed": 10000, "coins": 1000, "run_id": "chain_" + id})
		var gate: int = p.WORLDS[index + 1]["unlock"]
		check(p.data["xp"] == p.xp_for_level(gate), id + " can earn enough XP to reach the next gate exactly")
		check(p.is_world_unlocked(next_id), id + " skill and XP unlock " + next_id)
		check(chain["world_id"] == id, "Run keeps its recorded world identity")
	check(p.select_world("sky"), "The complete skill chain reaches Insane")
	p._loading = true
	var before_sky: int = p.data["xp"]
	var sky_run: Dictionary = p.finish_run({"world_id": "sky", "height": 1000.0, "passed": 100, "run_id": "uncapped_sky"})
	check(sky_run["xp"] > 0 and p.data["xp"] > before_sky and not p.world_xp_status("sky")["capped"], "Insane continues permanent XP beyond the last world gate")
	# A completed run carries its own world, even if selection has since changed.
	p.data["selected_world"] = "jungle"
	var jungle_before: Dictionary = p.data["world_stats"]["jungle"].duplicate(true)
	var canyon_before: Dictionary = p.data["world_stats"]["canyon"].duplicate(true)
	var attributed: Dictionary = p.finish_run({"world_id": "canyon", "height": 123.0, "passed": 7, "jumps": 5, "coins": 3, "run_id": "attribution"})
	check(attributed["world_id"] == "canyon" and p.data["world_stats"]["jungle"] == jungle_before, "Summary world_id owns the run rather than current selection")
	check(p.data["world_stats"]["canyon"]["runs"] == canyon_before["runs"] + 1 and p.data["world_stats"]["canyon"]["total_distance"] == canyon_before["total_distance"] + 123.0, "Per-world runs and distance accumulate independently")
	check(p.world_run_distances("canyon")["last"] == 123.0, "Per-world last distance is available for UI")
	p.finish_run({"world": "ice", "height": 45.0, "run_id": "legacy_world"})
	check(p.data["last_result"]["world_id"] == "ice", "Legacy summary.world remains accepted")
	var duplicate_before: Dictionary = p.data.duplicate(true)
	var duplicate: Dictionary = p.finish_run({"world_id": "sky", "height": 99999.0, "run_id": "attribution"})
	check(p.data == duplicate_before and duplicate == attributed, "An older duplicate run changes no counters and returns its own original result")
	# Migration preserves old global records and grandfathered XP-only unlocks.
	var legacy: Dictionary = {"version": 3, "coins": 91, "xp": p.xp_for_level(50), "best_height": 5000.0, "total_distance": 12345.0, "runs": 22, "selected_world": "sky", "settings": {"music": false, "language": "en", "fps": 120}, "achievements": ["first_jump", "height_5000"]}
	p.data = p._sanitize(legacy)
	check(p.data["coins"] == 91 and p.data["xp"] == legacy["xp"] and p.data["runs"] == 22, "Legacy migration retains all currency and run counts")
	check(p.data["best_height"] == 5000.0 and p.data["total_distance"] == 12345.0, "Legacy global records are retained without inventing a world of origin")
	check(p.is_world_unlocked("sky") and p.data["selected_world"] == "sky", "Old XP-only world unlocks and selected world are grandfathered")
	check(p.data["settings"]["language"] == "en" and p.data["settings"]["fps"] == 120, "Migration retains settings")
	p._loading = false
	p.save_game()
	p.load_game()
	check(p.is_world_unlocked("sky") and p.data["xp"] == legacy["xp"] and p.data["progression_rules"] == 23, "Grandfathered unlocks and existing XP survive save/reload")
	# Explicit persisted unlocks survive even if old XP is below today's gate.
	legacy["progression_rules"] = 23
	legacy["unlocked_worlds"] = ["jungle", "sky", "missing", "sky"]
	legacy["xp"] = 0
	p.data = p._sanitize(legacy)
	check(p.is_world_unlocked("sky") and p.data["unlocked_worlds"] == ["jungle", "sky"], "Saved unlock list is preserved, validated, and deduplicated")
	fresh()
	p._loading = false
	var durable: Dictionary = p.finish_run({"world_id": "jungle", "height": 300.0, "jumps": 4, "run_id": "durable"})
	p.finish_run({"world_id": "jungle", "height": 50.0, "run_id": "durable_later"})
	p.load_game()
	var persisted_before: Dictionary = p.data.duplicate(true)
	var persisted_duplicate: Dictionary = p.finish_run({"height": 9999.0, "run_id": "durable"})
	check(p.data == persisted_before and persisted_duplicate == durable, "Run-specific idempotency survives save/reload")
	check(p.data["world_stats"]["jungle"]["runs"] == 2 and p.world_run_distances("jungle")["best"] == 300.0, "Per-world statistics survive save/reload")
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	p.free()
	var audio: Node = root.get_node_or_null("Audio")
	if audio != null:
		audio.set_music_enabled(false)
		audio.set_sfx_enabled(false)
	await process_frame
	await process_frame
	await create_timer(0.06).timeout
	print("V23 progression: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
