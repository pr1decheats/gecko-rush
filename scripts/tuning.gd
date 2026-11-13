class_name RushTuning
extends RefCounted

const WALL_LEFT := 270.0
const WALL_RIGHT := 810.0
const PLAYER_LEFT := 296.0
const PLAYER_RIGHT := 784.0
const JUMP_DURATION := 0.24
const JUMP_ARC := 45.0
const PIXELS_PER_METRE := 64.0
const MAX_SPEED := 2700.0
const NIGHT_SPEED := 840.0
const START_SPEED := 820.0
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

# The absolute certification ceiling stays shared; each difficulty has a lower
# or equal pace limit. Legacy constants remain available to physics callers.
const WORLD_PROFILES := {
	"jungle": {"start_speed": 720.0, "max_speed": 1700.0, "night_speed": 680.0, "spacing_scale": 1.22, "motion_scale": 0.72, "xp_multiplier": 0.55, "first_ramp_metres": 500.0, "cap_metres": 3200.0},
	"canyon": {"start_speed": 840.0, "max_speed": 1950.0, "night_speed": 800.0, "spacing_scale": 1.16, "motion_scale": 0.86, "xp_multiplier": 0.75, "first_ramp_metres": 460.0, "cap_metres": 3000.0},
	"ice": {"start_speed": 960.0, "max_speed": 2200.0, "night_speed": 920.0, "spacing_scale": 1.10, "motion_scale": 1.0, "xp_multiplier": 1.0, "first_ramp_metres": 420.0, "cap_metres": 2800.0},
	"crystal": {"start_speed": 1080.0, "max_speed": 2450.0, "night_speed": 1040.0, "spacing_scale": 1.06, "motion_scale": 1.10, "xp_multiplier": 1.25, "first_ramp_metres": 380.0, "cap_metres": 2600.0},
	"volcano": {"start_speed": 1200.0, "max_speed": 2650.0, "night_speed": 1160.0, "spacing_scale": 1.03, "motion_scale": 1.20, "xp_multiplier": 1.55, "first_ramp_metres": 340.0, "cap_metres": 2400.0},
	"sky": {"start_speed": 1320.0, "max_speed": 2700.0, "night_speed": 1280.0, "spacing_scale": 1.0, "motion_scale": 1.30, "xp_multiplier": 1.85, "first_ramp_metres": 300.0, "cap_metres": 2200.0}
}

static func profile_for(world_id: String) -> Dictionary:
	return WORLD_PROFILES.get(world_id, WORLD_PROFILES["jungle"]).duplicate(true)

static func speed_at(height_px: float, world_id: String = "jungle") -> float:
	var profile: Dictionary = WORLD_PROFILES.get(world_id, WORLD_PROFILES["jungle"])
	var metres := maxf(height_px, 0.0) / PIXELS_PER_METRE
	var first_ramp := float(profile["first_ramp_metres"])
	var cap_metres := float(profile["cap_metres"])
	# Ease into the first 35% of acceleration, then build the remaining pace
	# over a longer stretch. Both joins have zero slope, avoiding abrupt steps.
	var gain := 0.35 * smoothstep(0.0, first_ramp, metres)
	gain += 0.65 * smoothstep(first_ramp, cap_metres, metres)
	return lerpf(float(profile["start_speed"]), float(profile["max_speed"]), gain)

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
	var day_speed := speed_at(height_px, world_id)
	var profile: Dictionary = WORLD_PROFILES.get(world_id, WORLD_PROFILES["jungle"])
	var night_speed := float(profile["night_speed"])
	var phase := fposmod(maxf(seconds, 0.0), CYCLE_SECONDS)
	if phase >= DAY_SECONDS:
		return night_speed
	if seconds >= CYCLE_SECONDS and phase < CYCLE_FADE_SECONDS:
		return lerpf(night_speed, day_speed, smoothstep(0.0, CYCLE_FADE_SECONDS, phase))
	return lerpf(day_speed, night_speed, smoothstep(DAY_SECONDS - CYCLE_FADE_SECONDS, DAY_SECONDS, phase))
