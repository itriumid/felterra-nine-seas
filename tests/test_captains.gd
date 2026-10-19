extends TestCase
## Computer-controlled ships have to get where they're going the way real ones did: around the
## land, through the straits, and against the wind by beating to windward.

static var _voyage: Voyage


func _shared_voyage() -> Voyage:
	# Building the chart and the navigation grid takes a moment; share them across tests.
	if _voyage == null:
		_voyage = Voyage.new()
	return _voyage


func _route_stays_at_sea(voyage: Voyage, from: String, to: String) -> Array[Vector2]:
	var start: Vector2 = voyage.port_named(from).position
	var finish: Vector2 = voyage.port_named(to).position
	var route := voyage.navigation.route(start, finish)
	check(not route.is_empty(), "no route from %s to %s" % [from, to])
	var previous := start
	for point in route:
		var steps := ceili(previous.distance_to(point) / 500.0)
		for index in range(1, steps):
			var sample := previous.lerp(point, float(index) / steps)
			# Ports sit right at the coast; only the open-sea part has to keep clear.
			if sample.distance_to(start) > 4000.0 and sample.distance_to(finish) > 4000.0:
				if voyage.chart.is_land(sample):
					check(false, "%s to %s crosses land near %.2f, %.2f" % [
						from, to, Chart.latitude_at(sample), Chart.longitude_at(sample)])
					return route
		previous = point
	return route


func test_routes_go_around_land() -> void:
	var voyage := _shared_voyage()
	_route_stays_at_sea(voyage, "Batavia", "Semarang")
	_route_stays_at_sea(voyage, "Batavia", "Makassar")


func test_routes_use_the_straits() -> void:
	# Batavia to Malacca runs up between Sumatra and Borneo and through the islands south of
	# Singapura; it must not detour around Borneo.
	var voyage := _shared_voyage()
	var route := _route_stays_at_sea(voyage, "Batavia", "Malacca")
	var length := 0.0
	var previous: Vector2 = voyage.port_named("Batavia").position
	for point in route:
		length += previous.distance_to(point)
		previous = point
	check(length < 1400000.0, "the route is %d kilometers long" % roundi(length / 1000.0))


func _sail(voyage: Voyage, from: String, to: String, day: int, days: int) -> Captain:
	voyage.calendar.seconds = day * Calendar.SECONDS_PER_DAY
	var captain := Captain.new(Captain.Role.MERCHANT, ShipDesign.sloop())
	captain.ship.position = voyage.port_named(from).position
	captain.sail_for(voyage.port_named(to), voyage.navigation)
	for step in days * 24 * 30:
		voyage.calendar.advance(120.0)
		captain.update(120.0, voyage.monsoon.velocity_at(captain.ship.position), voyage)
		check(not voyage.chart.is_land(captain.ship.position), "sailed onto land")
		if not captain.at_sea():
			break
	return captain


func test_a_merchant_runs_east_before_the_west_monsoon() -> void:
	var voyage := _shared_voyage()
	var captain := _sail(voyage, "Batavia", "Semarang", 15, 6)
	check(not captain.at_sea(), "didn't reach Semarang in 6 days of January")


func test_a_merchant_beats_east_against_the_east_monsoon() -> void:
	# In July the wind blows from the east-southeast along Java: straight on the nose.
	var voyage := _shared_voyage()
	var captain := _sail(voyage, "Batavia", "Semarang", 196, 20)
	check(not captain.at_sea(), "didn't reach Semarang in 20 days of July")
	check(captain.tacks_made >= 2, "only tacked %d times" % captain.tacks_made)


func test_traffic_fills_the_sea() -> void:
	var voyage := Voyage.new()
	for hour in 96:
		voyage.advance(3600.0)
	var at_sea := 0
	for captain in voyage.captains:
		if captain.at_sea():
			at_sea += 1
		check(not voyage.chart.is_land(captain.ship.position), "a %s ended up on land" % captain.role_name())
	check(at_sea >= 6, "only %d of %d ships at sea after four days" % [at_sea, voyage.captains.size()])


func test_clicking_a_point_sails_the_player_there() -> void:
	var voyage := Voyage.new()
	var target := Chart.position_of(-5.6, 108.6)
	check(voyage.set_course(target), "no course to the Java Sea")
	for step in 24 * 30 * 5:
		voyage.advance(120.0)
		if voyage.autopilot == null:
			break
	check(voyage.autopilot == null, "never arrived")
	check(voyage.ship.position.distance_to(target) < Captain.ARRIVAL_RADIUS * 1.5,
		"stopped %d meters short" % roundi(voyage.ship.position.distance_to(target)))


func test_taking_the_helm_cancels_the_course() -> void:
	var voyage := Voyage.new()
	voyage.set_course(Chart.position_of(-5.6, 108.6))
	voyage.take_helm()
	check(voyage.autopilot == null, "the crew kept sailing")


func test_the_crew_turns_at_the_helm_rate() -> void:
	var voyage := Voyage.new()
	voyage.ship.heading = 0.0
	# A point due west: the crew has to turn the ship right round.
	voyage.set_course(voyage.ship.position + Vector2(-60000.0, 0.0))
	var before := voyage.ship.heading
	voyage.advance(60.0)
	var turned := absf(angle_difference(before, voyage.ship.heading))
	check(turned <= Captain.TURN_RATE * 60.0 + 0.0001, "turned %.1f degrees in a game minute" % rad_to_deg(turned))
