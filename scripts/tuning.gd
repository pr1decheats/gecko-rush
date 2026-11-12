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

static func speed_at(height_px: float) -> float:
	var metres := maxf(height_px, 0.0) / PIXELS_PER_METRE
	return START_SPEED + minf(metres / 250.0, 1.0) * 500.0 + minf(maxf(metres - 250.0, 0.0) / 750.0, 1.0) * 880.0 + minf(maxf(metres - 1000.0, 0.0) / 1000.0, 1.0) * 500.0

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

static func run_speed_at(height_px: float, seconds: float) -> float:
	var day_speed := speed_at(height_px)
	var phase := fposmod(maxf(seconds, 0.0), CYCLE_SECONDS)
	if phase >= DAY_SECONDS:
		return NIGHT_SPEED
	if seconds >= CYCLE_SECONDS and phase < CYCLE_FADE_SECONDS:
		return lerpf(NIGHT_SPEED, day_speed, smoothstep(0.0, CYCLE_FADE_SECONDS, phase))
	return lerpf(day_speed, NIGHT_SPEED, smoothstep(DAY_SECONDS - CYCLE_FADE_SECONDS, DAY_SECONDS, phase))
