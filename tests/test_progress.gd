extends SceneTree

var failures: Array[String] = []
var checks: int = 0
var progress: Node
var test_save: String

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func _run() -> void:
	var script: Script = load("res://scripts/progress.gd")
	progress = script.new()
	test_save = "user://qa_progress_%d.json" % Time.get_ticks_usec()
	progress.save_file = test_save
	root.add_child(progress)
	await process_frame
	check(progress.get_level() == 1, "A new profile starts at level 1")
	check(progress.data["coins"] == 0 and progress.data["xp"] == 0, "New balance and XP are zero")
	check(progress.current_world()["id"] == "jungle", "Jungle is the initial world")
	check(not progress.select_world("canyon"), "Locked worlds cannot be selected")
	var instant: Dictionary = progress.finish_run({"height": 0, "coins": 0, "jumps": 0, "passed": 0, "run_id": "instant"})
	check(instant["reward_coins"] == 0 and instant["xp"] == 0, "Instant death cannot farm rewards")
	var first: Dictionary = progress.finish_run({"height": 100, "coins": 2, "jumps": 1, "passed": 4, "run_id": "first"})
	check(first["reward_coins"] - first["level_bonus"] == 4, "100m payout: 2 pickups + 0 height + 2 record")
	check(first["new_achievements"] == ["first_jump"] and first["xp"] == 35, "First 100m pays the jump goal and restrained XP")
	check(progress.get_level() == 1, "A short first run does not immediately farm a level")
	var good: Dictionary = progress.finish_run({"height": 400, "coins": 8, "jumps": 35, "passed": 12, "run_id": "good"})
	check(progress.get_level() > 1, "Several meaningful runs still raise the permanent level")
	check(good["reward_coins"] - good["level_bonus"] == 12, "Good record run pays 12 before level bonus")
	var repeat_good: Dictionary = progress.finish_run({"height": 400, "coins": 8, "jumps": 35, "passed": 12, "run_id": "repeat_good"})
	check(repeat_good["reward_coins"] - repeat_good["level_bonus"] == 10, "Ordinary good run pays 10 before level bonus")
	check(not "first_jump" in repeat_good["new_achievements"], "An achievement pays XP only once")
	progress.finish_run({"height": 300, "coins": 2, "jumps": 1, "passed": 0, "run_id": "daily_finish"})
	var tasks: Array = progress.daily_tasks()
	check(tasks[0]["complete"] and tasks[1]["complete"] and tasks[2]["complete"], "Daily progress combines runs and uses best single-run height")
	var before_claim: int = progress.data["coins"]
	check(progress.claim_daily("jumps"), "Completed daily reward can be claimed")
	check(progress.data["coins"] == before_claim + 3, "Daily jump reward adds exactly three coins")
	check(not progress.claim_daily("jumps"), "A daily reward cannot be claimed twice")
	check(not progress.claim_daily("missing"), "Unknown daily IDs cannot pay")
	var before_duplicate: Dictionary = progress.data.duplicate(true)
	var duplicate: Dictionary = progress.finish_run({"height": 300, "coins": 2, "jumps": 1, "passed": 0, "run_id": "daily_finish"})
	check(progress.data["coins"] == before_duplicate["coins"] and progress.data["runs"] == before_duplicate["runs"], "Repeated run ID never pays or counts twice")
	check(not duplicate.is_empty(), "Idempotent finalization returns the saved result")
	var snapshot: Dictionary = {"run_id": "resume-test", "height": 123.5, "phase": 0.12345678901234567, "coins": 4, "player": [123.0, -4100.0], "obstacles": [{"type": "rock", "x": 540.0}]}
	progress.save_resume(snapshot)
	check(progress.load_resume()["run_id"] == "resume-test", "Checkpoint is retained independently of rewards")
	var balance: int = progress.data["coins"]
	var xp: int = progress.data["xp"]
	progress.load_game()
	check(progress.data["coins"] == balance and progress.data["xp"] == xp, "Coins and XP survive closing and reopening")
	check(progress.load_resume()["player"][1] == -4100.0, "Checkpoint survives a reload")
	check(absf(progress.load_resume()["phase"] - 0.12345678901234567) < 1.0e-15, "Checkpoint phases preserve full floating-point precision")
	check(progress.daily_tasks()[0]["claimed"], "Claimed daily state survives reload")
	# Prepare an identical backup then corrupt only the current file.
	progress.save_game()
	progress.save_game()
	var broken: FileAccess = FileAccess.open(test_save, FileAccess.WRITE)
	broken.store_string("{ broken JSON")
	broken.close()
	progress.load_game()
	check(progress.data["coins"] == balance and progress.data["xp"] == xp, "A damaged main file recovers the verified backup")
	var sanitized: Dictionary = progress._sanitize({"version": 3, "coins": "invalid", "xp": -42, "runs": [], "best_height": -12, "settings": {"music": false, "sfx": "bad"}, "selected_world": "missing", "achievements": ["first_jump", "first_jump", "invalid"]})
	check(sanitized["coins"] == 0 and sanitized["xp"] == 0 and sanitized["runs"] == 0 and sanitized["best_height"] == 0.0, "Malformed or negative counters are sanitized")
	check(not sanitized["settings"]["music"] and sanitized["settings"]["sfx"], "Music and effects have separate validated settings")
	check(sanitized["achievements"].size() == 1, "Achievement data is deduplicated and known")
	progress.data["daily"]["date"] = "2000-01-01"
	check(progress.daily_tasks()[0]["value"] == 0 and not progress.daily_tasks()[0]["claimed"], "A new local day resets progress and claims")
	var before_unlock_test: Dictionary = progress.data.duplicate(true)
	progress.data["xp"] = 0
	progress.data["best_height"] = 2000.0
	progress.data["jumps"] = 1000
	progress.data["achievements"] = ["first_jump", "height_1000", "jumps_100", "level_10"]
	var locked_goals: Dictionary = progress.finish_run({"height": 0, "coins": 0, "jumps": 0, "passed": 0, "run_id": "blocked_goals_25"})
	check(not "height_2000" in progress.data["achievements"] and not "jumps_1000" in progress.data["achievements"], "Level-25 achievements remain locked even when their statistics are complete")
	check(locked_goals["new_achievements"].is_empty(), "Locked achievements do not grant XP")
	var level_25_xp: int = 0
	for level: int in range(1, 25):
		level_25_xp += progress.xp_required(level)
	progress.data["xp"] = level_25_xp
	var unlocked_goals: Dictionary = progress.finish_run({"height": 0, "coins": 0, "jumps": 0, "passed": 0, "run_id": "unlocked_goals_25"})
	check("height_2000" in unlocked_goals["new_achievements"] and "jumps_1000" in unlocked_goals["new_achievements"], "Both additional achievements unlock at level 25")
	check(unlocked_goals["xp"] == 370 and "level_25" in unlocked_goals["new_achievements"], "Height/jump goals and level25 award 370 XP once")
	progress.load_game()
	check("height_2000" in progress.data["achievements"] and "jumps_1000" in progress.data["achievements"], "Additional achievements survive a version-3 save reload")
	progress.data = before_unlock_test
	progress.save_game()
	var level_101_xp: int = 0
	for level: int in range(1, 101):
		level_101_xp += progress.xp_required(level)
	progress.data["xp"] = level_101_xp
	check(progress.get_level() == 101, "Level progression continues above 100")
	check(progress.level_title() == "Бессмертный геккон", "Level 100 title remains beyond 100")
	check(progress.xp_required(101) > progress.xp_required(100), "Later levels cost more XP")
	check(progress.is_world_unlocked("sky") and progress.select_world("sky"), "All six worlds can unlock and selection persists")
	progress.load_game()
	check(progress.current_world()["id"] == "sky", "World selection survives reload")
	progress.clear_resume()
	check(progress.load_resume().is_empty(), "A finalized or abandoned checkpoint can be cleared")
	for suffix: String in ["", ".bak", ".tmp"]:
		var absolute: String = ProjectSettings.globalize_path(test_save + suffix)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)
	progress.queue_free()
	await process_frame
	# The extra Progress instance deliberately exercises load_game/settings_changed.
	# Those calls can re-enable the autoload score; release audio before quitting.
	var audio_manager: Node = root.get_node_or_null("Audio")
	if audio_manager != null:
		audio_manager.set_music_enabled(false)
		audio_manager.set_sfx_enabled(false)
	await process_frame
	await process_frame
	# Allow the mixer thread to consume stop commands before SceneTree teardown.
	await create_timer(0.06).timeout
	if failures.is_empty():
		print("PASS: progression — %d checks" % checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d progression checks" % [failures.size(), checks])
		quit(1)
