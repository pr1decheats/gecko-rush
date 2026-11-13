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
const ICICLE_RADIUS := 21.0
const ICICLE_HALF_LENGTH := 34.0
const STREAM_AHEAD_SECONDS := 3.0
const KEEP_BEHIND_SECONDS := 0.8
const PHYSICS_STEP := 1.0 / 120.0
# A biome owns its silhouettes, movement vocabulary and structure weights.
# These are deliberately disjoint; legacy generic kinds are restore-only.
const WORLD_TYPES := {
	"jungle": ["root", "beetle", "vine", "thorns"],
	"canyon": ["boulder", "rockfall", "canyon_weight", "sand_spur"],
	"ice": ["icicle", "ice_chunk", "frost", "ice_teeth"],
	"crystal": ["prism", "crystal_beam", "shard", "crystal_teeth"],
	"volcano": ["lava_orb", "fire_jet", "obsidian", "magma_teeth"],
	"sky": ["lightning", "storm_orb", "wind_blade", "storm_spikes"],
}
const WORLD_LAYOUTS := {
	"jungle": [0, 0, 1, 3, 5, 5, 6], # Brambles, hanging vines, beetle patrols.
	"canyon": [0, 2, 2, 3, 5, 6, 6, 7], # Rockfall columns and swinging weights.
	"ice": [0, 1, 4, 7, 7, 8, 8], # Staggered icicles and frost cross-currents.
	"crystal": [1, 4, 4, 8, 8, 9, 9], # Split prisms and refracted beam relays.
	"volcano": [0, 1, 2, 5, 7, 9, 9, 9], # Vertical vents, lava pulses, obsidian.
	"sky": [1, 4, 6, 8, 9, 9, 10], # Charged orbs, lightning and diagonal gusts.
}
const WORLD_WALL_KIND := {"jungle": "thorns", "canyon": "sand_spur", "ice": "ice_teeth", "crystal": "crystal_teeth", "volcano": "magma_teeth", "sky": "storm_spikes"}
const WORLD_ATTACHED_KIND := {"jungle": "root", "canyon": "boulder", "ice": "icicle", "crystal": "prism", "volcano": "fire_jet", "sky": "lightning"}
const WORLD_SIGNATURE_KIND := {"jungle": "vine", "canyon": "canyon_weight", "ice": "icicle", "crystal": "crystal_beam", "volcano": "fire_jet", "sky": "wind_blade"}
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
var _profile: Dictionary = {}

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
	_profile = RushTuning.profile_for(world_id)
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

static func speed_at(height_px: float, selected_world: String = "jungle") -> float:
	return RushTuning.speed_at(height_px, selected_world)

func _world_speed_at(height_px: float) -> float:
	return RushTuning.speed_at(height_px, world_id)

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
	# Safe events may remove an already-certified gate. Keep diagnostic
	# witness metadata honest; pressure tests use real shapes independently.
	for action: Dictionary in witness:
		if not bool(action.get("forced", false)):
			continue
		var gate_exists := false
		for item: Dictionary in hazards:
			if bool(item.get("gate", false)) and float(item["h"]) == float(action.get("gate_h", -INF)):
				gate_exists = true
				break
		action["forced"] = gate_exists
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

func stream_ahead_at(height_px: float) -> float:
	# Seconds of visible route, not a fixed pixel budget that disappears at
	# high pace. Cell spacing grows with the same local speed, bounding count.
	return maxf(LOOKAHEAD, RushTuning.max_speed_at(height_px, world_id) * STREAM_AHEAD_SECONDS)

func gate_interval_at(height_px: float) -> float:
	var metres := maxf(height_px, 0.0) / RushTuning.PIXELS_PER_METRE
	var progress := 1.0 - exp(-metres / 1200.0)
	return lerpf(0.85, 0.43, progress) * float(_profile["spacing_scale"])

func ensure_ahead(height_px: float, run_time: float) -> void:
	animation_time = run_time
	var local_speed := RushTuning.max_speed_at(height_px, world_id)
	var cutoff := height_px - maxf(KEEP_BEHIND, local_speed * KEEP_BEHIND_SECONDS)
	if height_px >= _cleanup_at:
		_prune_behind(cutoff)
		_cleanup_at = height_px + maxf(512.0, local_speed * 0.2)
	var streamed := 0
	while next_cell < height_px + stream_ahead_at(height_px):
		_generate_cell()
		streamed += 1
		# A restored/test run may advance a long distance in one call. Consume
		# the same deterministic RNG sequence without retaining old terrain.
		if streamed % 16 == 0:
			_prune_behind(cutoff)
	if streamed > 0:
		_prune_behind(cutoff)
	_draw_needed = true

func _prune_behind(cutoff: float) -> void:
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
	maintenance_runs += 1

func _generate_cell() -> void:
	var start := next_cell
	var intro := start < INTRO_METRES * RushTuning.PIXELS_PER_METRE
	var cell_height := _travel_ceiling(start, gate_interval_at(start)) - start
	cell_height = snappedf(cell_height, 1.0 / 1024.0)
	var previous_side := route_side
	var breathing := not intro and generated_cells > 3 and generated_cells % 11 == 10
	# Every active cell switches because its departed wall is physically
	# blocked. There are no central-only cells a player can camp through.
	if not breathing:
		route_side = 1 - route_side
	_side_streak = 0
	var lead := RushTuning.min_speed_at(start, world_id) * rng.randf_range(0.025, 0.05)
	var action := {
		"height_px": start + (40.0 if generated_cells == 0 else maxf(32.0, lead)),
		"from_side": previous_side, "to_side": route_side, "cell_start": start,
		"cell_end": start + cell_height, "breathing": breathing,
		"forced": not breathing,
	}
	var candidates: Array = []
	var layout := 0 if generated_cells == 0 else _next_layout()
	if generated_cells == 0:
		_last_layout = layout
	action["layout"] = layout
	if not breathing:
		match layout:
			0: # One themed wall outcrop, with a broad opposite lane.
				candidates.append(_wall_spikes(start, cell_height * 0.83, rng.randf_range(40.0, 64.0)))
			1: # A biome's free-moving patrol, rock or shard.
				candidates.append(_central_hazard(_choose_type(), start))
			2: # A rockfall/lava island followed by a separate wall outcrop.
				candidates.append(_central_hazard("rockfall" if world_id == "canyon" else "lava_orb", start))
				candidates.append(_wall_spikes(start, cell_height * 0.93, 30.0))
			3: # Two short bramble / stone clusters on the unsafe wall.
				candidates.append(_wall_spikes(start, cell_height * 0.77, 28.0))
				candidates.append(_wall_spikes(start, cell_height * 0.93, 28.0))
			4: # Offset islands; never a bar across both wall lanes.
				for index in range(2):
					var island := _central_hazard(_choose_type(), start)
					_scale_hazard(island, 0.68)
					island["x"] = 430.0 if index == 0 else 650.0
					candidates.append(island)
			5: # Roots / vents emerge from the wall the witness has left.
				var attached := _central_hazard(String(WORLD_ATTACHED_KIND[world_id]), start)
				attached["x"] = WALL_LEFT + 36.0 if route_side == 1 else WALL_RIGHT - 36.0
				attached["motion_x"] = 0.0
				attached["wall_attached"] = true
				attached["side"] = 1 - route_side
				candidates.append(attached)
			6: # A suspended jungle vine / canyon weight / storm gust.
				candidates.append(_central_hazard(String(WORLD_SIGNATURE_KIND[world_id]), start))
			7: # Falling columns have separate x lanes and opposing phases.
				var kind := "rockfall" if world_id == "canyon" else ("icicle" if world_id == "ice" else "fire_jet")
				for index in range(2):
					var column := _central_hazard(kind, start)
					_scale_hazard(column, 0.76)
					column["x"] = 445.0 if index == 0 else 635.0
					column["phase"] = float(index) * PI
					candidates.append(column)
			8: # A diagonal shard / frost / gust relay, not wall spikes.
				var kind := "frost" if world_id == "ice" else ("shard" if world_id == "crystal" else "wind_blade")
				for index in range(2):
					var relay := _central_hazard(kind, start)
					_scale_hazard(relay, 0.64)
					relay["x"] = 425.0 if index == 0 else 655.0
					relay["angle"] = -0.35 if index == 0 else 0.35
					candidates.append(relay)
			9: # One readable, pulsing beam / vent / lightning strike.
				var kind := "crystal_beam" if world_id == "crystal" else ("fire_jet" if world_id == "volcano" else "lightning")
				candidates.append(_central_hazard(kind, start))
			10: # The sky's charged orb and a small crosswind at different x.
				var orb := _central_hazard("storm_orb", start)
				_scale_hazard(orb, 0.72)
				orb["x"] = 430.0
				candidates.append(orb)
				var gust := _central_hazard("wind_blade", start)
				_scale_hazard(gust, 0.62)
				gust["x"] = 650.0
				candidates.append(gust)
	if not breathing:
		var primary_gate: Dictionary = {}
		for item: Dictionary in candidates:
			if String(item.get("shape", "")) == "spikes":
				primary_gate = item
				break
		if primary_gate.is_empty():
			primary_gate = _wall_spikes(start, 0.0, 40.0)
			candidates.append(primary_gate)
		# At any pace the physical/visible gate spans several 120Hz samples.
		# Swept collision additionally catches even arbitrarily thin shapes.
		primary_gate["half_h"] = maxf(float(primary_gate["half_h"]), RushTuning.max_speed_at(start, world_id) * PHYSICS_STEP * 0.8 + 32.0)
		primary_gate["gate"] = true
		# The first threat is always the readable wall gate. Biome patrols
		# follow it, so reacting to the gate does not jump into an earlier
		# floating obstacle whose wall lane happened to look clear.
		candidates.erase(primary_gate)
		candidates.push_front(primary_gate)
	# Full motion envelopes sit after a complete selected-world jump and
	# before the next possible jump. This certificate includes every night
	# phase, not just the phase at which the cell happened to stream in.
	var jump_limit := _jump_ceiling(float(action["height_px"])) + VALIDATION_RADIUS + 8.0
	for index in range(candidates.size()):
		var item: Dictionary = candidates[index]
		_cache_geometry(item)
		var extent := float(item["_ey"])
		var low := jump_limit + extent
		var high := start + cell_height - VALIDATION_RADIUS - 8.0 - extent
		if high < low:
			# Profiles can be tuned independently without creating a forced trap.
			cell_height = ceilf((cell_height + low - high) * 1024.0) / 1024.0
			action["cell_end"] = start + cell_height
			high = low
		var fraction := float(index + 1) / float(candidates.size() + 1)
		item["h"] = lerpf(low, high, fraction)
		_cache_geometry(item)
	for i in range(candidates.size() - 1, -1, -1):
		var item: Dictionary = candidates[i]
		if _safe_span_intersects(float(item["h"]) - float(item["_ey"]), float(item["h"]) + float(item["_ey"])):
			candidates.remove_at(i)
	action["forced"] = false
	for item: Dictionary in candidates:
		if bool(item.get("gate", false)):
			action["forced"] = true
			action["gate_h"] = float(item["h"])
			action["gate_side"] = int(item["side"])
	if not _validate_cell(action, candidates):
		rejected_candidates += 1
		candidates.clear()
		action["forced"] = false
	validated_cells += 1
	hazards.append_array(candidates)
	witness.append(action)
	_spawn_items(action)
	generated_cells += 1
	next_cell += cell_height

func _next_layout() -> int:
	# Weighted biome bags keep characteristic structures frequent. Removing
	# a different card at a duplicate boundary also handles duplicate weights.
	if _layout_deck.is_empty():
		_layout_deck.assign(WORLD_LAYOUTS[world_id])
		for i in range(_layout_deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var temporary := _layout_deck[i]
			_layout_deck[i] = _layout_deck[j]
			_layout_deck[j] = temporary
	var index := _layout_deck.size() - 1
	while index >= 0 and _layout_deck[index] == _last_layout:
		index -= 1
	if index < 0:
		# A bag containing only the previous weighted card is carried forward.
		var alternatives: Array = WORLD_LAYOUTS[world_id].duplicate()
		alternatives.erase(_last_layout)
		for i in range(alternatives.size() - 1, -1, -1):
			if int(alternatives[i]) == _last_layout:
				alternatives.remove_at(i)
		_last_layout = int(alternatives[rng.randi_range(0, alternatives.size() - 1)])
		return _last_layout
	_last_layout = _layout_deck[index]
	_layout_deck.remove_at(index)
	return _last_layout

func _wall_spikes(start: float, offset: float, half_height: float) -> Dictionary:
	# Profile XP / challenge_level never changes obstacle physics.
	return {"kind": String(WORLD_WALL_KIND[world_id]), "shape": "spikes",
		"x": WALL_LEFT if route_side == 1 else WALL_RIGHT,
		"h": start + offset, "side": 1 - route_side, "half_h": maxf(half_height, RushTuning.max_speed_at(start, world_id) * PHYSICS_STEP * 0.8 + 24.0),
		"phase": rng.randf_range(0.0, TAU), "passed": false}

func _choose_type() -> String:
	var allowed: Array = WORLD_TYPES[world_id]
	var choices: Array[String] = []
	for kind: String in allowed:
		if kind != String(WORLD_WALL_KIND[world_id]) and not _recent_types.has(kind):
			choices.append(kind)
	if choices.is_empty():
		for kind: String in allowed:
			if kind != String(WORLD_WALL_KIND[world_id]):
				choices.append(kind)
	var chosen := choices[rng.randi_range(0, choices.size() - 1)]
	_recent_types.append(chosen)
	if _recent_types.size() > 2:
		_recent_types.pop_front()
	return chosen

func _central_hazard(kind: String, start: float) -> Dictionary:
	var item := {
		"kind": kind, "shape": "circle", "x": rng.randf_range(435.0, 645.0),
		"h": start + rng.randf_range(900.0, 1000.0),
		"phase": rng.randf_range(0.0, TAU), "passed": false,
		"r": 36.0, "amplitude": 0.0, "frequency": 1.0,
		"motion_x": 0.0, "motion_y": 0.0, "half_length": 0.0,
		"angle": 0.0, "angle_sway": 0.0,
	}
	match kind:
		"root":
			item["r"] = 40.0
		"beetle", "insect":
			item["r"] = 29.0
			item["motion_x"] = 56.0
			item["motion_y"] = 12.0
			item["frequency"] = 1.9
		"vine":
			item["shape"] = "capsule"
			item["r"] = 13.0
			item["half_length"] = 40.0
			item["angle"] = PI * 0.5
			item["angle_sway"] = 0.24
			item["motion_x"] = 32.0
			item["frequency"] = 0.9
		"boulder", "stone":
			item["r"] = 41.0
			item["motion_x"] = 22.0
			item["frequency"] = 0.8
		"rockfall", "falling":
			item["r"] = 36.0
			item["motion_y"] = 42.0
			item["frequency"] = 2.0
		"canyon_weight", "pendulum":
			item["r"] = 34.0
			item["motion_x"] = 70.0
			item["motion_y"] = 13.0
			item["frequency"] = 1.2
		"icicle":
			item["shape"] = "capsule"
			item["r"] = ICICLE_RADIUS
			item["half_length"] = ICICLE_HALF_LENGTH
			item["angle"] = PI * 0.5
			item["motion_y"] = 32.0
			item["frequency"] = 2.5
		"ice_chunk":
			item["r"] = 38.0
			item["motion_x"] = 13.0
			item["motion_y"] = 7.0
			item["frequency"] = 0.65
		"frost":
			item["shape"] = "capsule"
			item["r"] = 13.0
			item["half_length"] = 38.0
			item["motion_x"] = 54.0
			item["motion_y"] = 9.0
			item["frequency"] = 1.45
		"prism", "crystal":
			item["r"] = 38.0
			item["motion_y"] = 9.0
			item["frequency"] = 0.85
		"crystal_beam":
			item["shape"] = "capsule"
			item["r"] = 10.0
			item["half_length"] = 62.0
			item["angle_sway"] = 0.25
			item["frequency"] = 1.1
			item["pulse_period"] = 3.1
			item["pulse_on"] = 2.3
		"shard":
			item["r"] = 26.0
			item["motion_x"] = 42.0
			item["motion_y"] = 22.0
			item["frequency"] = 1.8
		"lava_orb":
			item["r"] = 33.0
			item["motion_x"] = 23.0
			item["motion_y"] = 27.0
			item["frequency"] = 1.3
		"fire_jet":
			item["shape"] = "capsule"
			item["r"] = 13.0
			item["half_length"] = 42.0
			item["angle"] = PI * 0.5
			item["motion_y"] = 12.0
			item["frequency"] = 1.6
			item["pulse_period"] = 2.5
			item["pulse_on"] = 1.7
		"obsidian", "saw":
			item["r"] = 40.0
			item["motion_x"] = 31.0
			item["frequency"] = 1.7
		"lightning", "electric":
			item["shape"] = "capsule"
			item["r"] = 10.0
			item["half_length"] = 60.0
			item["half_width"] = 60.0 # Retained for older electrical fixtures.
			item["motion_x"] = 44.0
			item["motion_y"] = 8.0
			item["frequency"] = 1.7
			if kind == "lightning":
				item["pulse_period"] = 2.2
				item["pulse_on"] = 1.65
		"storm_orb":
			item["r"] = 30.0
			item["motion_x"] = 54.0
			item["motion_y"] = 22.0
			item["frequency"] = 1.6
		"wind_blade":
			item["shape"] = "capsule"
			item["r"] = 12.0
			item["half_length"] = 42.0
			item["angle_sway"] = 0.3
			item["motion_x"] = 48.0
			item["motion_y"] = 18.0
			item["frequency"] = 2.2
	if kind in ["root", "boulder", "rockfall", "canyon_weight", "ice_chunk", "prism", "shard", "obsidian", "icicle", "vine", "frost", "fire_jet", "wind_blade", "crystal_beam"]:
		item["shape"] = "polygon"
	var motion := float(_profile.get("motion_scale", 1.0))
	item["motion_x"] = float(item["motion_x"]) * motion
	item["motion_y"] = float(item["motion_y"]) * motion
	item["frequency"] = float(item["frequency"]) * motion
	item["angle_sway"] = float(item["angle_sway"]) * motion
	item["spin"] = 1.4 if kind == "boulder" else (2.3 if kind in ["obsidian", "saw", "ice_chunk"] else 0.0)
	item["suspended"] = kind in ["canyon_weight", "pendulum", "vine"]
	# Legacy callers modify amplitude directly; the same field remains live.
	item["amplitude"] = item["motion_x"]
	_clamp_hazard_x(item)
	return item

func _scale_hazard(item: Dictionary, amount: float) -> void:
	for key: String in ["r", "half_length", "half_width", "motion_x", "motion_y", "amplitude"]:
		if item.has(key):
			item[key] = float(item[key]) * amount

func _clamp_hazard_x(item: Dictionary) -> void:
	var extent := float(item["r"]) + float(item.get("half_length", 0.0)) + float(item.get("motion_x", 0.0))
	item["x"] = clampf(float(item["x"]), LEFT_X + VALIDATION_RADIUS + extent + 12.0, RIGHT_X - VALIDATION_RADIUS - extent - 12.0)

func _travel_ceiling(height_px: float, seconds: float, extra_height: float = 0.0) -> float:
	# A constant-at-the-end speed bounds the whole monotone day trajectory.
	# Solve its local quadratic exactly; there is no global certification cap.
	# Splitting a long interval also handles very steep future curve sections.
	var origin := height_px + extra_height
	var kilometre_px := RushTuning.PIXELS_PER_METRE * 1000.0
	var quadratic := float(_profile["endless_quadratic"]) / (kilometre_px * kilometre_px)
	var slope := (float(_profile["growth_per_km"]) + 2.0 * float(_profile["endless_quadratic"]) * maxf(origin, 0.0) / kilometre_px) / kilometre_px
	var a := seconds * quadratic
	var b := 1.0 - seconds * slope
	var c := seconds * RushTuning.max_speed_at(origin, world_id)
	var discriminant := b * b - 4.0 * a * c
	if discriminant <= 0.0 or b <= 0.0:
		var middle := _travel_ceiling(origin, seconds * 0.5)
		return _travel_ceiling(middle, seconds * 0.5)
	var travel := 2.0 * c / (b + sqrt(discriminant))
	return origin + travel + 0.001

func _jump_ceiling(jump_start: float) -> float:
	# Main advances one complete final physics frame even when it clamps the
	# last jump fraction; include that frame and the maximum upward arc.
	return _travel_ceiling(jump_start, JUMP_DURATION + PHYSICS_STEP, JUMP_ARC)

func _spawn_items(action: Dictionary) -> void:
	var start := float(action["cell_start"])
	var cell_height := float(action["cell_end"]) - start
	if _safe_span_intersects(start, float(action["cell_end"])):
		return
	var safe_side := int(action["to_side"])
	var has_coin := false
	if generated_cells == 0:
		var h := start + 40.0 + _world_speed_at(start) * JUMP_DURATION * 0.5 + JUMP_ARC
		coins.append({"x": 540.0, "h": h, "collected": false, "phase": rng.randf_range(0.0, TAU)})
		has_coin = true
	elif generated_cells % 4 == 3 and rng.randf() < 0.84:
		coins.append({"x": LEFT_X if safe_side == 0 else RIGHT_X, "h": lerpf(_jump_ceiling(float(action["height_px"])) + VALIDATION_RADIUS, float(action["cell_end"]) - VALIDATION_RADIUS, 0.62), "collected": false, "phase": rng.randf_range(0.0, TAU)})
		has_coin = true
	if generated_cells % 3 == 1 and not has_coin:
		flies.append({"x": WALL_LEFT + 14.0 if safe_side == 0 else WALL_RIGHT - 14.0,
			"h": start + rng.randf_range(cell_height - 80.0, cell_height - 50.0), "side": safe_side,
			"phase": rng.randf_range(0.0, TAU), "eaten": false})

func _cache_geometry(item: Dictionary) -> void:
	var kind := String(item["kind"])
	var shape := String(item.get("shape", "circle"))
	if kind in ["spikes", "timed"]:
		shape = "spikes"
	elif kind == "electric":
		shape = "capsule"
		item["half_length"] = float(item.get("half_width", 60.0))
	elif kind == "vine" and not item.has("shape"):
		shape = "capsule"
		item["half_length"] = float(item.get("half_height", 64.0))
		item["angle"] = PI * 0.5
	item["shape"] = shape
	var center := Vector2(float(item["x"]), -float(item["h"]))
	var ex: float
	var ey: float
	if shape == "spikes":
		ey = float(item["half_h"])
		var side := int(item["side"])
		var direction := 1.0 if side == 0 else -1.0
		var x := WALL_LEFT if side == 0 else WALL_RIGHT
		var top := center.y - ey
		var triangles: Array = []
		var teeth := clampi(roundi(ey * 2.0 / 35.0), 2, 8)
		var tooth_height := ey * 2.0 / float(teeth)
		for i in range(teeth):
			var y := top + float(i) * tooth_height
			triangles.append(PackedVector2Array([Vector2(x, y + 1.0), Vector2(x + direction * SPIKE_REACH, y + tooth_height * 0.5), Vector2(x, y + tooth_height - 1.0)]))
		item["_triangles"] = triangles
		item["_bounds"] = Rect2(Vector2(minf(x, x + direction * SPIKE_REACH), top), Vector2(SPIKE_REACH, ey * 2.0))
	else:
		var radius := float(item.get("r", 36.0))
		var half_length := float(item.get("half_length", 0.0))
		var angle := float(item.get("angle", 0.0))
		var angle_sway := float(item.get("angle_sway", 0.0))
		ex = radius
		ey = radius
		if shape in ["capsule", "polygon"]:
			if angle_sway > 0.0:
				# A disk encloses the entire angular sweep, including endcaps.
				ex += half_length
				ey += half_length
			else:
				ex += absf(cos(angle)) * half_length
				ey += absf(sin(angle)) * half_length
		ex += absf(float(item.get("amplitude", item.get("motion_x", 0.0))))
		ey += _motion_y(item)
		item["_bounds"] = Rect2(center - Vector2(ex, ey), Vector2(ex * 2.0, ey * 2.0))
	if shape == "polygon":
		item["_polygon"] = _silhouette_points(kind, float(item["r"]), float(item.get("half_length", 0.0)))
	item["_ey"] = ey
	item["_end_h"] = float(item["h"]) + ey

func _validate_cell(action: Dictionary, candidates: Array) -> bool:
	# All-phase envelopes certify a corridor for the selected world's own
	# speed curve, including its night pace and the height gained in flight.
	var start := float(action["cell_start"])
	var end := float(action["cell_end"])
	var jump_start := float(action["height_px"])
	var from_x := LEFT_X if int(action["from_side"]) == 0 else RIGHT_X
	var to_x := LEFT_X if int(action["to_side"]) == 0 else RIGHT_X
	var radius := VALIDATION_RADIUS
	if from_x != to_x:
		var jump_end := _jump_ceiling(jump_start)
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

func validate_witness(time_offset: float = 0.0) -> bool:
	for action: Dictionary in witness:
		if not _validate_cell(action, hazards) or not _validate_action_motion(action, time_offset):
			return false
	return true

func _validate_action_motion(action: Dictionary, time_offset: float) -> bool:
	# Match main._simulate_step: increment time, integrate selected-world
	# run_speed_at, then add the jump arc and test the actual rendered shape.
	var height := float(action["cell_start"])
	var time := time_offset
	var jump_elapsed := -1.0
	var from_x := LEFT_X if int(action["from_side"]) == 0 else RIGHT_X
	var to_x := LEFT_X if int(action["to_side"]) == 0 else RIGHT_X
	var x := from_x
	var launched := from_x == to_x
	while height < float(action["cell_end"]):
		if not launched and height >= float(action["height_px"]):
			launched = true
			jump_elapsed = 0.0
		var dt := 1.0 / 120.0
		# Input can arrive on any physics frame. Split the crossing frame to
		# represent the witness's exact scheduled press rather than delaying it.
		if not launched:
			dt = minf(dt, maxf(0.000001, (float(action["height_px"]) - height) / RushTuning.run_speed_at(height, time + dt, world_id)))
		var previous_point := Vector2(x, -height)
		var previous_time := time
		time += dt
		height += RushTuning.run_speed_at(height, time, world_id) * dt
		if jump_elapsed >= 0.0:
			var previous := jump_elapsed / JUMP_DURATION
			jump_elapsed = minf(jump_elapsed + dt, JUMP_DURATION)
			var fraction := jump_elapsed / JUMP_DURATION
			height += (sin(fraction * PI) - sin(previous * PI)) * JUMP_ARC
			x = lerpf(from_x, to_x, 0.5 - cos(fraction * PI) * 0.5)
			if jump_elapsed >= JUMP_DURATION:
				jump_elapsed = -1.0
		if not collision_kind_along(previous_point, Vector2(x, -height), previous_time, time, VALIDATION_RADIUS).is_empty():
			return false
	return true

func get_witness() -> Array:
	return witness.duplicate(true)

func _vertical_extent(item: Dictionary) -> float:
	return float(item.get("_ey", item.get("r", 42.0)))

func _motion_y(item: Dictionary) -> float:
	if item.has("motion_y"):
		return absf(float(item["motion_y"]))
	var kind := String(item["kind"])
	if kind == "falling":
		return float(item.get("fall_range", 100.0)) * 0.5
	if kind == "insect": return 16.0
	if kind == "electric": return 14.0
	if kind == "pendulum": return 18.0
	return 0.0

func _hazard_center(item: Dictionary, time: float) -> Vector2:
	var center := Vector2(float(item["x"]), -float(item["h"]))
	var phase := float(item.get("phase", 0.0))
	var frequency := float(item.get("frequency", 1.0))
	if String(item["kind"]) == "falling" and not item.has("motion_y"):
		frequency /= 70.0
	center.x += sin(time * frequency + phase) * float(item.get("amplitude", item.get("motion_x", 0.0)))
	# Opposite x/y phases give rocks a fall-return and insects/orbs an orbit.
	center.y += cos(time * frequency + phase) * _motion_y(item)
	return center

func _hazard_rotation(item: Dictionary, time: float) -> float:
	var angle := float(item.get("angle", 0.0))
	angle += sin(time * float(item.get("frequency", 1.0)) + float(item.get("phase", 0.0))) * float(item.get("angle_sway", 0.0))
	angle += time * float(item.get("spin", 0.0))
	return angle

func _hazard_active(item: Dictionary, time: float) -> bool:
	if String(item["kind"]) == "timed":
		return _timed_active(item, time)
	if not item.has("pulse_period"):
		return true
	return fposmod(time + float(item["phase"]), float(item["pulse_period"])) < float(item["pulse_on"])

func collision_at(point: Vector2, time: float, radius: float = 20.0) -> bool:
	return not collision_kind_at(point, time, radius).is_empty()

func collision_kind_at(point: Vector2, time: float, radius: float = 20.0) -> String:
	# Shape, moving center, orientation and active phase are shared by draw.
	var height := -point.y
	if section_is_safe(height):
		return ""
	for item: Dictionary in hazards:
		if absf(height - float(item["h"])) > float(item["_ey"]) + radius or not _hazard_active(item, time):
			continue
		var kind := String(item["kind"])
		var death_kind := "electric" if kind == "electric" or kind == "lightning" or kind == "storm_orb" else kind
		if String(item.get("shape", "circle")) == "spikes":
			for triangle: PackedVector2Array in item["_triangles"]:
				if _circle_polygon(point, radius, triangle):
					return death_kind
		else:
			var center := _hazard_center(item, time)
			var reach := radius + float(item["r"])
			var nearest := center
			if String(item.get("shape", "circle")) == "capsule":
				var axis := Vector2.from_angle(_hazard_rotation(item, time))
				var half_length := float(item.get("half_length", 0.0))
				nearest += axis * clampf((point - center).dot(axis), -half_length, half_length)
			if String(item.get("shape", "circle")) == "polygon":
				var local := (point - center).rotated(-_hazard_rotation(item, time))
				if _circle_polygon(local, radius, item["_polygon"]):
					return death_kind
			elif point.distance_squared_to(nearest) <= reach * reach:
				return death_kind
	return ""

func collision_kind_along(from: Vector2, to: Vector2, start_time: float, end_time: float, radius: float = 20.0) -> String:
	# A 120Hz step can cross an entire small obstacle at late-run pace.
	# Sweep the actual cached shape instead of increasing arbitrary substeps.
	var first_height := minf(-from.y, -to.y)
	var last_height := maxf(-from.y, -to.y)
	for section: Dictionary in safe_sections:
		if first_height >= float(section["start"]) and last_height <= float(section["end"]):
			return ""
	var middle_time := (start_time + end_time) * 0.5
	var duration := absf(end_time - start_time)
	for item: Dictionary in hazards:
		if first_height > float(item["h"]) + float(item["_ey"]) + radius or last_height < float(item["h"]) - float(item["_ey"]) - radius:
			continue
		if not _hazard_active(item, start_time) and not _hazard_active(item, middle_time) and not _hazard_active(item, end_time):
			continue
		var kind := String(item["kind"])
		var death_kind := "electric" if kind == "electric" or kind == "lightning" or kind == "storm_orb" else kind
		var shape := String(item.get("shape", "circle"))
		if shape == "spikes":
			for triangle: PackedVector2Array in item["_triangles"]:
				if _segment_hits_polygon(from, to, radius, triangle):
					return death_kind
			continue
		# Relative endpoints incorporate actual translation. The small chord
		# error uses the sine's second-derivative bound; angular motion expands
		# only by its maximum displacement within this one physics frame.
		var relative_from := from - _hazard_center(item, start_time)
		var relative_to := to - _hazard_center(item, end_time)
		var frequency := absf(float(item.get("frequency", 1.0)))
		var translation := absf(float(item.get("amplitude", item.get("motion_x", 0.0)))) + _motion_y(item)
		var margin := translation * frequency * frequency * duration * duration * 0.125
		var half_length := float(item.get("half_length", 0.0))
		var turn_rate := absf(float(item.get("spin", 0.0))) + absf(float(item.get("angle_sway", 0.0))) * frequency
		margin += (float(item["r"]) + half_length) * turn_rate * duration * 0.5
		var rotation := -_hazard_rotation(item, middle_time)
		relative_from = relative_from.rotated(rotation)
		relative_to = relative_to.rotated(rotation)
		if shape == "polygon":
			if _segment_hits_polygon(relative_from, relative_to, radius + margin, item["_polygon"]):
				return death_kind
		elif shape == "capsule":
			var reach := radius + float(item["r"]) + margin
			if _segment_distance_squared(relative_from, relative_to, Vector2(-half_length, 0), Vector2(half_length, 0)) <= reach * reach:
				return death_kind
		else:
			var reach := radius + float(item["r"]) + margin
			if Geometry2D.get_closest_point_to_segment(Vector2.ZERO, relative_from, relative_to).length_squared() <= reach * reach:
				return death_kind
	return ""

static func _segment_hits_polygon(from: Vector2, to: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(from, polygon) or Geometry2D.is_point_in_polygon(to, polygon):
		return true
	var squared := radius * radius
	for index in range(polygon.size()):
		if _segment_distance_squared(from, to, polygon[index], polygon[(index + 1) % polygon.size()]) <= squared:
			return true
	return false

static func _segment_distance_squared(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(Geometry2D.get_closest_point_to_segment(a, c, d).distance_squared_to(a), Geometry2D.get_closest_point_to_segment(b, c, d).distance_squared_to(b)), minf(Geometry2D.get_closest_point_to_segment(c, a, b).distance_squared_to(c), Geometry2D.get_closest_point_to_segment(d, a, b).distance_squared_to(d)))

func collect_along(from: Vector2, to: Vector2) -> int:
	var collected := 0
	for coin: Dictionary in coins:
		if bool(coin.get("collected", false)):
			continue
		var point := Vector2(float(coin["x"]), -float(coin["h"]))
		if Geometry2D.get_closest_point_to_segment(point, from, to).distance_squared_to(point) <= 48.0 * 48.0:
			coin["collected"] = true
			collected += 1
	return collected

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
		if ahead >= 70.0 and ahead <= clampf(_world_speed_at(-point.y) * 0.09 + 150.0, 210.0, 390.0) and absf(point.x - float(fly["x"])) < 60.0:
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
		for key: String in ["_triangles", "_polygon", "_bounds", "_ey", "_end_h"]:
			clean.erase(key)
		clean_hazards.append(clean)
	return {"version": 6, "seed": str(seed_value), "rng_state": str(rng.state),
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
	if not WORLD_TYPES.has(world_id):
		world_id = "jungle"
	_profile = RushTuning.profile_for(world_id)
	challenge_level = int(data.get("challenge_level", 1))
	if not int(data.get("version", 0)) in [2, 3, 4, 5, 6]:
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
		var textures := {"spikes": _spike_texture(), "coin": _coin_texture(),
			"fly0": _fly_texture(0), "fly1": _fly_texture(1)}
		for kind: String in WORLD_TYPES[world_id]:
			if kind != String(WORLD_WALL_KIND[world_id]):
				textures[kind] = _themed_texture(kind)
		# Older snapshots and electrical regression fixtures remain drawable.
		for kind: String in ["stone", "falling", "saw", "insect", "electric", "crystal", "pendulum"]:
			textures[kind] = _themed_texture(kind)
		_texture_cache[world_id] = textures
	_art = _texture_cache[world_id]

func _draw() -> void:
	if _art.is_empty():
		return
	var tint := Color.WHITE.lerp(Color("b4ccff"), night_amount * 0.16)
	for item: Dictionary in hazards:
		var kind := String(item["kind"])
		var center := _hazard_center(item, animation_time)
		var active := _hazard_active(item, animation_time)
		var color := tint
		if not active:
			color.a = 0.24
		if String(item.get("shape", "circle")) == "spikes":
			var direction := 1.0 if int(item["side"]) == 0 else -1.0
			draw_set_transform(center, 0.0, Vector2(direction, 1.0))
			var half_height := float(item["half_h"])
			var teeth := clampi(roundi(half_height * 2.0 / 35.0), 2, 8)
			var tooth_height := half_height * 2.0 / float(teeth)
			for index in range(teeth):
				# One cached tooth per collision triangle; no stretched tooth count.
				draw_texture_rect(_art["spikes"], Rect2(0.0, -half_height + float(index) * tooth_height + 1.0, SPIKE_REACH, tooth_height - 2.0), false, color)
		else:
			var angle := _hazard_rotation(item, animation_time)
			var radius := float(item["r"])
			if bool(item.get("suspended", false)) and not bool(item.get("wall_attached", false)):
				draw_set_transform(Vector2.ZERO)
				var anchor := Vector2(float(item["x"]), -float(item["h"]) - 135.0)
				draw_line(anchor, center, accent_color.darkened(0.6) if kind == "vine" else metal_color.darkened(0.45), 4.0)
			draw_set_transform(center, angle)
			if String(item.get("shape", "circle")) == "capsule":
				var half_length := float(item.get("half_length", 0.0))
				var core := _capsule_color(kind)
				core.a = color.a
				draw_line(Vector2(-half_length, 0), Vector2(half_length, 0), core.darkened(0.45), radius * 2.0)
				draw_circle(Vector2(-half_length, 0), radius, core.darkened(0.45))
				draw_circle(Vector2(half_length, 0), radius, core.darkened(0.45))
				draw_line(Vector2(-half_length, -1), Vector2(half_length, -1), core, maxf(2.0, radius * 1.25))
				draw_circle(Vector2(-half_length, 0), radius * 0.7, core)
				draw_circle(Vector2(half_length, 0), radius * 0.7, core)
				if _art.has(kind):
					draw_texture_rect(_art[kind], Rect2(-half_length, -radius, half_length * 2.0, radius * 2.0), false, color)
			else:
				if _art.has(kind):
					var extent := Vector2(radius + float(item.get("half_length", 0.0)), radius)
					draw_texture_rect(_art[kind], Rect2(-extent, extent * 2.0), false, color)
				if kind == "beetle" or kind == "insect":
					# Wings stay within the same lethal body radius.
					var flutter := sin(animation_time * 24.0) * 3.0
					draw_line(Vector2(-radius * 0.7, -5), Vector2(-radius * 0.2, flutter), accent_color.lightened(0.3), 3.0)
					draw_line(Vector2(radius * 0.7, -5), Vector2(radius * 0.2, -flutter), accent_color.lightened(0.3), 3.0)
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

func _capsule_color(kind: String) -> Color:
	match kind:
		"vine": return Color("7aa94c")
		"icicle": return Color("b6efff")
		"frost": return Color("76d6eb")
		"crystal_beam": return Color("ed87ff")
		"fire_jet": return Color("ff9a28")
		"lightning", "electric": return Color("8de9ff")
		"wind_blade": return Color("dcfff2")
	return danger_color

static func _silhouette_points(kind: String, radius: float, half_length: float = 0.0) -> PackedVector2Array:
	var tip := half_length + radius
	if kind == "icicle":
		# Normalised corners keep the cached drawing and exact hit polygon
		# aligned for both current icicles and older saved dimensions.
		return PackedVector2Array([Vector2(-tip, -radius * 0.72), Vector2(-tip, radius * 0.72), Vector2(tip * 0.28, radius * 0.55), Vector2(tip, 0), Vector2(tip * 0.28, -radius * 0.55)])
	if kind == "fire_jet":
		return PackedVector2Array([Vector2(-tip, 0), Vector2(-half_length * 0.5, -radius * 0.8), Vector2(-half_length * 0.1, -radius * 0.5), Vector2(half_length * 0.45, -radius), Vector2(tip, -radius * 0.3), Vector2(tip, radius * 0.3), Vector2(half_length * 0.45, radius), Vector2(-half_length * 0.1, radius * 0.6), Vector2(-half_length * 0.5, radius * 0.8)])
	if kind == "wind_blade":
		return PackedVector2Array([Vector2(-tip, radius * 0.45), Vector2(-half_length * 0.4, -radius * 0.7), Vector2(half_length * 0.35, -radius), Vector2(tip, -radius * 0.1), Vector2(half_length * 0.25, -radius * 0.1), Vector2(-half_length * 0.5, radius * 0.3)])
	if kind == "crystal_beam":
		return PackedVector2Array([Vector2(-tip, 0), Vector2(-half_length, -radius), Vector2(half_length, -radius), Vector2(tip, 0), Vector2(half_length, radius), Vector2(-half_length, radius)])
	if kind == "frost":
		return PackedVector2Array([Vector2(-tip, 0), Vector2(-half_length, -radius * 0.45), Vector2(-half_length * 0.35, -radius * 0.45), Vector2(-half_length * 0.12, -radius), Vector2(half_length * 0.12, -radius), Vector2(half_length * 0.35, -radius * 0.45), Vector2(half_length, -radius * 0.45), Vector2(tip, 0), Vector2(half_length, radius * 0.45), Vector2(half_length * 0.35, radius * 0.45), Vector2(half_length * 0.12, radius), Vector2(-half_length * 0.12, radius), Vector2(-half_length * 0.35, radius * 0.45), Vector2(-half_length, radius * 0.45)])
	if kind == "vine":
		var points := PackedVector2Array([Vector2(-tip, 0)])
		for index in range(7):
			var x := lerpf(-half_length, half_length, float(index) / 6.0)
			points.append(Vector2(x, -radius * (0.95 if index % 2 == 0 else 0.32)))
		points.append(Vector2(tip, 0))
		for index in range(6, -1, -1):
			var x := lerpf(-half_length, half_length, float(index) / 6.0)
			points.append(Vector2(x, radius * (0.95 if index % 2 != 0 else 0.32)))
		return points
	if kind in ["prism", "crystal"]:
		return PackedVector2Array([Vector2(0, -radius), Vector2(radius * 0.74, 0), Vector2(0, radius), Vector2(-radius * 0.74, 0)])
	if kind == "shard":
		return PackedVector2Array([Vector2(-radius * 0.4, -radius * 0.8), Vector2(radius, -radius * 0.42), Vector2(radius * 0.38, radius * 0.92), Vector2(-radius * 0.92, radius * 0.38)])
	var points := PackedVector2Array()
	for index in range(10):
		var angle := float(index) * TAU / 10.0
		var factor := 1.0 if index % 2 == 0 else 0.86
		if kind == "obsidian": factor = 1.0 if index % 2 == 0 else 0.66
		if kind == "ice_chunk": factor = 1.0 if index % 3 != 0 else 0.75
		points.append(Vector2.from_angle(angle) * radius * factor)
	return points

func _long_polygon_texture(kind: String) -> Texture2D:
	var image := _new_image(128, 32)
	var ratio := 3.0
	match kind:
		"icicle": ratio = ICICLE_HALF_LENGTH / ICICLE_RADIUS
		"vine": ratio = 40.0 / 13.0
		"frost": ratio = 38.0 / 13.0
		"fire_jet": ratio = 42.0 / 13.0
		"wind_blade": ratio = 42.0 / 12.0
		"crystal_beam": ratio = 62.0 / 10.0
	var points := _silhouette_points(kind, 1.0, ratio)
	var base := _capsule_color(kind)
	for y in range(32):
		for x in range(128):
			var point := Vector2((float(x) / 127.0 * 2.0 - 1.0) * (ratio + 1.0), float(y) / 31.0 * 2.0 - 1.0)
			if not Geometry2D.is_point_in_polygon(point, points): continue
			var color := base.lightened(0.2) if y < 15 else base.darkened(0.18)
			var edge := false
			for index in range(points.size()):
				if Geometry2D.get_closest_point_to_segment(point, points[index], points[(index + 1) % points.size()]).distance_squared_to(point) < 0.012:
					edge = true
					break
			if edge: color = Color("24546e") if kind == "icicle" else base.darkened(0.6)
			elif kind == "icicle":
				# A bright inner face and a dark contour stay inside the same
				# lethal silhouette; no glow makes empty space look dangerous.
				if point.y < -0.30: color = Color("f1ffff")
				elif absf(point.y - 0.05) < 0.16: color = Color("d9fbff")
				else: color = Color("80cce7")
			elif kind == "vine":
				if absf(point.y) < 0.2: color = Color("517536")
				elif absf(point.y) > 0.5: color = Color("b6aa67")
			elif kind == "fire_jet":
				if absf(point.y) < 0.34 + sin(point.x * 3.0) * 0.12: color = Color("fff2a2")
				elif absf(point.y) > 0.65: color = Color("e45228")
			elif kind == "wind_blade":
				if absf(point.y + 0.4) < 0.15: color = Color("f2fff9")
				else: color.a = 0.85
			elif kind == "frost":
				if x % 13 < 2 or absf(point.y) < 0.12: color = Color("eaffff")
			elif kind == "crystal_beam":
				if absf(point.y) < 0.16: color = Color("fff4ff")
				elif (x / 16) % 2 == 0: color = base.lightened(0.3)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _themed_texture(kind: String) -> Texture2D:
	if kind in ["icicle", "vine", "frost", "fire_jet", "wind_blade", "crystal_beam"]:
		return _long_polygon_texture(kind)
	# Small cached pixel silhouettes carry biome-specific materials and cues.
	# The same local polygon is used for collision, including rotating shards.
	var image := _new_image(64, 64)
	var polygonal := kind in ["root", "boulder", "rockfall", "canyon_weight", "ice_chunk", "prism", "shard", "obsidian", "crystal"]
	var points := _silhouette_points(kind, 31.5)
	var base := danger_color
	match kind:
		"root": base = Color("80543b")
		"beetle", "insect": base = Color("c27c3b")
		"boulder", "rockfall", "stone", "falling": base = Color("ad7752")
		"canyon_weight", "pendulum": base = Color("80685d")
		"ice_chunk": base = Color("8cd6f0")
		"prism", "crystal": base = Color("b985ed")
		"shard": base = Color("ef98dc")
		"lava_orb": base = Color("f66b29")
		"obsidian", "saw": base = Color("493b5d")
		"storm_orb": base = Color("52647e")
		_: base = _capsule_color(kind)
	for y in range(64):
		for x in range(64):
			var point := Vector2(float(x) - 31.5, float(y) - 31.5)
			var inside := Geometry2D.is_point_in_polygon(point, points) if polygonal else point.length_squared() <= 31.5 * 31.5
			if not inside: continue
			var light := clampf((-point.x - point.y) / 100.0, -0.25, 0.25)
			var color := base.lightened(light) if light >= 0.0 else base.darkened(-light)
			var edge := point.length() > 28.5
			if polygonal:
				edge = false
				for index in range(points.size()):
					if Geometry2D.get_closest_point_to_segment(point, points[index], points[(index + 1) % points.size()]).distance_squared_to(point) < 3.0:
						edge = true
						break
			if edge: color = base.darkened(0.6)
			elif kind == "root":
				if (x + int(sin(float(y) * 0.18) * 7.0)) % 13 < 3: color = Color("392e28")
				if y < 18 and x % 9 < 5: color = Color("8ba747")
			elif kind == "beetle" or kind == "insect":
				if absf(point.x) < 2.5 or (x / 9 + y / 11) % 4 == 0: color = Color("3d3028")
				if y < 19 and x > 19 and x < 45: color = Color("f8e4a2")
			elif kind in ["boulder", "rockfall", "stone", "falling"]:
				if (y + int(point.x * 0.24)) % 17 < 3: color = base.darkened(0.28)
				if absf(point.x - sin(point.y * 0.1) * 8.0) < 1.5 and y > 27: color = Color("4a342c")
			elif kind in ["canyon_weight", "pendulum"]:
				if absf(point.x) < 3.0 or absf(point.y) < 3.0: color = Color("c3a076")
				if point.length() < 7.0: color = Color("472d25")
			elif kind in ["ice_chunk", "prism", "shard", "crystal"]:
				if point.x < point.y * 0.35: color = base.lightened(0.2)
				if absf(point.x - point.y * 0.35) < 1.5: color = Color("efffff")
				if x % 21 == 4 and y % 19 < 6: color = Color("f8e5ff")
			elif kind in ["lava_orb", "obsidian", "saw"]:
				if absf(sin(point.x * 0.15 + sin(point.y * 0.12))) < 0.2 or absf(point.y + point.x * 0.45) < 2.0: color = Color("ffb642")
				if kind == "lava_orb" and point.length() < 20.0: color = Color("ffd06a")
			elif kind == "storm_orb":
				if absf(point.x - sin(point.y * 0.34) * 10.0) < 2.5: color = Color("d9faff")
				if point.y < -9.0 and x % 17 < 7: color = Color("8cb0c8")
			elif kind == "vine":
				if (x + y / 5) % 14 < 4: color = Color("30452a")
			elif kind == "fire_jet":
				if absf(point.y) < 10.0 + sin(point.x * 0.3) * 4.0: color = Color("fff3a3")
			elif kind in ["lightning", "electric", "crystal_beam", "wind_blade", "frost", "icicle"]:
				if absf(point.y - sin(point.x * 0.35) * 7.0) < 3.0: color = Color("efffff")
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _new_image(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image

func _rect(image: Image, rect: Rect2i, color: Color) -> void:
	image.fill_rect(rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height())), color)

func _spike_texture() -> Texture2D:
	var image := _new_image(84, 32)
	var base := danger_color
	match world_id:
		"jungle": base = Color("8c9148")
		"canyon": base = Color("bd875b")
		"ice": base = Color("b0e8f3")
		"crystal": base = Color("c69bf4")
		"volcano": base = Color("d57537")
		"sky": base = Color("abcbe4")
	for y in range(32):
		var reach := (1.0 - absf((float(y) - 15.5) / 15.5)) * 83.0
		for x in range(int(reach) + 1):
			var color := base.lightened(0.22) if y < 15 else base.darkened(0.15)
			if x < 2 or float(x) > reach - 2.0: color = base.darkened(0.55)
			elif world_id == "jungle" and (x + y * 2) % 17 < 3: color = Color("483925")
			elif world_id == "volcano" and (x + y * 3) % 23 < 3: color = Color("ffdc66")
			elif world_id == "sky" and y > 12 and y < 17: color = Color("efffff")
			image.set_pixel(x, y, color)
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
