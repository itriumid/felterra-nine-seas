class_name Polar
extends RefCounted
## Speed polars: how fast a ship settles at each angle to a steady true wind. Sailors use them
## to choose a course; the world map will use them to sail ships between ports without running
## the full simulation.

const STEP := 1.0 / 60.0


## Steady forward speed, in meters per second, of a ship held on a fixed angle to the true
## wind (in degrees, 0 head to wind) with its sails trimmed automatically. Ships start from
## rest: a running start coasts for minutes in light air and reads as speed it doesn't have.
static func steady_speed(design: ShipDesign, wind_angle: float, wind_speed: float, seconds := 150.0) -> float:
	var wind := Wind.steady(wind_speed, 0.0)
	var ship := Ship.new(design)
	ship.heading = deg_to_rad(wind_angle - 90.0)
	var held_heading := ship.heading
	var steps := int(seconds / STEP)
	var settled_from := int(steps * 0.8)
	var total := 0.0
	for index in steps:
		ship.step(STEP, wind.velocity_at(ship.position))
		ship.heading = held_heading
		ship.yaw_rate = 0.0
		if index >= settled_from:
			total += ship.forward_speed()
	return total / float(steps - settled_from)


## Speeds at every angle from 0 to 180 degrees in the given increments.
static func table(design: ShipDesign, wind_speed: float, increment := 5.0) -> Dictionary:
	var speeds := {}
	var angle := 0.0
	while angle <= 180.0:
		speeds[angle] = steady_speed(design, angle, wind_speed)
		angle += increment
	return speeds


## Steady speed from the precomputed table, interpolated between the angles and wind speeds it
## holds. Angle in degrees off the wind, 0 to 180; wind speed in meters per second.
static func lookup(design_id: String, wind_angle: float, wind_speed: float) -> float:
	var rows: Array = PolarTable.SPEEDS[design_id]
	var angle := clampf(absf(wind_angle), 0.0, 180.0)
	var angle_position := angle / PolarTable.ANGLE_STEP
	var angle_index := mini(int(angle_position), PolarTable.ANGLE_COUNT - 2)
	var angle_weight := angle_position - angle_index

	var speeds := PolarTable.WIND_SPEEDS
	var wind := clampf(wind_speed, 0.0, speeds[speeds.size() - 1])
	if wind <= speeds[0]:
		# Below the lightest wind in the table, speed falls off in proportion to the wind.
		var scale := wind / speeds[0]
		return scale * lerpf(rows[0][angle_index], rows[0][angle_index + 1], angle_weight)
	var wind_index := 0
	while wind_index < speeds.size() - 2 and wind > speeds[wind_index + 1]:
		wind_index += 1
	var wind_weight := inverse_lerp(speeds[wind_index], speeds[wind_index + 1], wind)
	var lower := lerpf(rows[wind_index][angle_index], rows[wind_index][angle_index + 1], angle_weight)
	var upper := lerpf(rows[wind_index + 1][angle_index], rows[wind_index + 1][angle_index + 1], angle_weight)
	return lerpf(lower, upper, wind_weight)


## The angle off the wind, in degrees, that makes the most progress straight upwind: where to
## sail close-hauled when beating.
static func best_upwind_angle(design_id: String, wind_speed: float) -> float:
	var best_angle := 45.0
	var best_progress := -INF
	var angle := 30.0
	while angle <= 90.0:
		var progress := lookup(design_id, angle, wind_speed) * cos(deg_to_rad(angle))
		if progress > best_progress:
			best_progress = progress
			best_angle = angle
		angle += 2.0
	return best_angle
