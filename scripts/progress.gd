extends Node
## Durable, versioned single-player progression. No statistics affect movement physics.

signal changed
signal achievement_unlocked(id: String)
signal level_gained(level: int)

const SAVE_VERSION: int = 3
const SKIN_PRICE: int = 100
const ANDROID_REFRESH = preload("res://scripts/android_refresh.gd")
const WORLDS: Array = [
	{"id": "jungle", "name": "Джунгли", "unlock": 1, "hazards": ["spikes", "rock", "insect", "saw", "mover", "falling"]},
	{"id": "canyon", "name": "Каменный каньон", "unlock": 5, "hazards": ["spikes", "rock", "saw", "mover", "falling"]},
	{"id": "ice", "name": "Ледяные скалы", "unlock": 12, "hazards": ["spikes", "rock", "insect", "mover", "falling"]},
	{"id": "crystal", "name": "Кристальные пещеры", "unlock": 20, "hazards": ["spikes", "insect", "saw", "mover"]},
	{"id": "volcano", "name": "Вулкан", "unlock": 30, "hazards": ["spikes", "rock", "saw", "mover", "falling"]},
	{"id": "sky", "name": "Небесные острова", "unlock": 50, "hazards": ["spikes", "insect", "saw", "mover", "falling"]}
]
const ACHIEVEMENTS: Array = [
	{"id": "first_jump", "name": "Первый прыжок", "title": "Первый прыжок", "description": "Перепрыгните на другую стену", "target": 1, "xp": 15},
	{"id": "height_1000", "name": "На высоте", "title": "1 000 метров", "description": "Поднимитесь на 1 000 м за один забег", "target": 1000, "xp": 100},
	{"id": "height_5000", "name": "Путь к звёздам", "title": "5 000 метров", "description": "Поднимитесь на 5 000 м за один забег", "target": 5000, "xp": 150},
	{"id": "coins_1000", "name": "Золотой запас", "title": "1 000 заработанных монет", "description": "Заработайте суммарно 1 000 монет, включая награды", "target": 1000, "xp": 80},
	{"id": "jumps_100", "name": "От стены к стене", "title": "100 успешных прыжков", "description": "Совершите 100 успешных прыжков", "target": 100, "xp": 60},
	{"id": "level_10", "name": "Опытный геккон", "title": "Достичь 10 уровня", "description": "Достигните 10 уровня", "target": 10, "xp": 100},
	{"id": "level_25", "name": "Ветеран высот", "title": "Достичь 25 уровня", "description": "Достигните 25 уровня", "target": 25, "xp": 100},
	{"id": "level_50", "name": "Покоритель небес", "title": "Достичь 50 уровня", "description": "Достигните 50 уровня", "target": 50, "xp": 150},
	{"id": "height_2000", "name": "За облаками", "title": "2 000 метров", "description": "Поднимитесь на 2 000 м за один забег", "target": 2000, "xp": 150, "unlock": 25},
	{"id": "jumps_1000", "name": "Мастер прыжков", "title": "1 000 успешных прыжков", "description": "Совершите 1 000 успешных прыжков", "target": 1000, "xp": 120, "unlock": 25}
]
const MILESTONES: Array = [
	{"level": 1, "name": "Мир «Джунгли»"}, {"level": 3, "name": "Звание «Скалолаз»"},
	{"level": 5, "name": "Мир «Каменный каньон»"}, {"level": 8, "name": "Сложные сочетания испытаний"},
	{"level": 12, "name": "Мир «Ледяные скалы»"}, {"level": 15, "name": "Звание «Покоритель высот»"},
	{"level": 20, "name": "Мир «Кристальные пещеры»"}, {"level": 25, "name": "Новые цели высоты"},
	{"level": 30, "name": "Мир «Вулкан»"}, {"level": 40, "name": "Звание «Легенда стен»"},
	{"level": 50, "name": "Мир «Небесные острова»"}, {"level": 75, "name": "Звание «Небесный дракон»"},
	{"level": 100, "name": "Звание «Бессмертный геккон»"}
]
const DAILY_DEFINITIONS: Array = [
	{"id": "jumps", "title": "Сделать 30 прыжков", "target": 30, "reward": 3},
	{"id": "coins", "title": "Собрать 20 монет в забегах", "target": 20, "reward": 5},
	{"id": "height", "title": "Достичь 300 м за один забег", "target": 300, "reward": 7}
]

# Overridable before entering the tree for isolated tests; ordinary games use user://.
var save_file: String = "user://progress_v3.json"
var data: Dictionary = {}
var _level_thresholds: Array[int] = [0]
var _loading: bool = false

func _init() -> void:
	data = _defaults()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_game()

func _defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION, "coins": 0, "xp": 0, "best_height": 0.0,
		"total_distance": 0.0, "runs": 0, "lifetime_coins": 0, "jumps": 0,
		"obstacles": 0, "achievements": [], "selected_world": "jungle",
		"settings": {"music": true, "sfx": true, "jump_sfx": true, "theme": "dark", "language": "ru", "fps": 60},
		"daily": {"date": _today(), "jumps": 0, "coins": 0, "height": 0.0, "claimed": []},
		"resume": {}, "processed_runs": [], "last_result": {},
		# Forward-compatible placeholders; there is no shop transaction in this version.
		"skin_id": "standard_green", "owned_skins": ["standard_green"],
		"profile_frame": "default", "sync_revision": 0
	}

func _today() -> String:
	return Time.get_date_string_from_system(false)

func _number(value: Variant, fallback: float, lower: float = 0.0, upper: float = 1.0e12) -> float:
	if not (value is int or value is float):
		return fallback
	var result: float = float(value)
	if not is_finite(result):
		return fallback
	return clampf(result, lower, upper)

func _known_achievement(id: String) -> bool:
	for item: Dictionary in ACHIEVEMENTS:
		if item["id"] == id:
			return true
	return false

func _world_exists(id: String) -> bool:
	for world: Dictionary in WORLDS:
		if world["id"] == id:
			return true
	return false

func _safe_json(value: Variant, depth: int = 0) -> Variant:
	if depth > 12:
		return null
	if value is Dictionary:
		var result: Dictionary = {}
		var count: int = 0
		for key: Variant in value:
			if not key is String or count >= 2048:
				continue
			result[key] = _safe_json(value[key], depth + 1)
			count += 1
		return result
	if value is Array:
		var result: Array = []
		for index: int in mini(value.size(), 4096):
			result.append(_safe_json(value[index], depth + 1))
		return result
	if value is float:
		return value if is_finite(value) else 0.0
	if value is int or value is bool or value is String or value == null:
		return value
	return null

func _sanitize(raw: Dictionary) -> Dictionary:
	var clean: Dictionary = _defaults()
	for key: String in ["coins", "xp", "runs", "lifetime_coins", "jumps", "obstacles", "sync_revision"]:
		clean[key] = int(_number(raw.get(key, clean[key]), float(clean[key])))
	for key: String in ["best_height", "total_distance"]:
		clean[key] = _number(raw.get(key, 0.0), 0.0)
	var achievements_value: Variant = raw.get("achievements", [])
	if achievements_value is Array:
		for value: Variant in achievements_value:
			if value is String and _known_achievement(value) and not value in clean["achievements"]:
				clean["achievements"].append(value)
	var selected: Variant = raw.get("selected_world", "jungle")
	if selected is String and _world_exists(selected):
		clean["selected_world"] = selected
	var settings: Variant = raw.get("settings", {})
	if settings is Dictionary:
		for key: String in ["music", "sfx", "jump_sfx"]:
			if settings.get(key) is bool:
				clean["settings"][key] = settings[key]
		for key: String in ["theme", "language"]:
			var allowed: Array = ["dark", "light"] if key == "theme" else ["ru", "en"]
			if settings.get(key) is String and settings[key] in allowed:
				clean["settings"][key] = settings[key]
		if (settings.get("fps") is int or settings.get("fps") is float) and float(settings["fps"]) in [60.0, 120.0]:
			clean["settings"]["fps"] = int(settings["fps"])
	var daily: Variant = raw.get("daily", {})
	if daily is Dictionary and daily.get("date") is String and daily["date"] == _today():
		for key: String in ["jumps", "coins", "height"]:
			clean["daily"][key] = _number(daily.get(key, 0), 0)
		var claimed: Variant = daily.get("claimed", [])
		if claimed is Array:
			for id: Variant in claimed:
				if id is String and id in ["jumps", "coins", "height"] and not id in clean["daily"]["claimed"]:
					clean["daily"]["claimed"].append(id)
	var resume: Variant = raw.get("resume", {})
	if resume is Dictionary:
		clean["resume"] = _safe_json(resume)
	var processed: Variant = raw.get("processed_runs", [])
	if processed is Array:
		for id: Variant in processed.slice(maxi(0, processed.size() - 24)):
			if id is String:
				clean["processed_runs"].append(id.substr(0, 128))
	var last_result: Variant = raw.get("last_result", {})
	if last_result is Dictionary:
		clean["last_result"] = _safe_json(last_result)
	return clean

func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4 * 1024 * 1024:
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	var raw: Dictionary = parser.data
	# A tiny unrelated object must not silently replace a valid backup.
	if not raw.has("version") or not raw.has("coins") or not raw.has("xp"):
		return {}
	var version: int = int(_number(raw.get("version"), -1.0, -1.0, 999.0))
	if version < 1 or version > SAVE_VERSION:
		return {}
	return _sanitize(raw)

func load_game() -> void:
	_loading = true
	var loaded: Dictionary = _read_valid(save_file)
	if loaded.is_empty():
		loaded = _read_valid(save_file + ".bak")
	data = loaded if not loaded.is_empty() else _defaults()
	_refresh_day(false)
	if not is_world_unlocked(str(data["selected_world"])):
		data["selected_world"] = "jungle"
	_loading = false
	settings_changed()
	changed.emit()

func save_game() -> void:
	if _loading:
		return
	data["version"] = SAVE_VERSION
	var temporary: String = save_file + ".tmp"
	var folder: String = ProjectSettings.globalize_path(save_file).get_base_dir()
	DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось открыть файл сохранения: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t", false, true))
	file.flush()
	file.close()
	# Keep a verified prior snapshot. Corrupt saves never overwrite a good backup.
	if not _read_valid(save_file).is_empty():
		var backup_error: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(save_file), ProjectSettings.globalize_path(save_file + ".bak"))
		if backup_error != OK:
			push_warning("Не удалось обновить резервное сохранение: %s" % backup_error)
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_file))
	if rename_error != OK:
		push_warning("Не удалось атомарно записать сохранение: %s" % rename_error)

func xp_required(level: int = -1) -> int:
	var effective: int = get_level() if level < 1 else level
	var n: float = float(effective - 1)
	return 80 + 35 * (effective - 1) + int(floor(8.0 * pow(n, 1.25)))

func get_level() -> int:
	var total: int = int(data.get("xp", 0))
	while _level_thresholds.back() <= total:
		var previous_level: int = _level_thresholds.size()
		_level_thresholds.append(_level_thresholds.back() + xp_required(previous_level))
	var low: int = 0
	var high: int = _level_thresholds.size() - 1
	while low < high:
		var middle: int = (low + high + 1) / 2
		if _level_thresholds[middle] <= total:
			low = middle
		else:
			high = middle - 1
	return low + 1

func xp_in_level() -> int:
	return int(data["xp"]) - _level_thresholds[get_level() - 1]

func level_title() -> String:
	var level: int = get_level()
	if level >= 100:
		return "Бессмертный геккон"
	if level >= 75:
		return "Небесный дракон"
	if level >= 40:
		return "Легенда стен"
	if level >= 15:
		return "Покоритель высот"
	if level >= 3:
		return "Скалолаз"
	return "Юный исследователь"

func current_world() -> Dictionary:
	for world: Dictionary in WORLDS:
		if world["id"] == data["selected_world"]:
			return world.duplicate(true)
	return WORLDS[0].duplicate(true)

func is_world_unlocked(id: String) -> bool:
	for world: Dictionary in WORLDS:
		if world["id"] == id:
			return get_level() >= int(world["unlock"])
	return false

func select_world(id: String) -> bool:
	if not is_world_unlocked(id):
		return false
	data["selected_world"] = id
	save_game()
	changed.emit()
	return true

func _achievement_complete(id: String) -> bool:
	for achievement: Dictionary in ACHIEVEMENTS:
		if achievement["id"] == id:
			return get_level() >= int(achievement.get("unlock", 1)) and achievement_progress(id) >= float(achievement["target"])
	return false

func achievement_progress(id: String) -> float:
	match id:
		"first_jump", "jumps_100", "jumps_1000": return float(data["jumps"])
		"height_1000", "height_2000", "height_5000": return float(data["best_height"])
		"coins_1000": return float(data["lifetime_coins"])
		"level_10", "level_25", "level_50": return float(get_level())
	return 0.0

func run_distances() -> Dictionary:
	# Derive menu counters from the existing save schema: older profiles retain
	# their record/total, while a profile with no previous result starts at zero.
	var last: Variant = data.get("last_result", {})
	return {
		"last": _number(last.get("height", 0.0), 0.0) if last is Dictionary else 0.0,
		"best": _number(data.get("best_height", 0.0), 0.0),
		"total": _number(data.get("total_distance", 0.0), 0.0)
	}

func finish_run(summary: Dictionary) -> Dictionary:
	var run_id: String = str(summary.get("run_id", "")).substr(0, 128)
	if not run_id.is_empty() and run_id in data["processed_runs"]:
		return data["last_result"].duplicate(true)
	_refresh_day(false)
	var height: float = _number(summary.get("height", 0), 0)
	var collected: int = int(_number(summary.get("coins", 0), 0))
	var jumps: int = int(_number(summary.get("jumps", 0), 0))
	var passed: int = int(_number(summary.get("passed", 0), 0))
	var previous_best: float = float(data["best_height"])
	var previous_xp: int = int(data["xp"])
	var old_level: int = get_level()
	var new_best: bool = height > previous_best
	var record_bonus: int = 2 if new_best and height - previous_best >= 100.0 else 0
	var reward: int = collected + int(floor(height / 150.0)) + record_bonus
	var base_xp: int = int(floor(height * 0.10)) + int(floor(float(passed) * 0.5))
	if new_best and height >= 100.0:
		base_xp += 8
	if height < 3.0:
		# An immediate restart never pays coins or repeatable XP.
		reward = 0
		base_xp = 0
	data["runs"] = int(data["runs"]) + 1
	data["total_distance"] = float(data["total_distance"]) + height
	data["best_height"] = maxf(previous_best, height)
	data["jumps"] = int(data["jumps"]) + jumps
	data["obstacles"] = int(data["obstacles"]) + passed
	data["coins"] = int(data["coins"]) + reward
	data["lifetime_coins"] = int(data["lifetime_coins"]) + reward
	data["xp"] = previous_xp + base_xp
	data["daily"]["jumps"] = int(data["daily"]["jumps"]) + jumps
	data["daily"]["coins"] = int(data["daily"]["coins"]) + collected
	data["daily"]["height"] = maxf(float(data["daily"]["height"]), height)
	var new_achievements: Array = []
	var rewarded_level: int = old_level
	var level_bonus: int = 0
	# Resolve every milestone and coin-reward chain, including levels 25 and 50.
	# Each achievement pays only once, so this loop always reaches a stable state.
	while true:
		var awarded: bool = false
		for achievement: Dictionary in ACHIEVEMENTS:
			var id: String = achievement["id"]
			if not id in data["achievements"] and _achievement_complete(id):
				data["achievements"].append(id)
				data["xp"] = int(data["xp"]) + int(achievement["xp"])
				new_achievements.append(id)
				awarded = true
		var level: int = get_level()
		if level > rewarded_level:
			var bonus: int = level - rewarded_level
			level_bonus += bonus
			data["coins"] = int(data["coins"]) + bonus
			data["lifetime_coins"] = int(data["lifetime_coins"]) + bonus
			rewarded_level = level
			awarded = true
		if not awarded:
			break
	var result: Dictionary = {
		"reward_coins": reward + level_bonus, "xp": int(data["xp"]) - previous_xp,
		"old_level": old_level, "level": get_level(), "new_best": new_best,
		"new_achievements": new_achievements, "level_bonus": level_bonus,
		"collected_coins": collected, "height_bonus": int(floor(height / 150.0)),
		"record_bonus": record_bonus, "height": height
	}
	if not run_id.is_empty():
		data["processed_runs"].append(run_id)
		if data["processed_runs"].size() > 24:
			data["processed_runs"].pop_front()
	data["resume"] = {}
	data["last_result"] = result.duplicate(true)
	save_game()
	for id: String in new_achievements:
		achievement_unlocked.emit(id)
	if int(result["level"]) > old_level:
		level_gained.emit(int(result["level"]))
	changed.emit()
	return result

func _refresh_day(persist: bool = true) -> void:
	if data.get("daily", {}).get("date", "") != _today():
		data["daily"] = {"date": _today(), "jumps": 0, "coins": 0, "height": 0.0, "claimed": []}
		if persist:
			save_game()

func daily_tasks() -> Array:
	_refresh_day()
	var tasks: Array = []
	for definition: Dictionary in DAILY_DEFINITIONS:
		var item: Dictionary = definition.duplicate(true)
		var id: String = item["id"]
		item["value"] = minf(float(data["daily"][id]), float(item["target"]))
		item["progress"] = item["value"]
		item["claimed"] = id in data["daily"]["claimed"]
		item["complete"] = float(data["daily"][id]) >= float(item["target"])
		tasks.append(item)
	return tasks

func claim_daily(id: String) -> bool:
	for task: Dictionary in daily_tasks():
		if task["id"] == id and task["complete"] and not task["claimed"]:
			data["daily"]["claimed"].append(id)
			data["coins"] = int(data["coins"]) + int(task["reward"])
			data["lifetime_coins"] = int(data["lifetime_coins"]) + int(task["reward"])
			save_game()
			changed.emit()
			return true
	return false

func save_resume(snapshot: Dictionary) -> void:
	data["resume"] = _safe_json(snapshot)
	save_game()

func load_resume() -> Dictionary:
	var snapshot: Variant = data.get("resume", {})
	return snapshot.duplicate(true) if snapshot is Dictionary else {}

func clear_resume() -> void:
	data["resume"] = {}
	save_game()

func settings_changed() -> void:
	data["settings"] = _sanitize({"settings": data.get("settings", {})})["settings"]
	Engine.max_fps = int(data["settings"]["fps"])
	ANDROID_REFRESH.request_rate(int(data["settings"]["fps"]))
	var locale: Node = get_node_or_null("/root/L10n") if is_inside_tree() else null
	if locale != null:
		locale.set_language(str(data["settings"]["language"]))
	var audio: Node = get_node_or_null("/root/Audio") if is_inside_tree() else null
	if audio != null:
		audio.set_music_enabled(bool(data["settings"]["music"]))
		audio.set_sfx_enabled(bool(data["settings"]["sfx"]))
		audio.set_jump_enabled(bool(data["settings"]["jump_sfx"]))
	if not _loading:
		save_game()
	changed.emit()
