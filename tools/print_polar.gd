extends SceneTree
## Prints each ship's speed polar, for tuning the sailing model.
## Run with: godot --headless --path . --script tools/print_polar.gd

const KNOTS_PER_METER_PER_SECOND := 1.943844


func _init() -> void:
	var wind_speed := 7.0
	for design: ShipDesign in [ShipDesign.sloop(), ShipDesign.brig()]:
		print("%s in %.0f knots of wind (hull speed %.1f knots)" % [
			design.display_name, wind_speed * KNOTS_PER_METER_PER_SECOND,
			design.hull_speed() * KNOTS_PER_METER_PER_SECOND,
		])
		print("  angle   speed   upwind")
		var speeds := Polar.table(design, wind_speed)
		for angle: float in speeds:
			var speed: float = speeds[angle]
			print("  %5.0f  %6.2f  %7.2f" % [
				angle, speed * KNOTS_PER_METER_PER_SECOND,
				speed * cos(deg_to_rad(angle)) * KNOTS_PER_METER_PER_SECOND,
			])
	quit()
