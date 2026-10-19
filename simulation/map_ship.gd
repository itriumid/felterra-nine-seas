class_name MapShip
extends RefCounted
## A ship crossing the world map. At this scale a voyage takes days, so instead of stepping
## the full physics sixty times a second, the ship settles toward the steady speed the same
## physics gives for its heading and wind: the speed polar. Same model, a different clock.

## Seconds of game time a ship takes to settle to a new speed.
const SETTLING_TIME := 600.0

var design: ShipDesign
var position := Vector2.ZERO
var heading := 0.0
var speed := 0.0
var aground := false


func _init(ship_design: ShipDesign) -> void:
	design = ship_design


func forward() -> Vector2:
	return Vector2.from_angle(heading)


func step(delta: float, true_wind: Vector2, chart: Chart) -> void:
	var angle_off_wind := rad_to_deg(absf(forward().angle_to(-true_wind)))
	var target := maxf(Polar.lookup(design.id, angle_off_wind, true_wind.length()), 0.0)
	speed = lerpf(speed, target, 1.0 - exp(-delta / SETTLING_TIME))
	var next := position + forward() * speed * delta
	aground = chart.is_land(next)
	if aground:
		speed = 0.0
	else:
		position = next
