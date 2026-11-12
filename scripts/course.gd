class_name RushCourse
extends Node2D
## Fast, narrow endless course. Gameplay data stays small and JSON-safe;
## drawing uses pixel textures cached once per world, not per-frame polygons.

const LEFT_X := 296.0
const RIGHT_X := 784.0
const WALL_LEFT := 270.0
const WALL_RIGHT := 810.0
const CELL_HEIGHT := 1120.0
const FIRST_CELL := 1050.0
const INTRO_CELL_HEIGHTS := [1060.0, 1100.0, 1080.0, 1040.0]
const INTRO_METRES := 200.0
const JUMP_DURATION := 0.24
const JUMP_ARC := 45.0
const LOOKAHEAD := 5000.0
const KEEP_BEHIND := 1900.0
const VALIDATION_RADIUS := 30.0
const SPIKE_REACH := 84.0
const MAX_SPEED := 2700.0
const TYPES := ["stone", "insect", "saw", "electric", "falling", "crystal", "pendulum", "vine"]
const WORLD_TYPES := {
	"jungle": ["stone", "insect", "saw", "electric", "falling", "pendulum", "vine"],
	"canyon": ["stone", "saw", "electric", "falling", "crystal", "pendulum"],
	"ice": ["stone", "insect", "electric", "falling", "crystal", "pendulum"],
	"crystal": ["insect", "saw", "electric", "crystal", "pendulum"],
	"volcano": ["stone", "saw", "electric", "falling", "crystal", "pendulum"],
	"sky": ["insect", "saw", "electric", "falling", "pendulum", "vine"],
}
const SAFE_SECTION_PADDING := 180.0

static var _texture_cache: Dictionary = {}
var hazards: Array = []
var coins: Array = []
var flies: Array = []
var witness: Array = []
var safe_sections: Array = []
var world_id := "jungle"
var challenge_level := 1
var rng := RandomNumberGenerator.new()
var seed_value := 1
var next_cell := FIRST_CELL
var route_side := 0
var generated_cells := 0
var animation_time := 0.0
var validated_cells := 0
var rejected_candidates := 0
var maintenance_runs := 0
var night_amount := 0.0
var danger_color := Color("ee785d")
var metal_color := Color("8da8ae")
var rock_color := Color("7c9196")
var accent_color := Color("a5e4a2")
var _cleanup_at := 0.0
var _draw_needed := true
var _art: Dictionary = {}
var _layout_deck: Array[int] = []
var _last_layout := -1
var _recent_types: Array[String] = []
var _side_streak := 0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_art()

func _process(_delta: float) -> void:
	if _draw_needed and visible:
		queue_redraw()
		_draw_needed = false

func setup(value: int, selected_world: String = "jungle") -> void:
	seed_value = value
	rng.seed = value
	world_id = selected_world if WORLD_TYPES.has(selected_world) else "jungle"
	hazards.clear()
	coins.clear()
	flies.clear()
	witness.clear()
	safe_sections.clear()
	_layout_deck.clear()
	_last_layout = -1
	_recent_types.clear()
	_side_streak = 0
	next_cell = FIRST_CELL
	route_side = 0
	generated_cells = 0
	validated_cells = 0
	rejected_candidates = 0
	maintenance_runs = 0
	_cleanup_at = 0.0
	animation_time = 0.0
	_set_palette()
	_ensure_art()
	ensure_ahead(0.0, 0.0)

func _set_palette() -> void:
	var palettes := {
		"jungle": ["ee785d", "8da8ae", "7c9196", "9fe089"],
		"canyon": ["f08352", "c09b7c", "b37e62", "f4cd83"],
		"ice": ["ef85a5", "a4cbe0", "8dbacf", "ddfaff"],
		"crystal": ["ef8cbf", "9699d4", "7a7aaf", "9cf4ed"],
		"volcano": ["ff9d51", "a18b96", "7b6e80", "ffd389"],
		"sky": ["ed9895", "bbcbd5", "92aeb8", "e7fff0"],
	}
	var colors: Array = palettes.get(world_id, palettes["jungle"])
	danger_color = Color(colors[0])
	metal_color = Color(colors[1])
	rock_color = Color(colors[2])
	accent_color = Color(colors[3])

static func speed_at(height_px: float) -> float:
	return RushTuning.speed_at(height_px)

func begin_safe_section(start_height: float, end_height: float) -> void:
	# Clear existing lookahead as well as suppressing future generation. The
	# margin hides nearby hazards before the side walls begin to fade out.
	var first := minf(start_height, end_height) - SAFE_SECTION_PADDING
	var last := maxf(start_height, end_height) + SAFE_SECTION_PADDING
	var merged: Array = []
	for section: Dictionary in safe_sections:
		if float(section["end"]) < first or float(section["start"]) > last:
			merged.append(section)
		else:
			first = minf(first, float(section["start"]))
			last = maxf(last, float(section["end"]))
	merged.append({"start": first, "end": last})
	merged.sort_custom(_safe_section_less)
	safe_sections = merged
	for i in range(hazards.size() - 1, -1, -1):
		var item: Dictionary = hazards[i]
		if _safe_span_intersects(float(item["h"]) - float(item["_ey"]), float(item["h"]) + float(item["_ey"])):
			hazards.remove_at(i)
	for items: Array in [coins, flies]:
		for i in range(items.size() - 1, -1, -1):
			if section_is_safe(float(items[i]["h"])):
				items.remove_at(i)
	_draw_needed = true

func _safe_section_less(a: Dictionary, b: Dictionary) -> bool:
	return float(a["start"]) < float(b["start"])

func section_is_safe(height_px: float) -> bool:
	return _safe_span_intersects(height_px, height_px)

func _safe_span_intersects(first: float, last: float) -> bool:
	for section: Dictionary in safe_sections:
		if first <= float(section["end"]) and last >= float(section["start"]):
			return true
	return false

func ensure_ahead(height_px: float, run_time: float) -> void:
	animation_time = run_time
	while next_cell < height_px + LOOKAHEAD:
		_generate_cell()
	# The hot path does no filtering, duplicate(), or polygon construction.
	# Streaming runs every 512 pixels, rather than at 120/240 physics Hz.
	if height_px >= _cleanup_at:
		var cutoff := height_px - KEEP_BEHIND
		for i in range(hazards.size() - 1, -1, -1):
			if float(hazards[i]["h"]) + float(hazards[i]["_ey"]) < cutoff:
				hazards.remove_at(i)
		for i in range(coins.size() - 1, -1, -1):
			if float(coins[i]["h"]) < cutoff or bool(coins[i].get("collected", false)):
				coins.remove_at(i)
		for i in range(flies.size() - 1, -1, -1):
			if float(flies[i]["h"]) < cutoff or bool(flies[i].get("eaten", false)):
				flies.remove_at(i)
		for i in range(witness.size() - 1, -1, -1):
			if float(witness[i]["cell_end"]) < cutoff:
				witness.remove_at(i)
		for i in range(safe_sections.size() - 1, -1, -1):
			if float(safe_sections[i]["end"]) < cutoff:
				safe_sections.remove_at(i)
		_cleanup_at = height_px + 512.0
		maintenance_runs += 1
	_draw_needed = true

func _generate_cell() -> void:
	var start := next_cell
	var intro := start < INTRO_METRES * RushTuning.PIXELS_PER_METRE
	var cell_height := float(INTRO_CELL_HEIGHTS[generated_cells % INTRO_CELL_HEIGHTS.size()]) if intro else CELL_HEIGHT
	var previous_side := route_side
	var breathing := not intro and generated_cells > 3 and generated_cells % 11 == 10
	var switch_side := generated_cells == 0 or _side_streak >= 2 or rng.randf() < 0.62
	if switch_side and not breathing:
		route_side = 1 - route_side
		_side_streak = 0
	else:
		_side_streak += 1
	var action := {
		"height_px": start + (40.0 if generated_cells == 0 else rng.randf_range(32.0, 84.0)),
		"from_side": previous_side, "to_side": route_side, "cell_start": start,
		"cell_end": start + cell_height, "breathing": breathing,
	}
	var candidates: Array = []
	var layout := 0 if generated_cells == 0 else _next_layout()
	action["layout"] = layout
	if not breathing:
		match layout:
			0: # One wall obstacle: no obligatory floating platform beside it.
				candidates.append(_wall_spikes(start, rng.randf_range(930.0, 1020.0), rng.randf_range(46.0, 70.0)))
			1: # A free-floating hazard, with both wall lanes unobstructed.
				candidates.append(_central_hazard(_choose_type(), start))
			2: # Two different heights, deliberately avoiding a spike/platform row.
				var floating := _central_hazard(_choose_type(), start)
				floating["h"] = start + 920.0
				candidates.append(floating)
				candidates.append(_wall_spikes(start, 1045.0, 32.0))
			3: # A stepped pair of short wall clusters.
				candidates.append(_wall_spikes(start, 885.0, 32.0))
				candidates.append(_wall_spikes(start, 1040.0, 32.0))
			4: # Small offset islands; their positions never make a cross-wall bar.
				for index in range(2):
					var island := _central_hazard(_choose_type(), start)
					island["x"] = rng.randf_range(420.0, 455.0) if index == 0 else rng.randf_range(625.0, 660.0)
					island["h"] = start + 900.0 + float(index) * 140.0
					island["r"] = 11.0 if String(island["kind"]) == "electric" else 25.0
					island["amplitude"] = 12.0
					island["fall_range"] = 30.0
					island["half_width"] = 24.0
					island["half_height"] = 20.0
					island["scale"] = 0.62
					candidates.append(island)
			5: # A bramble/crystal outcrop attached to the unsafe wall.
				var allowed: Array = WORLD_TYPES[world_id]
				var kind := "vine" if allowed.has("vine") else ("stone" if allowed.has("stone") else "crystal")
				var attached := _central_hazard(kind, start)
				attached["x"] = WALL_LEFT + 45.0 if route_side == 1 else WALL_RIGHT - 45.0
				attached["amplitude"] = 0.0
				attached["wall_attached"] = true
				attached["side"] = 1 - route_side
				candidates.append(attached)
			6: # A swinging weight or faceted island, independently of wall spikes.
				var allowed: Array = WORLD_TYPES[world_id]
				var kind := "pendulum" if allowed.has("pendulum") else _choose_type()
				candidates.append(_central_hazard(kind, start))
	for item: Dictionary in candidates:
		_cache_geometry(item)
		if intro:
			# Keep the complete motion envelope between the latest possible
			# 2700px/s jump and the next cell's radius-padded witness. Even
			# the shortest intro cell fits the largest falling-rock envelope.
			var extent := float(item["_ey"])
			var jump_limit := start + 84.0 + MAX_SPEED * JUMP_DURATION + JUMP_ARC + VALIDATION_RADIUS + 4.0
			item["h"] = clampf(float(item["h"]), jump_limit + extent, start + cell_height - VALIDATION_RADIUS - 4.0 - extent)
			_cache_geometry(item)
	for i in range(candidates.size() - 1, -1, -1):
		var item: Dictionary = candidates[i]
		if _safe_span_intersects(float(item["h"]) - float(item["_ey"]), float(item["h"]) + float(item["_ey"])):
			candidates.remove_at(i)
	if not _validate_cell(action, candidates):
		rejected_candidates += 1
		candidates.clear()
	validated_cells += 1
	hazards.append_array(candidates)
	witness.append(action)
	_spawn_items(action)
	generated_cells += 1
	next_cell += cell_height

func _next_layout() -> int:
	# A local Fisher-Yates deck uses this course's RNG, never the global RNG.
	# Every seven cells show all structures, with no repeated bag boundary.
	if _layout_deck.is_empty():
		_layout_deck.assign([0, 1, 2, 3, 4, 5, 6])
		for i in range(_layout_deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var temporary := _layout_deck[i]
			_layout_deck[i] = _layout_deck[j]
			_layout_deck[j] = temporary
		if _layout_deck.back() == _last_layout:
			var temporary := _layout_deck[0]
			_layout_deck[0] = _layout_deck[_layout_deck.size() - 1]
			_layout_deck[_layout_deck.size() - 1] = temporary
	_last_layout = _layout_deck.pop_back()
	return _last_layout

func _wall_spikes(start: float, offset: float, half_height: float) -> Dictionary:
	var item := {
		"kind": "spikes", "x": WALL_LEFT if route_side == 1 else WALL_RIGHT,
		"h": start + offset, "side": 1 - route_side, "half_h": half_height,
		"phase": rng.randf_range(0.0, TAU), "passed": false,
	}
	if challenge_level >= 8 and generated_cells > 10 and generated_cells % 5 == 2:
		item["kind"] = "timed"
	return item

func _choose_type() -> String:
	var allowed: Array = WORLD_TYPES[world_id]
	var choices: Array[String] = []
	for kind: String in allowed:
		if not _recent_types.has(kind):
			choices.append(kind)
	if choices.is_empty():
		for kind: String in allowed:
			choices.append(kind)
	var chosen := choices[rng.randi_range(0, choices.size() - 1)]
	_recent_types.append(chosen)
	if _recent_types.size() > 2:
		_recent_types.pop_front()
	return chosen

func _central_hazard(kind: String, start: float) -> Dictionary:
	var item := {
		"kind": kind, "x": rng.randf_range(430.0, 650.0),
		"h": start + rng.randf_range(920.0, 1000.0),
		"phase": rng.randf_range(0.0, TAU), "passed": false,
		"r": 42.0, "amplitude": 0.0, "frequency": 1.0,
	}
	match kind:
		"insect":
			item["r"] = 31.0
			item["amplitude"] = rng.randf_range(55.0, 85.0)
			item["frequency"] = rng.randf_range(1.4, 2.2)
		"saw":
			item["r"] = 46.0
			item["amplitude"] = rng.randf_range(22.0, 48.0)
			item["frequency"] = 1.7
		"electric":
			item["r"] = 10.0
			item["half_width"] = rng.randf_range(48.0, 72.0)
			item["amplitude"] = rng.randf_range(35.0, 65.0)
			item["frequency"] = rng.randf_range(1.0, 1.7)
		"falling":
			item["r"] = 39.0
			item["fall_range"] = 100.0
			item["frequency"] = rng.randf_range(160.0, 240.0)
		"crystal":
			item["r"] = 44.0
		"pendulum":
			item["r"] = 37.0
			item["amplitude"] = rng.randf_range(64.0, 92.0)
			item["frequency"] = rng.randf_range(1.0, 1.4)
		"vine":
			item["r"] = 22.0
			item["half_height"] = 64.0
	var horizontal_extent := float(item["r"]) + float(item["amplitude"]) + float(item.get("half_width", 0.0))
	item["x"] = clampf(float(item["x"]), LEFT_X + VALIDATION_RADIUS + horizontal_extent + 14.0, RIGHT_X - VALIDATION_RADIUS - horizontal_extent - 14.0)
	return item

func _spawn_items(action: Dictionary) -> void:
	var start := float(action["cell_start"])
	var cell_height := float(action["cell_end"]) - start
	if _safe_span_intersects(start, float(action["cell_end"])):
		return
	var safe_side := int(action["to_side"])
	var has_coin := false
	if generated_cells == 0:
		var h := start + 40.0 + speed_at(start) * JUMP_DURATION * 0.5 + JUMP_ARC
		coins.append({"x": 540.0, "h": h, "collected": false, "phase": rng.randf_range(0.0, TAU)})
		has_coin = true
	elif generated_cells % 4 == 3 and rng.randf() < 0.84:
		coins.append({"x": LEFT_X if safe_side == 0 else RIGHT_X, "h": start + 780.0, "collected": false, "phase": rng.randf_range(0.0, TAU)})
		has_coin = true
	if generated_cells % 3 == 1 and not has_coin:
		flies.append({"x": WALL_LEFT + 14.0 if safe_side == 0 else WALL_RIGHT - 14.0,
			"h": start + rng.randf_range(cell_height - 80.0, cell_height - 50.0), "side": safe_side,
			"phase": rng.randf_range(0.0, TAU), "eaten": false})

func _cache_geometry(item: Dictionary) -> void:
	var kind := String(item["kind"])
	var center := Vector2(float(item["x"]), -float(item["h"]))
	var ex: float
	var ey: float
	if kind == "spikes" or kind == "timed":
		ey = float(item["half_h"])
		var side := int(item["side"])
		var direction := 1.0 if side == 0 else -1.0
		var x := WALL_LEFT if side == 0 else WALL_RIGHT
		var top := center.y - ey
		var triangles: Array = []
		var teeth := maxi(2, roundi(ey * 2.0 / 35.0))
		var tooth_height := ey * 2.0 / float(teeth)
		for i in range(teeth):
			var y := top + float(i) * tooth_height
			triangles.append(PackedVector2Array([Vector2(x, y + 1.0), Vector2(x + direction * SPIKE_REACH, y + tooth_height * 0.5), Vector2(x, y + tooth_height - 1.0)]))
		item["_triangles"] = triangles
		item["_bounds"] = Rect2(Vector2(minf(x, x + direction * SPIKE_REACH), top), Vector2(SPIKE_REACH, ey * 2.0))
	else:
		ex = float(item.get("r", 42.0)) + float(item.get("amplitude", 0.0))
		ey = float(item.get("r", 42.0))
		if kind == "electric":
			ex += float(item["half_width"])
			ey += 14.0
		elif kind == "insect":
			ey += 16.0
		elif kind == "falling":
			ey += float(item["fall_range"]) * 0.5
		elif kind == "pendulum":
			ey += 18.0
		elif kind == "vine":
			ey += float(item.get("half_height", 64.0))
		item["_bounds"] = Rect2(center - Vector2(ex, ey), Vector2(ex * 2.0, ey * 2.0))
	item["_ey"] = ey
	item["_end_h"] = float(item["h"]) + ey

func _validate_cell(action: Dictionary, candidates: Array) -> bool:
	# A constructive certificate stronger than phase sampling: all possible
	# jump positions fit in an empty rectangle until MAX_SPEED*duration+arc.
	var start := float(action["cell_start"])
	var end := float(action["cell_end"])
	var jump_start := float(action["height_px"])
	var from_x := LEFT_X if int(action["from_side"]) == 0 else RIGHT_X
	var to_x := LEFT_X if int(action["to_side"]) == 0 else RIGHT_X
	var radius := VALIDATION_RADIUS
	if from_x != to_x:
		var jump_end := jump_start + MAX_SPEED * JUMP_DURATION + JUMP_ARC
		var flight := Rect2(Vector2(LEFT_X - radius, -jump_end - radius), Vector2(RIGHT_X - LEFT_X + radius * 2.0, jump_end - jump_start + radius * 2.0))
		if _rect_hits_envelopes(flight, candidates):
			return false
		var before := Rect2(Vector2(from_x - radius, -jump_start - radius), Vector2(radius * 2.0, jump_start - start + radius * 2.0))
		if _rect_hits_envelopes(before, candidates):
			return false
	var after := Rect2(Vector2(to_x - radius, -end - radius), Vector2(radius * 2.0, end - start + radius * 2.0))
	return not _rect_hits_envelopes(after, candidates)

func _rect_hits_envelopes(rect: Rect2, items: Array) -> bool:
	for item: Dictionary in items:
		if rect.intersects(item["_bounds"]):
			return true
	return false

func validate_witness() -> bool:
	for action: Dictionary in witness:
		if not _validate_cell(action, hazards):
			return false
	return true

func get_witness() -> Array:
	return witness.duplicate(true)

func _vertical_extent(item: Dictionary) -> float:
	return float(item.get("_ey", item.get("r", 42.0)))

func _hazard_center(item: Dictionary, time: float) -> Vector2:
	var center := Vector2(float(item["x"]), -float(item["h"]))
	var kind := String(item["kind"])
	var phase := float(item.get("phase", 0.0))
	var frequency := float(item.get("frequency", 1.0))
	if kind in ["insect", "saw", "electric", "pendulum"]:
		center.x += sin(time * frequency + phase) * float(item["amplitude"])
		if kind == "insect":
			center.y += sin(time * 2.7 + phase) * 16.0
		elif kind == "electric":
			center.y += sin(time * 2.1 + phase) * 14.0
		elif kind == "pendulum":
			center.y += cos(time * frequency + phase) * 18.0
	elif kind == "falling":
		# Smooth periodic fall/return rather than the old sawtooth teleport.
		center.y += sin(time * frequency / 70.0 + phase) * float(item["fall_range"]) * 0.5
	return center

func collision_at(point: Vector2, time: float, radius: float = 20.0) -> bool:
	return not collision_kind_at(point, time, radius).is_empty()

func collision_kind_at(point: Vector2, time: float, radius: float = 20.0) -> String:
	# Return the kind only after the actual triangle/circle/capsule hits.
	# The caller can choose its death effect without repeating shape checks.
	var height := -point.y
	if section_is_safe(height):
		return ""
	for item: Dictionary in hazards:
		if absf(height - float(item["h"])) > float(item["_ey"]) + radius:
			continue
		var kind := String(item["kind"])
		if kind == "timed" and not _timed_active(item, time):
			continue
		if kind == "spikes" or kind == "timed":
			for triangle: PackedVector2Array in item["_triangles"]:
				if _circle_polygon(point, radius, triangle):
					return kind
		else:
			var center := _hazard_center(item, time)
			var reach := radius + float(item["r"])
			if kind == "electric":
				var nearest := Vector2(clampf(point.x, center.x - float(item["half_width"]), center.x + float(item["half_width"])), center.y)
				if point.distance_squared_to(nearest) <= reach * reach:
					return kind
			elif kind == "vine":
				var nearest := Vector2(center.x, clampf(point.y, center.y - float(item.get("half_height", 64.0)), center.y + float(item.get("half_height", 64.0))))
				if point.distance_squared_to(nearest) <= reach * reach:
					return kind
			elif point.distance_squared_to(center) <= reach * reach:
				return kind
	return ""

func collect_at(point: Vector2, _time: float) -> int:
	var collected := 0
	for coin: Dictionary in coins:
		if bool(coin.get("collected", false)) or absf(-point.y - float(coin["h"])) > 48.0:
			continue
		if point.distance_squared_to(Vector2(float(coin["x"]), -float(coin["h"]))) <= 48.0 * 48.0:
			coin["collected"] = true
			collected += 1
	return collected

func take_fly(point: Vector2, side: int) -> Dictionary:
	var wanted := 0 if side < 0 else 1
	for fly: Dictionary in flies:
		if bool(fly.get("eaten", false)) or int(fly["side"]) != wanted:
			continue
		var ahead := float(fly["h"]) + point.y
		if ahead >= 70.0 and ahead <= clampf(speed_at(-point.y) * 0.09 + 150.0, 210.0, 390.0) and absf(point.x - float(fly["x"])) < 60.0:
			fly["eaten"] = true
			return {"position": Vector2(float(fly["x"]), -float(fly["h"]))}
	return {}

func count_passed(height_px: float) -> int:
	var passed := 0
	for item: Dictionary in hazards:
		if not bool(item.get("passed", false)) and height_px > float(item["_end_h"]) + 26.0:
			item["passed"] = true
			passed += 1
	return passed

func snapshot() -> Dictionary:
	var clean_hazards: Array = []
	for item: Dictionary in hazards:
		var clean := item.duplicate()
		for key: String in ["_triangles", "_bounds", "_ey", "_end_h"]:
			clean.erase(key)
		clean_hazards.append(clean)
	return {"version": 4, "seed": str(seed_value), "rng_state": str(rng.state),
		"world": world_id, "hazards": clean_hazards, "coins": coins.duplicate(true),
		"flies": flies.duplicate(true), "witness": witness.duplicate(true),
		"next_cell": next_cell, "route_side": route_side, "generated_cells": generated_cells,
		"animation_time": animation_time, "challenge_level": challenge_level,
		"validated_cells": validated_cells, "rejected_candidates": rejected_candidates,
		"cleanup_at": _cleanup_at, "maintenance_runs": maintenance_runs,
		"safe_sections": safe_sections.duplicate(true), "layout_deck": _layout_deck.duplicate(),
		"last_layout": _last_layout, "recent_types": _recent_types.duplicate(), "side_streak": _side_streak}

func restore(data: Dictionary) -> void:
	seed_value = int(data.get("seed", "1"))
	world_id = String(data.get("world", "jungle"))
	challenge_level = int(data.get("challenge_level", 1))
	if not int(data.get("version", 0)) in [2, 3, 4]:
		setup(seed_value, world_id)
		return
	rng.seed = seed_value
	rng.state = int(data.get("rng_state", str(rng.state)))
	hazards = Array(data.get("hazards", [])).duplicate(true)
	coins = Array(data.get("coins", [])).duplicate(true)
	flies = Array(data.get("flies", [])).duplicate(true)
	witness = Array(data.get("witness", [])).duplicate(true)
	safe_sections = Array(data.get("safe_sections", [])).duplicate(true)
	_layout_deck.assign(data.get("layout_deck", []))
	_last_layout = int(data.get("last_layout", -1))
	_recent_types.assign(data.get("recent_types", []))
	for i in range(_recent_types.size()):
		if _recent_types[i] == "bar":
			_recent_types[i] = "electric"
	_side_streak = int(data.get("side_streak", 0))
	for item: Dictionary in hazards:
		if String(item.get("kind", "")) == "bar":
			item["kind"] = "electric"
		_cache_geometry(item)
	next_cell = float(data.get("next_cell", FIRST_CELL))
	route_side = int(data.get("route_side", 0))
	generated_cells = int(data.get("generated_cells", 0))
	animation_time = float(data.get("animation_time", 0.0))
	validated_cells = int(data.get("validated_cells", 0))
	rejected_candidates = int(data.get("rejected_candidates", 0))
	_cleanup_at = float(data.get("cleanup_at", 0.0))
	maintenance_runs = int(data.get("maintenance_runs", 0))
	_set_palette()
	_ensure_art()
	_draw_needed = true

func _timed_active(item: Dictionary, time: float) -> bool:
	return fposmod(time + float(item["phase"]), 2.6) < 1.9

static func _circle_polygon(point: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(point, polygon):
		return true
	var squared := radius * radius
	for i in range(polygon.size()):
		var nearest := Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])
		if nearest.distance_squared_to(point) <= squared:
			return true
	return false

func _ensure_art() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not _texture_cache.has(world_id):
		_texture_cache[world_id] = {
			"stone": _rock_texture(), "falling": _rock_texture(), "saw": _saw_texture(),
			"insect0": _insect_texture(0), "insect1": _insect_texture(1),
			"electric0": _electric_texture(0), "electric1": _electric_texture(1),
			"electric2": _electric_texture(2), "electric3": _electric_texture(3),
			"spikes": _spike_texture(), "coin": _coin_texture(),
			"fly0": _fly_texture(0), "fly1": _fly_texture(1),
			"crystal": _crystal_texture(), "pendulum": _pendulum_texture(), "vine": _vine_texture(),
		}
	_art = _texture_cache[world_id]

func _draw() -> void:
	if _art.is_empty():
		return
	var tint := Color.WHITE.lerp(Color("b4ccff"), night_amount * 0.16)
	for item: Dictionary in hazards:
		var kind := String(item["kind"])
		var center := _hazard_center(item, animation_time)
		if kind == "spikes" or kind == "timed":
			var direction := 1.0 if int(item["side"]) == 0 else -1.0
			var color := tint
			if kind == "timed" and not _timed_active(item, animation_time):
				color.a = 0.25
			draw_set_transform(center, 0.0, Vector2(direction, 1.0))
			var half_height := float(item["half_h"])
			draw_texture_rect(_art["spikes"], Rect2(0.0, -half_height, 88.0, half_height * 2.0), false, color)
			if kind == "timed":
				draw_rect(Rect2(5, -89, 12, 12), Color("f4df87") if color.a > 0.5 else Color("8e6970"))
		else:
			var angle := animation_time * 6.0 + float(item["phase"]) if kind == "saw" else 0.0
			var radius := float(item["r"])
			draw_set_transform(center, angle)
			match kind:
				"stone", "falling":
					if kind == "falling":
						draw_rect(Rect2(-20, -68, 4, 17), Color(0.8, 0.86, 1.0, 0.25))
						draw_rect(Rect2(9, -80, 4, 23), Color(0.8, 0.86, 1.0, 0.18))
					var extent := 48.0 * radius / 42.0
					draw_texture_rect(_art[kind], Rect2(-extent, -extent, extent * 2.0, extent * 2.0), false, tint)
				"saw":
					var extent := 62.0 * radius / 46.0
					draw_texture_rect(_art[kind], Rect2(-extent, -extent, extent * 2.0, extent * 2.0), false, tint)
				"insect":
					var frame := int(animation_time * 22.0 + float(item["phase"])) % 2
					var size := Vector2(128, 96) * radius / 31.0
					draw_texture_rect(_art["insect%d" % frame], Rect2(-size * 0.5, size), false, tint)
				"electric":
					var half_width := float(item["half_width"])
					# Paint the exact lethal capsule, including its round electrodes.
					# Faint external sparks are decorative, never extra hit area.
					var casing := Color("1459b0")
					draw_line(Vector2(-half_width, 0.0), Vector2(half_width, 0.0), casing, radius * 2.0)
					draw_circle(Vector2(-half_width, 0.0), radius, casing)
					draw_circle(Vector2(half_width, 0.0), radius, casing)
					var frame := int(animation_time * 12.0 + float(item["phase"]) * 2.0) % 4
					var size := Vector2((half_width + radius) * 2.0, radius * 4.0)
					draw_texture_rect(_art["electric%d" % frame], Rect2(-size * 0.5, size), false, Color.WHITE)
				"crystal":
					var extent := 46.0 * radius / 44.0
					draw_texture_rect(_art[kind], Rect2(-extent, -extent, extent * 2.0, extent * 2.0), false, tint)
				"pendulum":
					var anchor := Vector2(float(item["x"]), -float(item["h"]) - 160.0) - center
					draw_line(anchor, Vector2.ZERO, metal_color.darkened(0.5), 6.0)
					draw_line(anchor + Vector2(1, 0), Vector2(1, 0), metal_color, 2.0)
					var extent := 39.0 * radius / 37.0
					draw_texture_rect(_art[kind], Rect2(-extent, -extent, extent * 2.0, extent * 2.0), false, tint)
				"vine":
					var extent := float(item.get("half_height", 64.0)) + float(item["r"])
					draw_texture_rect(_art[kind], Rect2(-radius, -extent, radius * 2.0, extent * 2.0), false, tint)
	for coin: Dictionary in coins:
		if not bool(coin.get("collected", false)):
			var center := Vector2(float(coin["x"]), -float(coin["h"]))
			var width := 0.24 + absf(cos(animation_time * 3.4 + float(coin["phase"]))) * 0.76
			draw_set_transform(center, 0.0, Vector2(width, 1.0))
			draw_texture_rect(_art["coin"], Rect2(-28, -28, 56, 56), false, Color.WHITE)
	for fly: Dictionary in flies:
		if not bool(fly.get("eaten", false)):
			var center := Vector2(float(fly["x"]) + sin(animation_time * 7.0 + float(fly["phase"])) * 2.0, -float(fly["h"]))
			draw_set_transform(center)
			var frame := int(animation_time * 30.0) % 2
			draw_texture_rect(_art["fly%d" % frame], Rect2(-16, -16, 32, 32), false, tint)
	draw_set_transform(Vector2.ZERO)

func _new_image(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image

func _crystal_texture() -> Texture2D:
	var image := _new_image(48, 48)
	var outline := Color("30364c")
	for y in range(48):
		for x in range(48):
			var dx := (float(x) - 23.5) / 22.0
			var dy := (float(y) - 23.5) / 23.0
			if absf(dx) * 0.72 + absf(dy) < 1.0:
				var color := accent_color.lerp(rock_color, 0.22)
				if x < 23: color = color.lightened(0.23)
				if x > 31: color = color.darkened(0.28)
				if absf(dx) * 0.72 + absf(dy) > 0.89: color = outline
				if absf(float(x) - (23.5 + dy * 5.0)) < 1.1: color = accent_color.lightened(0.5)
				image.set_pixel(x, y, color)
	_rect(image, Rect2i(14, 16, 2, 7), Color("e0f6df"))
	return ImageTexture.create_from_image(image)

func _pendulum_texture() -> Texture2D:
	var image := _new_image(40, 40)
	for y in range(40):
		for x in range(40):
			var d := Vector2(x - 19.5, y - 19.5)
			var radial := d.length()
			if radial < 19.0:
				var color := metal_color
				if radial > 16.5: color = Color("293744")
				elif d.x + d.y < -8.0: color = metal_color.lightened(0.32)
				elif d.x + d.y > 9.0: color = metal_color.darkened(0.38)
				if absf(d.x) < 3.0 or absf(d.y) < 3.0: color = rock_color.darkened(0.3)
				if radial < 7.0: color = danger_color
				if radial < 3.0: color = Color("ffe2a0")
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _vine_texture() -> Texture2D:
	var image := _new_image(24, 86)
	for y in range(86):
		var x := 10 + int(sin(float(y) * 0.14) * 2.0)
		_rect(image, Rect2i(x - 3, y, 7, 1), Color("253c38"))
		_rect(image, Rect2i(x - 1, y, 3, 1), accent_color.darkened(0.35))
		if y % 11 < 4:
			var reach := 2 + (3 - y % 11) * 2
			_rect(image, Rect2i(x - reach, y, reach, 2), danger_color.darkened(0.15))
			_rect(image, Rect2i(x + 2, y + 4, reach, 2), danger_color)
		if y % 17 == 0:
			_rect(image, Rect2i(x - 1, y, 2, 3), accent_color.lightened(0.2))
	return ImageTexture.create_from_image(image)

func _rect(image: Image, rect: Rect2i, color: Color) -> void:
	image.fill_rect(rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height())), color)

func _rock_texture() -> Texture2D:
	var image := _new_image(48, 48)
	var outline := Color("273448")
	for y in range(48):
		for x in range(48):
			var d := Vector2(float(x) - 23.5, float(y) - 23.5)
			var angle := atan2(d.y, d.x)
			var edge := 20.5 + sin(angle * 5.0) * 1.7 + cos(angle * 3.0) * 1.5
			var length := d.length()
			if length <= edge:
				var color := outline
				if length < edge - 2.0:
					var light := clampf((-d.x - d.y) / 58.0, -0.3, 0.3)
					color = rock_color.lightened(light) if light > 0.0 else rock_color.darkened(-light)
					if (x * 17 + y * 31) % 37 < 3:
						color = color.lightened(0.11)
				image.set_pixel(x, y, color)
	_rect(image, Rect2i(13, 10, 9, 2), rock_color.lightened(0.4))
	_rect(image, Rect2i(11, 13, 3, 6), rock_color.lightened(0.25))
	_rect(image, Rect2i(25, 24, 2, 9), rock_color.darkened(0.4))
	_rect(image, Rect2i(27, 31, 7, 2), rock_color.darkened(0.4))
	return ImageTexture.create_from_image(image)

func _saw_texture() -> Texture2D:
	var image := _new_image(64, 64)
	for y in range(64):
		for x in range(64):
			var d := Vector2(float(x) - 31.5, float(y) - 31.5)
			var angle := atan2(d.y, d.x)
			var radius := 29.0 if fposmod(angle / TAU * 12.0, 1.0) < 0.5 else 24.0
			var length := d.length()
			if length <= radius:
				var color := Color("283b4c")
				if length < radius - 2.0:
					color = metal_color.lightened(0.28 if d.y < -7.0 else 0.0)
				if length < 19.0:
					color = metal_color.darkened(0.28)
				if length < 15.0:
					color = metal_color.lightened(0.12)
				if length < 8.0:
					color = danger_color
				if length < 4.0:
					color = Color("283b4c")
				image.set_pixel(x, y, color)
	_rect(image, Rect2i(28, 25, 4, 2), Color("ffe9bf"))
	return ImageTexture.create_from_image(image)

func _spike_texture() -> Texture2D:
	var image := _new_image(44, 70)
	var outline := Color("513646")
	for y in range(70):
		var local := float(y % 17) / 16.0
		var width := int((1.0 - absf(local * 2.0 - 1.0)) * 41.0)
		for x in range(width + 1):
			var color := danger_color
			if x <= 1 or x >= width - 1 or local < 0.1 or local > 0.9:
				color = outline
			elif local < 0.48:
				color = danger_color.lightened(0.27)
			elif local > 0.7:
				color = danger_color.darkened(0.2)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _insect_texture(frame: int) -> Texture2D:
	var image := _new_image(64, 48)
	var dark := Color("293449")
	for side in [-1, 1]:
		var wing_y := 13 if frame == 0 else 20
		for y in range(wing_y - 7, wing_y + 8):
			for x in range(5, 28):
				var px := x if side < 0 else 63 - x
				var nx := (float(x) - 17.0) / 12.0
				var ny := (float(y) - float(wing_y)) / 8.0
				if nx * nx + ny * ny < 1.0:
					image.set_pixel(px, y, Color("b4d4d6") if x % 5 else Color("d7f3e4"))
	_rect(image, Rect2i(22, 11, 20, 28), dark)
	_rect(image, Rect2i(19, 18, 26, 16), dark)
	_rect(image, Rect2i(23, 13, 18, 23), danger_color.darkened(0.05))
	_rect(image, Rect2i(25, 15, 4, 16), danger_color.lightened(0.3))
	_rect(image, Rect2i(31, 14, 2, 22), dark)
	for p in [Vector2i(27, 22), Vector2i(36, 29)]:
		_rect(image, Rect2i(p, Vector2i(3, 3)), dark)
	_rect(image, Rect2i(24, 8, 16, 10), dark)
	_rect(image, Rect2i(26, 10, 5, 4), Color("fff2bc"))
	_rect(image, Rect2i(34, 10, 5, 4), Color("fff2bc"))
	_rect(image, Rect2i(29, 4, 2, 6), dark)
	_rect(image, Rect2i(36, 3, 2, 7), dark)
	for x in [17, 43]:
		_rect(image, Rect2i(x, 30, 5, 2), dark)
		_rect(image, Rect2i(x - 1, 35, 6, 2), dark)
	return ImageTexture.create_from_image(image)

func _electric_texture(frame: int) -> Texture2D:
	# Four tiny cached frames: no particle nodes or per-frame bolt geometry.
	# The middle 32px contain the solid core; transparent margins hold only
	# faint short arcs, rendered outside the physical capsule on purpose.
	var image := _new_image(128, 64)
	for y in range(32):
		for x in range(128):
			var axis_x := clampf(float(x), 15.5, 111.5)
			var distance := Vector2(float(x) - axis_x, float(y) - 15.5).length()
			if distance <= 15.5:
				var color := Color("164780") if distance > 13.5 else Color("237de1")
				if y < 9 and distance < 13.5:
					color = Color("54bdff")
				if x > 24 and x < 103 and absf(float(y) - 15.5) < 9.0:
					color = Color("103d7d")
				if (x < 24 or x > 103) and distance < 11.5:
					color = Color("7fe6ff") if y < 16 else Color("318fe9")
				if (x < 20 or x > 107) and absf(float(y) - 15.5) < 5.5:
					color = Color("dcfbff")
				image.set_pixel(x, y + 16, color)
	for x in range(22, 106):
		var segment := float(x - 22) / 7.0
		var first := sin(floorf(segment) * 5.0 + float(frame * 3))
		var second := sin((floorf(segment) + 1.0) * 5.0 + float(frame * 3))
		var bolt_y := 31 + int(lerpf(first, second, fposmod(segment, 1.0)) * 6.0)
		_rect(image, Rect2i(x, bolt_y - 2, 1, 5), Color("2bafff"))
		_rect(image, Rect2i(x, bolt_y, 1, 2), Color("e8fdff"))
		if x % 19 == frame * 3:
			_rect(image, Rect2i(x, bolt_y - 6, 2, 4), Color("87eaff"))
	for arc in range(3):
		var arc_x := 30 + arc * 29 + (frame * 5 + arc * 3) % 9
		var direction := -1 if (arc + frame) % 2 == 0 else 1
		var edge_y := 16 if direction < 0 else 47
		for step in range(12):
			var x := arc_x + int(sin(float(step) * 1.2 + float(frame)) * 2.0)
			var y := edge_y + direction * step
			_rect(image, Rect2i(x - 1, y, 3, 1), Color(0.2, 0.65, 1.0, 0.16))
			_rect(image, Rect2i(x, y, 1, 1), Color(0.55, 0.9, 1.0, 0.5))
	return ImageTexture.create_from_image(image)

func _coin_texture() -> Texture2D:
	var image := _new_image(32, 32)
	for y in range(32):
		for x in range(32):
			var distance := Vector2(float(x) - 15.5, float(y) - 15.5).length()
			if distance < 15.0:
				var color := Color("80512f")
				if distance < 13.5: color = Color("f2bc4c")
				if distance < 11.2: color = Color("bd7a30")
				if distance < 9.8: color = Color("f2bc4c")
				if y < 13 and distance > 11.2 and distance < 13.5: color = Color("ffe6a0")
				image.set_pixel(x, y, color)
	# A small raised gecko stamp: head/body, four toes and curling tail.
	var stamp := Color("9b642d")
	var shine := Color("ffe49a")
	_rect(image, Rect2i(13, 8, 6, 6), stamp)
	_rect(image, Rect2i(14, 13, 4, 9), stamp)
	_rect(image, Rect2i(11, 14, 3, 2), stamp)
	_rect(image, Rect2i(18, 14, 3, 2), stamp)
	_rect(image, Rect2i(11, 19, 3, 2), stamp)
	_rect(image, Rect2i(18, 19, 3, 2), stamp)
	for x in [10, 20]:
		_rect(image, Rect2i(x, 12, 2, 4), stamp)
		_rect(image, Rect2i(x, 19, 2, 4), stamp)
	_rect(image, Rect2i(15, 21, 2, 4), stamp)
	_rect(image, Rect2i(17, 24, 4, 2), stamp)
	_rect(image, Rect2i(20, 22, 2, 3), stamp)
	_rect(image, Rect2i(13, 8, 4, 1), shine)
	_rect(image, Rect2i(14, 13, 1, 7), shine)
	image.set_pixel(17, 10, Color("7b4b2c"))
	return ImageTexture.create_from_image(image)

func _fly_texture(frame: int) -> Texture2D:
	var image := _new_image(16, 16)
	var wings := Color("cee5e7")
	_rect(image, Rect2i(1, 4 if frame == 0 else 7, 5, 3), wings)
	_rect(image, Rect2i(10, 4 if frame == 0 else 7, 5, 3), wings)
	_rect(image, Rect2i(6, 4, 4, 8), Color("182a36"))
	_rect(image, Rect2i(5, 5, 6, 4), Color("182a36"))
	_rect(image, Rect2i(6, 4, 2, 2), Color("efad74"))
	_rect(image, Rect2i(6, 13, 1, 2), Color("182a36"))
	_rect(image, Rect2i(10, 12, 1, 2), Color("182a36"))
	return ImageTexture.create_from_image(image)
