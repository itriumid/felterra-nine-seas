extends TestCase
## The sailing model has to behave like real ships do, or nothing built on it will feel right.
## These pin the behavior that matters, with tolerances wide enough to allow retuning.

const WIND_SPEED := 7.0


func _best_upwind_angle(design: ShipDesign) -> float:
	var best_angle := 0.0
	var best_progress := -INF
	for angle in range(30, 91, 5):
		var progress := Polar.steady_speed(design, angle, WIND_SPEED) * cos(deg_to_rad(angle))
		if progress > best_progress:
			best_progress = progress
			best_angle = angle
	return best_angle


func test_sloop_beats_upwind_at_about_45_degrees() -> void:
	var angle := _best_upwind_angle(ShipDesign.sloop())
	check(angle >= 40.0 and angle <= 55.0, "best upwind angle was %.0f degrees" % angle)


func test_square_rigger_cannot_point_as_high_as_a_sloop() -> void:
	var brig := _best_upwind_angle(ShipDesign.brig())
	var sloop := _best_upwind_angle(ShipDesign.sloop())
	check(brig >= 55.0 and brig <= 75.0, "brig's best upwind angle was %.0f degrees" % brig)
	check(brig > sloop, "brig pointed at %.0f degrees, sloop at %.0f" % [brig, sloop])


func test_nothing_sails_straight_into_the_wind() -> void:
	for design in [ShipDesign.sloop(), ShipDesign.brig()]:
		var speed := Polar.steady_speed(design, 0.0, WIND_SPEED)
		check(speed < 0.0, "%s made %.2f meters per second head to wind" % [design.display_name, speed])


func test_square_rigger_is_driven_backward_when_taken_aback() -> void:
	var speed := Polar.steady_speed(ShipDesign.brig(), 25.0, WIND_SPEED)
	check(speed < -0.5, "brig at 25 degrees made %.2f meters per second" % speed)


func test_reaching_is_faster_than_running() -> void:
	for design in [ShipDesign.sloop(), ShipDesign.brig()]:
		var reaching := Polar.steady_speed(design, 100.0, WIND_SPEED)
		var running := Polar.steady_speed(design, 180.0, WIND_SPEED)
		check(reaching > running * 1.2,
			"%s reached at %.2f and ran at %.2f" % [design.display_name, reaching, running])


func test_hull_speed_is_a_wall() -> void:
	# Heavy hulls can be driven a little past hull speed, but once they're there, even a lot
	# more wind buys very little.
	for design in [ShipDesign.sloop(), ShipDesign.brig()]:
		var gale := Polar.steady_speed(design, 100.0, 15.0)
		var storm := Polar.steady_speed(design, 100.0, 22.0)
		check(gale < design.hull_speed() * 1.3,
			"%s made %.2f against a hull speed of %.2f in a gale" % [
				design.display_name, gale, design.hull_speed()])
		check(storm < gale * 1.1,
			"%s went from %.2f in a gale to %.2f in a storm" % [design.display_name, gale, storm])


func test_a_stopped_ship_cannot_steer() -> void:
	var ship := Ship.new(ShipDesign.sloop())
	ship.sail_ordered = 0.0
	ship.sail_set = 0.0
	ship.rudder = 1.0
	for index in 300:
		ship.step(1.0 / 60.0, Vector2.ZERO)
	check(absf(ship.heading) < 0.001, "heading changed by %.4f radians" % ship.heading)


func test_a_moving_ship_turns_with_the_rudder() -> void:
	var ship := Ship.new(ShipDesign.sloop())
	ship.sail_ordered = 0.0
	ship.sail_set = 0.0
	ship.velocity = ship.forward() * 4.0
	ship.rudder = 1.0
	for index in 360:
		ship.step(1.0 / 60.0, Vector2.ZERO)
	check(ship.heading > 0.25, "turned to starboard by only %.3f radians" % ship.heading)


func test_easing_the_sheet_too_far_luffs_the_sail() -> void:
	var wind := Wind.steady(WIND_SPEED, 0.0)
	var ship := Ship.new(ShipDesign.sloop())
	ship.heading = deg_to_rad(45.0 - 90.0)
	ship.velocity = ship.forward() * 3.0
	ship.automatic_trim = false
	ship.sheet = 1.0
	for index in 180:
		ship.step(1.0 / 60.0, wind.velocity_at(ship.position))
	check(ship.luffing > 0.9, "luffing was %.2f with the sheet eased right out" % ship.luffing)


func test_more_wind_heels_the_ship_further() -> void:
	var heels: Array[float] = []
	for wind_speed in [5.0, 10.0]:
		var wind := Wind.steady(wind_speed, 0.0)
		var ship := Ship.new(ShipDesign.sloop())
		ship.heading = deg_to_rad(60.0 - 90.0)
		for index in 600:
			ship.step(1.0 / 60.0, wind.velocity_at(ship.position))
			ship.heading = deg_to_rad(60.0 - 90.0)
			ship.yaw_rate = 0.0
		heels.append(absf(ship.heel))
	check(heels[1] > heels[0] * 1.5, "heel went from %.3f to %.3f radians" % heels)


func test_a_new_ship_starts_with_its_sails_drawing() -> void:
	# Wind over the starboard side, so the sails belong on the port side.
	var wind := Wind.steady(WIND_SPEED, 90.0)
	for design in [ShipDesign.sloop(), ShipDesign.brig()]:
		var ship := Ship.new(design)
		ship.heading = deg_to_rad(0.0 - 90.0)
		ship.velocity = ship.forward() * 2.0
		ship.trim_instantly(wind.velocity_at(ship.position))
		ship.step(1.0 / 60.0, wind.velocity_at(ship.position))
		check(ship.sail_angle < 0.0, "%s's sails started on the windward side" % design.display_name)
		check(not ship.aback, "%s started taken aback" % design.display_name)


func _off_the_wind_after(design: ShipDesign, seconds: float, backing: bool) -> float:
	var wind := Wind.steady(WIND_SPEED, 0.0)
	var ship := Ship.new(design)
	ship.heading = deg_to_rad(15.0 - 90.0)
	ship.backing_headsails = backing
	for index in int(60 * seconds):
		ship.step(1.0 / 60.0, wind.velocity_at(ship.position))
	return rad_to_deg(absf(ship.wind_angle(wind.velocity_at(ship.position))))


func test_a_ship_stuck_in_irons_falls_off_slowly_on_its_own() -> void:
	for design in [ShipDesign.sloop(), ShipDesign.brig()]:
		var angle := _off_the_wind_after(design, 60.0, false)
		check(angle > 16.0, "%s didn't fall off at all: %.0f degrees" % [design.display_name, angle])


func test_backing_the_headsails_gets_a_ship_out_of_irons() -> void:
	for design in [ShipDesign.sloop(), ShipDesign.brig()]:
		var angle := _off_the_wind_after(design, 30.0, true)
		check(angle > 50.0,
			"%s was only %.0f degrees off the wind after 30 seconds" % [design.display_name, angle])
