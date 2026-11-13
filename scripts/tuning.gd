class_name RushTuning
extends RefCounted

const WALL_LEFT := 270.0
const WALL_RIGHT := 810.0
const PLAYER_LEFT := 296.0
const PLAYER_RIGHT := 784.0
const JUMP_DURATION := 0.24
const JUMP_ARC := 45.0
const PIXELS_PER_METRE := 64.0
# Deprecated compatibility values. Runtime pace is never clamped to these.
const MAX_SPEED := 2700.0
const START_SPEED := 800.0
const NIGHT_SPEED := START_SPEED * 0.85
const NIGHT_MULTIPLIER := 0.85
const CENTER_WALL_WIDTH := 56.0
const CENTER_WALL_LEFT := (1080.0 - CENTER_WALL_WIDTH) * 0.5
const CENTER_WALL_RIGHT := CENTER_WALL_LEFT + CENTER_WALL_WIDTH
const DAY_SECONDS := 40.0
const NIGHT_SECONDS := 20.0
const CYCLE_SECONDS := DAY_SECONDS + NIGHT_SECONDS
const CYCLE_FADE_SECONDS := 4.0
const CENTER_EVERY_METRES := 1500.0
const CENTER_PREVIEW_SECONDS := 1.6
const CENTER_ENTER_SECONDS := 0.45
const CENTER_RIDE_SECONDS := 5.0
const CENTER_EXIT_SECONDS := 0.5

# Let k be distance in kilometres. The day curve is
# start_speed + growth_per_km * k + endless_quadratic * k².
# All three coefficients increase with the selected world, so difficulty
# ordering holds at every height. No end distance or maximum speed exists.
const WORLD_PROFILES := {
	"jungle": {"start_speed": 800.0, "growth_per_km": 850.0, "endless_quadratic": 12.0, "night_multiplier": NIGHT_MULTIPLIER, "spacing_scale": 1.22, "motion_scale": 0.72, "xp_multiplier": 0.55},
	"canyon": {"start_speed": 900.0, "growth_per_km": 1000.0, "endless_quadratic": 16.0, "night_multiplier": NIGHT_MULTIPLIER, "spacing_scale": 1.16, "motion_scale": 0.86, "xp_multiplier": 0.75},
	"ice": {"start_speed": 1000.0, "growth_per_km": 1180.0, "endless_quadratic": 20.0, "night_multiplier": NIGHT_MULTIPLIER, "spacing_scale": 1.10, "motion_scale": 1.0, "xp_multiplier": 1.0},
	"crystal": {"start_speed": 1120.0, "growth_per_km": 1350.0, "endless_quadratic": 24.0, "night_multiplier": NIGHT_MULTIPLIER, "spacing_scale": 1.06, "motion_scale": 1.10, "xp_multiplier": 1.25},
	"volcano": {"start_speed": 1240.0, "growth_per_km": 1540.0, "endless_quadratic": 29.0, "night_multiplier": NIGHT_MULTIPLIER, "spacing_scale": 1.03, "motion_scale": 1.20, "xp_multiplier": 1.55},
	"sky": {"start_speed": 1380.0, "growth_per_km": 1760.0, "endless_quadratic": 35.0, "night_multiplier": NIGHT_MULTIPLIER, "spacing_scale": 1.0, "motion_scale": 1.30, "xp_multiplier": 1.85}
}

static func profile_for(world_id: String) -> Dictionary:
	# UI and save callers may safely annotate their copy. Hot physics paths
	# read WORLD_PROFILES directly instead of allocating profile dictionaries.
	return WORLD_PROFILES.get(world_id, WORLD_PROFILES["jungle"]).duplicate(true)

static func speed_at(height_px: float, world_id: String = "jungle") -> float:
	var profile: Dictionary = WORLD_PROFILES.get(world_id, WORLD_PROFILES["jungle"])
	var kilometres := maxf(height_px, 0.0) / (PIXELS_PER_METRE * 1000.0)
	return float(profile["start_speed"]) + float(profile["growth_per_km"]) * kilometres + float(profile["endless_quadratic"]) * kilometres * kilometres

static func min_speed_at(height_px: float, world_id: String = "jungle") -> float:
	# A height-local bound across every day/night phase, not a fixed night pace.
	var profile: Dictionary = WORLD_PROFILES.get(world_id, WORLD_PROFILES["jungle"])
	return speed_at(height_px, world_id) * float(profile["night_multiplier"])

static func max_speed_at(height_px: float, world_id: String = "jungle") -> float:
	# Course certification uses this monotone local bound at future heights.
	return speed_at(height_px, world_id)

static func night_amount(seconds: float) -> float:
	var phase := fposmod(maxf(seconds, 0.0), CYCLE_SECONDS)
	if seconds >= CYCLE_SECONDS and phase < CYCLE_FADE_SECONDS:
		return 1.0 - smoothstep(0.0, CYCLE_FADE_SECONDS, phase)
	return smoothstep(DAY_SECONDS - CYCLE_FADE_SECONDS, DAY_SECONDS, phase)

static func is_night(seconds: float) -> bool:
	return fposmod(maxf(seconds, 0.0), CYCLE_SECONDS) >= DAY_SECONDS

static func cycle_remaining(seconds: float) -> float:
	var phase := fposmod(maxf(seconds, 0.0), CYCLE_SECONDS)
	return CYCLE_SECONDS - phase if phase >= DAY_SECONDS else DAY_SECONDS - phase

static func run_speed_at(height_px: float, seconds: float, world_id: String = "jungle") -> float:
	var profile: Dictionary = WORLD_PROFILES.get(world_id, WORLD_PROFILES["jungle"])
	return speed_at(height_px, world_id) * lerpf(1.0, float(profile["night_multiplier"]), night_amount(seconds))
