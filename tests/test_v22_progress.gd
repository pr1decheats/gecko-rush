extends SceneTree
var p: Node
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
func threshold(level: int) -> int:
	var result := 0
	for n: int in range(1, level):
		result += p.xp_required(n)
	return result
func fresh() -> void:
	p.data = p._defaults()
	p.data["settings"]["music"] = false
func satisfy_previous_world_records(through_id: String) -> void:
	for world: Dictionary in p.WORLDS:
		var previous: String = world["previous_world"]
		if not previous.is_empty():
			var stats: Dictionary = p.data["world_stats"].get(previous, p._empty_world_stats())
			stats["best_height"] = maxf(float(stats["best_height"]), float(world["required_metres"]))
			p.data["world_stats"][previous] = stats
		if world["id"] == through_id:
			break
	p._refresh_world_unlocks()
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	p = load("res://scripts/progress.gd").new()
	p.save_file = "user://v22_economy_test.json"
	root.add_child(p)
	await process_frame
	fresh()
	for id: String in ["height_100", "height_500", "coins_100"]:
		check(not p._known_achievement(id), "Removed goal is unknown: " + id)
	for id: String in ["height_5000", "coins_1000", "level_25", "level_50"]:
		check(p._known_achievement(id), "New goal exists: " + id)
	var original := {"version": 3, "coins": 31, "xp": 12345, "lifetime_coins": 1001, "best_height": 5200.0, "total_distance": 15000.0, "achievements": ["height_100", "height_500", "coins_100", "first_jump", "height_1000", "jumps_100", "level_10", "first_jump"]}
	p.data = p._sanitize(original)
	check(p.data["xp"] == 12345 and p.data["coins"] == 31 and p.data["lifetime_coins"] == 1001, "Migration preserves all currency")
	check(p.data["best_height"] == 5200.0 and p.data["total_distance"] == 15000.0, "Migration preserves records")
	check(p.data["achievements"] == ["first_jump", "height_1000", "jumps_100", "level_10"], "Migration removes deleted IDs and duplicate flags")
	p.save_game()
	p.load_game()
	check(p.data["xp"] == 12345 and p.data["coins"] == 31, "Migration survives save/reload")
	check(p.data["achievements"] == ["first_jump", "height_1000", "jumps_100", "level_10"], "Existing achievements survive reload")
	fresh()
	var first: Dictionary = p.finish_run({"height": 100.0, "passed": 4, "jumps": 1, "coins": 2, "run_id": "first"})
	check(first["xp"] == 26 and p.get_level() == 1, "Easy first 100m: floor((10 height + 2 passed + 8 record) × 0.55) + 15 first jump")
	check(first["new_achievements"] == ["first_jump"], "Only first jump unlocks at 100m")
	var second: Dictionary = p.finish_run({"height": 100.0, "passed": 5, "jumps": 1, "coins": 2, "run_id": "second"})
	check(second["xp"] == 6, "Easy repeat XP floors 5 obstacles to 2, then floors 12 base XP × 0.55")
	var before_duplicate: Dictionary = p.data.duplicate(true)
	p.finish_run({"height": 5000, "passed": 500, "jumps": 1000, "coins": 1000, "run_id": "second"})
	check(p.data == before_duplicate, "Duplicate run ID cannot change any counters")
	fresh()
	p.data["coins"] = 1000
	p.data["lifetime_coins"] = 999
	check(not p._achievement_complete("coins_1000"), "Balance cannot complete lifetime-earnings goal")
	p.data["coins"] = 0
	p.data["lifetime_coins"] = 1000
	check(p._achievement_complete("coins_1000"), "Spent earnings still complete lifetime-earnings goal")
	p.data["total_distance"] = 10000.0
	p.data["best_height"] = 4999.99
	check(not p._achievement_complete("height_5000"), "Total distance cannot complete single-run height goal")
	p.data["best_height"] = 5000.0
	check(p._achievement_complete("height_5000"), "Single-run 5000m completes height goal")
	fresh()
	p.data["best_height"] = 1000.0
	p.data["xp"] = threshold(25) - 50
	p.data["achievements"] = ["level_10"]
	satisfy_previous_world_records("crystal")
	check(p.select_world("crystal"), "Level25 chain runs on earned Expert difficulty below its level30 XP ceiling")
	var chained25: Dictionary = p.finish_run({"height": 0, "run_id": "chain25"})
	check("height_1000" in chained25["new_achievements"] and "level_25" in chained25["new_achievements"], "Height achievement can cross level25 and award its milestone")
	check(chained25["xp"] == 200, "Level25 chain pays height + milestone once")
	var repeat25: Dictionary = p.finish_run({"height": 0, "run_id": "repeat25"})
	check(repeat25["xp"] == 0 and repeat25["new_achievements"].is_empty(), "Milestone chain cannot pay twice")
	fresh()
	p.data["best_height"] = 5000.0
	p.data["xp"] = threshold(50) - 100
	p.data["lifetime_coins"] = 999
	p.data["achievements"] = ["height_1000", "level_10", "level_25", "height_2000"]
	satisfy_previous_world_records("volcano")
	check(p.select_world("volcano"), "Level50 chain runs on earned Nightmare difficulty")
	var chained50: Dictionary = p.finish_run({"height": 0, "run_id": "chain50"})
	check("height_5000" in chained50["new_achievements"] and "level_50" in chained50["new_achievements"] and "coins_1000" in chained50["new_achievements"], "Height XP, level50 and level coin rewards resolve every goal")
	check(chained50["xp"] == 100 and chained50["level_bonus"] == 1 and p.data["xp"] == threshold(50), "Nightmare clips all chained achievement XP to its level50 ceiling and pays one level coin")
	check(p.data["coins"] == 1 and p.data["lifetime_coins"] == 1000, "Level reward counts as earned currency")
	p.save_game()
	p.load_game()
	var same: Dictionary = p.finish_run({"height": 0, "run_id": "chain50-reloaded"})
	check(same["xp"] == 0 and same["new_achievements"].is_empty(), "Reloaded milestone flags prevent double payouts")
	fresh()
	p.data["lifetime_coins"] = 997
	p.data["daily"]["jumps"] = 30
	check(p.claim_daily("jumps") and p.data["lifetime_coins"] == 1000, "Daily reward increases earned lifetime coins")
	var daily_coins: Dictionary = p.finish_run({"height": 0, "run_id": "daily-earned"})
	check(daily_coins["new_achievements"] == ["coins_1000"] and daily_coins["xp"] == 80, "Daily-earned lifetime goal pays once")
	var locale: Node = load("res://scripts/l10n.gd").new()
	root.add_child(locale)
	locale.set_language("en")
	var cyrillic := RegEx.new()
	cyrillic.compile("[А-Яа-яЁё]")
	for item: Dictionary in p.ACHIEVEMENTS:
		for key: String in ["name", "title", "description"]:
			check(cyrillic.search(locale.text(item[key])) == null, "English field fully translated: " + item["id"] + "." + key)
	locale.set_language("ru")
	for item: Dictionary in p.ACHIEVEMENTS:
		check(locale.text(item["description"]) == item["description"], "Russian source preserved: " + item["id"])
	locale.free()
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p.save_file + suffix))
	p.free()
	var audio: Node = root.get_node_or_null("Audio")
	if audio != null:
		audio.set_music_enabled(false)
		audio.set_sfx_enabled(false)
	await process_frame
	await process_frame
	await create_timer(0.06).timeout
	print("V22 progression isolated: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
