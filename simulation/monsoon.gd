class_name Monsoon
extends RefCounted
## The monsoon winds of the Nusantara seas, which reverse with the seasons.
##
## From December to March the northeast monsoon blows from the northeast north of the equator,
## and turns as it crosses it to blow from the northwest over the Java Sea (the west monsoon).
## From June to September it reverses: the southeast trade blows over Java and turns into the
## southwest monsoon north of the equator. Between them, in April and May and in October and
## November, the winds are light and wander. Traders planned their year around this.

const STRONGEST_NORTHEAST_DAY := 15.0
## Mean speed of a settled monsoon, and of the light airs between them, in meters per second.
const MONSOON_SPEED := 7.0
const LIGHT_AIR_SPEED := 2.0
## The equator isn't a sharp line for the wind: it turns across a band this many degrees wide
## on either side.
const TURNING_BAND := 3.0

var calendar: Calendar
var gust_strength := 0.25

var _gusts := FastNoiseLite.new()
var _wander := FastNoiseLite.new()


func _init(game_calendar: Calendar, seed_value := 39) -> void:
	calendar = game_calendar
	_gusts.seed = seed_value
	_gusts.frequency = 1.0 / 150000.0
	_wander.seed = seed_value + 1
	_wander.frequency = 1.0 / (6.0 * 3600.0)


## +1 at the height of the northeast monsoon, -1 at the height of the southwest, near 0 in the
## changes between.
func season() -> float:
	return cos(TAU * (calendar.day_of_year() - STRONGEST_NORTHEAST_DAY) / Calendar.DAYS_PER_YEAR)


func season_name(latitude: float) -> String:
	var value := season()
	if absf(value) < 0.3:
		return "Changing monsoon"
	if value > 0.0:
		return "Northeast monsoon" if latitude > 0.0 else "West monsoon"
	return "Southwest monsoon" if latitude > 0.0 else "East monsoon"


## Velocity of the air at a point on the chart, pointing where it blows to.
func velocity_at(world_position: Vector2) -> Vector2:
	var latitude := Chart.latitude_at(world_position)
	var north := smoothstep(-TURNING_BAND, TURNING_BAND, latitude)
	var value := season()
	var northeast_monsoon := _blowing_from(_turn(300.0, 45.0, north), MONSOON_SPEED * pow(maxf(value, 0.0), 0.6))
	var southwest_monsoon := _blowing_from(_turn(120.0, 225.0, north), MONSOON_SPEED * pow(maxf(-value, 0.0), 0.6))
	var light_airs := _blowing_from(180.0 * _wander.get_noise_1d(calendar.seconds) + 90.0, LIGHT_AIR_SPEED)
	var drifted := world_position - northeast_monsoon * calendar.seconds - southwest_monsoon * calendar.seconds
	var gust := 1.0 + gust_strength * _gusts.get_noise_2dv(drifted)
	return (northeast_monsoon + southwest_monsoon + light_airs) * gust


## Bearing between two others along the shorter way round, in degrees.
static func _turn(from_bearing: float, to_bearing: float, weight: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(from_bearing), deg_to_rad(to_bearing), weight))


static func _blowing_from(bearing: float, speed: float) -> Vector2:
	return Wind.bearing_to_direction(bearing + 180.0) * speed
