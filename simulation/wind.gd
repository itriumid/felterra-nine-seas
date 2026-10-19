class_name Wind
extends RefCounted
## The true wind over the water: a steady prevailing wind with gusts that drift downwind and a
## direction that wanders slowly, the way a trade wind does.

## Mean wind speed in meters per second. Seven is about 14 knots, a good sailing breeze.
var base_speed := 7.0
## Compass bearing the wind blows from, in degrees. 60 is east-northeast, the trade wind of the
## northern tropics.
var base_bearing := 60.0
## Gusts and lulls as a fraction of the mean speed.
var gust_strength := 0.25
## How far the wind direction wanders either side of its mean, in degrees.
var shift_range := 10.0
## How far a passing gust bends the wind, in degrees.
var gust_bend := 4.0
## Seconds of simulated time since the wind started blowing.
var time := 0.0

var _gusts := FastNoiseLite.new()
var _shifts := FastNoiseLite.new()


func _init(seed_value: int = 39) -> void:
	_gusts.seed = seed_value
	_gusts.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_gusts.frequency = 1.0 / 400.0
	_shifts.seed = seed_value + 1
	_shifts.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_shifts.frequency = 1.0 / 240.0


## A wind that never changes, for tests and polar diagrams.
static func steady(speed: float, bearing: float) -> Wind:
	var wind := Wind.new()
	wind.base_speed = speed
	wind.base_bearing = bearing
	wind.gust_strength = 0.0
	wind.shift_range = 0.0
	wind.gust_bend = 0.0
	return wind


func advance(delta: float) -> void:
	time += delta


## Bearing the wind blows from right now, in degrees, before gusts bend it locally.
func mean_bearing() -> float:
	return base_bearing + shift_range * _shifts.get_noise_1d(time)


## Velocity of the air at a point on the water, in meters per second, pointing where the wind
## blows to.
func velocity_at(world_position: Vector2) -> Vector2:
	var toward := bearing_to_direction(mean_bearing() + 180.0)
	# Gusts are patterns in the air, so they travel with it.
	var drifted := world_position - toward * base_speed * time
	var gust := _gusts.get_noise_2dv(drifted)
	var local_bearing := mean_bearing() + gust_bend * gust
	var speed := base_speed * (1.0 + gust_strength * gust)
	return bearing_to_direction(local_bearing + 180.0) * speed


## Unit vector for a compass bearing. North is up the screen, east to the right.
static func bearing_to_direction(bearing: float) -> Vector2:
	return Vector2.from_angle(deg_to_rad(bearing - 90.0))


## Compass bearing, 0 to 360, that a direction points toward.
static func direction_to_bearing(direction: Vector2) -> float:
	return fposmod(rad_to_deg(direction.angle()) + 90.0, 360.0)
