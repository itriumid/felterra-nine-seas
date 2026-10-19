extends TestCase
## The world map has to match the real Nusantara seas closely enough that a sailor who knows
## them recognizes them: land where the land is, and the monsoons blowing the right way.

var chart := Chart.new()


func _wind(latitude: float, longitude: float, day: int) -> Vector2:
	var calendar := Calendar.starting_on(day, 12.0)
	var monsoon := Monsoon.new(calendar)
	monsoon.gust_strength = 0.0
	return monsoon.velocity_at(Chart.position_of(latitude, longitude))


func _from(velocity: Vector2) -> float:
	return Wind.direction_to_bearing(-velocity)


func _near(bearing: float, expected: float, tolerance: float) -> bool:
	return absf(angle_difference(deg_to_rad(bearing), deg_to_rad(expected))) <= deg_to_rad(tolerance)


func test_land_and_sea_are_where_they_should_be() -> void:
	var land := {"central Java": [-7.4, 110.2], "Borneo": [0.5, 114.0], "Sumatra": [-1.0, 102.0]}
	var sea := {"Java Sea": [-5.0, 110.0], "Malacca Strait": [3.0, 100.5], "South China Sea": [5.0, 108.0]}
	for place: String in land:
		check(chart.is_land(Chart.position_of(land[place][0], land[place][1])), "%s is sea" % place)
	for place: String in sea:
		check(not chart.is_land(Chart.position_of(sea[place][0], sea[place][1])), "%s is land" % place)


func test_positions_round_trip_through_latitude_and_longitude() -> void:
	var position := Chart.position_of(-6.1, 106.8)
	check(is_equal_approx(Chart.latitude_at(position), -6.1), "latitude came back wrong")
	check(is_equal_approx(Chart.longitude_at(position), 106.8), "longitude came back wrong")


func test_every_port_is_on_water_by_the_coast() -> void:
	for port in Ports.on(chart):
		check(not chart.is_land(port.position), "%s is on land" % port.name)
		check(chart.coast_distance(port.position) <= 3, "%s is %d kilometers out to sea" % [
			port.name, chart.coast_distance(port.position)])


func test_the_northeast_monsoon_in_january() -> void:
	var north := _from(_wind(5.0, 108.0, 15))
	var south := _from(_wind(-5.0, 110.0, 15))
	check(_near(north, 45.0, 25.0), "South China Sea wind came from %.0f degrees" % north)
	check(_near(south, 300.0, 25.0), "Java Sea wind came from %.0f degrees" % south)


func test_the_monsoon_reverses_in_july() -> void:
	var north := _from(_wind(5.0, 108.0, 196))
	var south := _from(_wind(-5.0, 110.0, 196))
	check(_near(north, 225.0, 25.0), "South China Sea wind came from %.0f degrees" % north)
	check(_near(south, 120.0, 25.0), "Java Sea wind came from %.0f degrees" % south)


func test_the_change_between_monsoons_is_light() -> void:
	var settled := _wind(-5.0, 110.0, 15).length()
	var changing := _wind(-5.0, 110.0, 105).length()
	check(changing < settled * 0.6, "April wind was %.1f against January's %.1f" % [changing, settled])


func test_a_ship_runs_aground_instead_of_sailing_onto_land() -> void:
	var ship := MapShip.new(ShipDesign.sloop())
	# Just north of Java, heading due south at it, with a north wind behind.
	ship.position = Chart.position_of(-6.0, 110.5)
	ship.heading = Vector2.DOWN.angle()
	var wind := Wind.bearing_to_direction(180.0) * 7.0
	for hour in 48:
		ship.step(3600.0, wind, chart)
	check(ship.aground, "never ran aground")
	check(not chart.is_land(ship.position), "ended up on land")


func test_map_ships_sail_at_their_polar_speed() -> void:
	var ship := MapShip.new(ShipDesign.sloop())
	ship.position = Chart.position_of(-5.0, 110.0)
	ship.heading = Vector2.RIGHT.angle()
	# Wind from the north: a beam reach heading east.
	var wind := Wind.bearing_to_direction(180.0) * 7.0
	for minute in 60:
		ship.step(60.0, wind, chart)
	var expected := Polar.lookup("sloop", 90.0, 7.0)
	check(absf(ship.speed - expected) < expected * 0.05, "settled at %.2f, expected %.2f" % [ship.speed, expected])


func test_the_polar_table_matches_the_sailing_model() -> void:
	# Rebuild with tools/build_polars.gd whenever this fails.
	for sample in [["sloop", 90.0, 8.0], ["brig", 60.0, 6.0], ["sloop", 150.0, 11.0]]:
		var design: ShipDesign = ShipDesign.sloop() if sample[0] == "sloop" else ShipDesign.brig()
		var fresh := Polar.steady_speed(design, sample[1], sample[2], 200.0)
		var table := Polar.lookup(sample[0], sample[1], sample[2])
		check(absf(fresh - table) < 0.02, "%s at %.0f degrees in %.0f meters per second: model %.3f, table %.3f" % [
			sample[0], sample[1], sample[2], fresh, table])


func test_the_calendar_reads_like_a_date() -> void:
	check(Calendar.starting_on(14, 6.0).date_text() == "15 January, 06:00", "start date wrong")
	check(Calendar.starting_on(59, 13.5).date_text() == "1 March, 13:30", "1 March wrong")


func test_the_coast_is_smooth_and_continuous_between_chart_pixels() -> void:
	# Walking a straight line from sea to land, the chart's blended distance never changes faster
	# than the walk: there are no kilometer-wide steps from the chart's pixels. (The detail noise
	# on top is smooth by construction, and deliberately wanders.)
	var start := Chart.position_of(-5.5, 110.5)
	var finish := Chart.position_of(-7.0, 110.5)
	var previous := chart.smooth_distance(start)
	var crossings := 0
	for index in range(1, 1001):
		var point := start.lerp(finish, index / 1000.0)
		var here := chart.smooth_distance(point)
		var step := start.distance_to(finish) / 1000.0
		check(absf(here - previous) < step * 1.5 + 40.0, "the coast jumped %.0f meters" % absf(here - previous))
		if signf(here) != signf(previous):
			crossings += 1
		previous = here
	check(crossings >= 1, "never crossed the coast of Java")


func test_the_noise_matches_its_lattice() -> void:
	# The shader repeats this arithmetic in 32-bit unsigned integers; GDScript has to agree.
	check(is_equal_approx(Chart.smooth_noise(Vector2(3.0, 7.0)), Chart._lattice(3, 7)), "noise off its lattice point")
	var value := Chart._lattice(123456, 654321)
	check(value >= 0.0 and value <= 1.0, "lattice value %f out of range" % value)


func test_sail_set_is_the_throttle() -> void:
	var speeds: Array[float] = []
	for sail in [1.0, 0.5, 0.0]:
		var ship := MapShip.new(ShipDesign.sloop())
		ship.position = Chart.position_of(-5.0, 110.0)
		ship.heading = Vector2.RIGHT.angle()
		ship.sail_set = sail
		ship.speed = 3.0
		for minute in 120:
			ship.step(60.0, Wind.bearing_to_direction(180.0) * 7.0, chart)
		speeds.append(ship.speed)
	check(absf(speeds[1] / speeds[0] - sqrt(0.5)) < 0.02, "half sail made %.2f of full speed" % (speeds[1] / speeds[0]))
	check(speeds[2] < 0.05, "furled, the ship still made %.2f meters per second" % speeds[2])
