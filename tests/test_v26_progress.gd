extends SceneTree
## Actual wallet, ownership, saves, XP gates and platform FPS policy.
const PROGRESS = preload("res://scripts/progress.gd")
var p: Node
var checks := 0
var failures := 0
var save_path := ""
var original_fps := 60

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func fresh(all_worlds: bool = false, completed_goals: bool = false) -> void:
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	p._loading = true
	if all_worlds:
		for world: Dictionary in p.WORLDS:
			if not world.id in p.data.unlocked_worlds:
				p.data.unlocked_worlds.append(world.id)
	if completed_goals:
		for goal: Dictionary in p.ACHIEVEMENTS:
			p.data.achievements.append(goal.id)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	original_fps = Engine.max_fps
	p = PROGRESS.new()
	save_path = "user://v26_progress_%d.json" % Time.get_ticks_usec()
	p.save_file = save_path
	root.add_child(p)
	await process_frame
	_test_catalog_and_transactions()
	_test_sanitizing_and_persistence()
	_test_fps_policy()
	_test_xp_and_world_gates()
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	p.free()
	Engine.max_fps = original_fps
	var audio := root.get_node_or_null("Audio")
	if audio != null:
		audio.set_music_enabled(false)
		audio.set_sfx_enabled(false)
	await process_frame
	await process_frame
	await create_timer(0.06).timeout
	print("V26 PROGRESSION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_catalog_and_transactions() -> void:
	fresh()
	var tiers := {
		"common": {"price": 150, "ids": ["desert_wanderer", "pirate_captain", "electro_shock"]},
		"rare": {"price": 350, "ids": ["pixel_gecko", "robo_gecko", "jungle_hunter", "venom_chameleon", "neon_pulse"]},
		"epic": {"price": 500, "ids": ["steel_knight", "cyber_ninja", "star_wanderer", "volcanic_fighter", "cosmo_gecko"]},
		"legendary": {"price": 750, "ids": ["shadow_jumper", "royal_pearl", "moon_ghost", "ghost_dragon", "frost_crystal"]},
		"mythic": {"price": 1000, "ids": ["golden_champion", "rainbow_spark"]}
	}
	check(p.SKINS.size() == 21, "Catalog contains free starter plus all twenty requested outfits")
	check(p.current_skin().id == "standard_green" and p.owns_skin("standard_green"), "Starter is free, owned and equipped")
	check(p.get_skin("standard_green").price == 0, "Starter has no coin cost")
	check(p.get_skin("not_a_skin").is_empty() and not p.owns_skin("not_a_skin"), "Unknown skins do not become valid ownership")
	var before: Dictionary = p.data.duplicate(true)
	check(not p.purchase_skin("not_a_skin") and not p.select_skin("not_a_skin"), "Unknown purchase/equip are refused")
	check(p.data == before, "Unknown actions leave the entire profile unchanged")
	check(not p.select_skin("golden_champion"), "Unowned expensive outfit cannot be equipped")
	p.data.coins = 149
	before = p.data.duplicate(true)
	check(not p.purchase_skin("desert_wanderer") and p.data == before, "One coin below the price cannot buy or mutate the profile")
	p.data.coins = 150
	p.data.lifetime_coins = 999
	check(p.purchase_skin("desert_wanderer"), "Exact common price buys the outfit")
	check(p.data.coins == 0 and p.current_skin().id == "desert_wanderer", "Purchase charges exactly once and equips immediately")
	check(p.data.lifetime_coins == 999 and not p._achievement_complete("coins_1000"), "Spending cannot manufacture lifetime earnings or achievements")
	check(p.data.xp == 0 and p.data.runs == 0 and p.data.world_stats.is_empty(), "Buying does not create XP or run statistics")
	check(p.purchase_skin("desert_wanderer") and p.data.coins == 0, "Repeated purchase succeeds as equip without another charge")
	check(p.data.owned_skins.count("desert_wanderer") == 1, "Repeated clicks cannot duplicate ownership")
	check(p.select_skin("standard_green") and p.data.coins == 0, "Free starter remains selectable after a purchase")
	var copied: Dictionary = p.get_skin("rainbow_spark")
	copied.price = 0
	check(p.get_skin("rainbow_spark").price == 1000, "Catalog data returned to callers cannot alter authoritative prices")
	fresh()
	p.data.coins = 20000
	p.data.lifetime_coins = 42
	p.data.xp = 77
	var seen: Array[String] = ["standard_green"]
	for tier: String in tiers:
		for id: String in tiers[tier].ids:
			var skin: Dictionary = p.get_skin(id)
			check(not skin.is_empty() and skin.rarity == tier and skin.price == tiers[tier].price, "Requested rarity and exact price: " + id)
			check(not str(skin.name).is_empty() and not id in seen, "Outfit has a name and unique identity: " + id)
			seen.append(id)
			var wallet: int = p.data.coins
			check(p.purchase_skin(id) and p.data.coins == wallet - int(tiers[tier].price), "Authoritative wallet charge: " + id)
			check(p.owns_skin(id) and p.current_skin().id == id, "Purchased outfit is owned and equipped: " + id)
			check(p.purchase_skin(id) and p.data.coins == wallet - int(tiers[tier].price), "Duplicate purchase cannot double charge: " + id)
			check(p.data.xp == 77 and p.data.lifetime_coins == 42, "Purchase preserves XP and lifetime earnings: " + id)
	check(seen.size() == 21 and p.data.owned_skins.size() == 21 and p.data.coins == 9550, "All twenty exact prices total 10,450 coins with no extra charges")

func _test_sanitizing_and_persistence() -> void:
	# Keep the fully purchased profile from the transaction scenario.
	p._loading = false
	p.save_game()
	p.data = p._defaults()
	p.load_game()
	check(p.data.version == 3 and p.data.owned_skins.size() == 21, "All purchased outfits survive ordinary version-3 save/reload")
	check(p.current_skin().id == "rainbow_spark" and p.data.coins == 9550, "Equipped mythic and remaining wallet survive reopening")
	check(p.data.xp == 77 and p.data.lifetime_coins == 42, "Reopening does not reinterpret purchases as earned progress")
	var sanitized: Dictionary = p._sanitize({"version": 3, "coins": 300, "xp": 912, "owned_skins": ["pirate_captain", "missing", "pirate_captain", 17, null, {}], "skin_id": "golden_champion"})
	check(sanitized.owned_skins == ["standard_green", "pirate_captain"], "Saved ownership keeps known IDs, removes invalid/duplicate entries and preserves starter")
	check(sanitized.skin_id == "standard_green", "An unowned saved selection falls back to the starter")
	sanitized = p._sanitize({"version": 3, "coins": 300, "xp": 912, "owned_skins": ["pirate_captain"], "skin_id": "pirate_captain"})
	check(sanitized.skin_id == "pirate_captain", "Known owned saved selection is retained")
	sanitized = p._sanitize({"version": 3, "coins": 123, "xp": 4567})
	check(sanitized.coins == 123 and sanitized.xp == 4567 and sanitized.owned_skins == ["standard_green"], "An older profile gains starter ownership without losing XP or coins")
	check(sanitized.skin_id == "standard_green", "Older skin-less save has a safe equipped outfit")
	p.data.skin_id = "unknown_direct_value"
	check(p.current_skin().id == "standard_green", "Reading an invalid runtime selection remains safe")

func _test_fps_policy() -> void:
	check(PROGRESS.supported_fps_for(true) == [60, 120, 240], "Desktop exposes 60/120/240 FPS")
	check(PROGRESS.supported_fps_for(false) == [60, 120], "Mobile exposes only its supported 60/120 choices")
	for rate: int in [60, 120, 240]:
		check(PROGRESS.normalize_fps(rate, true) == rate and PROGRESS.normalize_fps(float(rate), true) == rate, "Desktop accepts persisted numeric FPS: " + str(rate))
	check(PROGRESS.normalize_fps(240, false) == 120 and PROGRESS.normalize_fps(240.0, false) == 120, "Desktop 240 save safely migrates to 120 on mobile")
	for rate: int in [60, 120]:
		check(PROGRESS.normalize_fps(rate, false) == rate, "Mobile keeps existing rate: " + str(rate))
	for invalid: Variant in [null, true, false, "240", 0, -240, 241, 360, 120.5, [], {}]:
		check(PROGRESS.normalize_fps(invalid, true) == 60 and PROGRESS.normalize_fps(invalid, false) == 60, "Malformed FPS cannot create an unsupported render cap: " + str(invalid))
	check(p.available_fps() == PROGRESS.supported_fps_for(OS.has_feature("pc")), "Real device API uses the current export platform")
	fresh()
	p._loading = false
	p.data.settings.fps = 240
	p.settings_changed()
	var expected := 240 if OS.has_feature("pc") else 120
	check(p.data.settings.fps == expected and Engine.max_fps == expected, "Graphics choice reaches the actual engine render cap")
	p.data.settings.fps = 60
	p.load_game()
	check(p.data.settings.fps == expected and Engine.max_fps == expected, "Selected rate survives a real disk reload and is reapplied")

func _test_xp_and_world_gates() -> void:
	fresh()
	var first: Dictionary = p.finish_run({"world_id": "jungle", "height": 100.0, "passed": 4, "jumps": 1, "coins": 2, "run_id": "v26-first"})
	check(first.xp == 28 and first.new_achievements == ["first_jump"], "Short meaningful first run gains modest XP boost while the achievement remains 15 XP")
	check(first.reward_coins - first.level_bonus == 4, "XP change leaves the pickup/height/record coin policy unchanged")
	var repeat: Dictionary = p.finish_run({"height": 100.0, "passed": 5, "run_id": "v26-repeat"})
	check(repeat.xp == 8, "Repeat Easy run improves from 6 XP to 8 XP without one-time bonuses")
	var fractional: Dictionary = p.finish_run({"height": 30.0, "passed": 0, "run_id": "v26-fractional"})
	check(fractional.xp == 2, "A small run uses one final floor rather than losing XP to double rounding")
	var world_expected := {"jungle": 31, "canyon": 43, "ice": 57, "crystal": 71, "volcano": 89, "sky": 106}
	for id: String in world_expected:
		fresh(true, true)
		p.data.best_height = 1000000.0
		var result: Dictionary = p.finish_run({"world_id": id, "height": 400.0, "passed": 12, "jumps": 4, "coins": 2, "run_id": "v26-xp-" + id})
		check(result.xp == world_expected[id] and result.new_achievements.is_empty(), "Moderately faster repeat XP preserves difficulty ordering: " + id)
		check(result.reward_coins - result.level_bonus == 4, "Ordinary coin payout is unchanged in " + id)
	fresh(false, true)
	for index in range(4):
		var instant: Dictionary = p.finish_run({"height": 2.99, "coins": 10, "passed": 100, "run_id": "v26-instant-" + str(index)})
		check(instant.xp == 0 and instant.reward_coins == 0, "Quick restart pays neither boosted XP nor coins")
	var before: Dictionary = p.data.duplicate(true)
	var duplicate: Dictionary = p.finish_run({"height": 100000.0, "coins": 1000, "passed": 10000, "run_id": "v26-instant-0"})
	check(p.data == before and duplicate.xp == 0, "Reusing a settled run cannot gain boosted rewards")
	fresh(false, true)
	for index in range(4):
		p.finish_run({"world_id": "jungle", "height": 10000000.0, "passed": 100000, "run_id": "v26-easy-farm-" + str(index)})
	check(p.data.xp == p.xp_for_level(5) and p.get_level() == 5, "Endless Easy farming still stops exactly at the next-world level")
	check(p.is_world_unlocked("canyon") and not p.is_world_unlocked("ice") and not p.is_world_unlocked("sky"), "Faster Easy XP cannot unlock the hardest world")
	var spoofed: Dictionary = p.finish_run({"world_id": "sky", "height": 1000000, "run_id": "v26-spoof"})
	check(spoofed.world_id == "jungle" and spoofed.xp == 0, "Forged locked-world identity cannot bypass Easy's cap")
	fresh(false, true)
	p.data.xp = p.xp_for_level(5) - 1
	var last_point: Dictionary = p.finish_run({"height": 300.0, "run_id": "v26-last-point"})
	check(last_point.xp == 1 and p.data.xp == p.xp_for_level(5) and p.is_world_unlocked("canyon"), "One missing XP is attainable and the exact skill/level gate unlocks")
	for index in range(1, p.WORLDS.size() - 1):
		var world: Dictionary = p.WORLDS[index]
		var following: Dictionary = p.WORLDS[index + 1]
		check(p.select_world(world.id), "Earned next world can be entered: " + str(world.id))
		p._loading = true
		p.finish_run({"world_id": world.id, "height": 10000000.0, "passed": 100000, "run_id": "v26-chain-" + str(world.id)})
		check(p.data.xp == p.xp_for_level(int(following.unlock)) and p.is_world_unlocked(following.id), "Each world can earn precisely enough for its successor: " + str(world.id))
	check(p.select_world("sky"), "Complete skill chain reaches the hardest world")
	p._loading = true
	var previous_xp: int = p.data.xp
	var final_world: Dictionary = p.finish_run({"world_id": "sky", "height": 1000, "passed": 100, "run_id": "v26-sky-growth"})
	check(final_world.xp > 0 and p.data.xp > previous_xp, "Hardest world remains uncapped after its gate")
	fresh(false, true)
	p.data.xp = p.xp_for_level(50)
	var inherited_xp: int = p.data.xp
	p.finish_run({"world_id": "jungle", "height": 10000.0, "run_id": "v26-old-xp"})
	check(p.data.xp == inherited_xp, "New boost/caps never remove a legacy profile's existing XP")
