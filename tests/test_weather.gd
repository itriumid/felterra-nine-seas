extends TestCase
## Squalls and gales: wind that rises and falls, and sail that has to come in for it.


func _gale_over(voyage: Voyage, where: Vector2) -> void:
	voyage.monsoon.weather.cells = [{
		"kind": Weather.Kind.GALE, "center": where, "velocity": Vector2.ZERO, "radius": 150000.0,
		"push": 14.0, "direction": voyage.monsoon.base_velocity_at(where).normalized(),
		"age": 18.0 * 3600.0, "life": 36.0 * 3600.0,
	}]


func test_a_gale_raises_the_wind_inside_it_and_not_outside() -> void:
	var voyage := Voyage.new()
	var heart := Chart.position_of(-5.0, 110.0)
	_gale_over(voyage, heart)
	var calm := voyage.monsoon.base_velocity_at(heart).length()
	check(voyage.monsoon.velocity_at(heart).length() > calm + 10.0, "the gale added under ten meters a second at its heart")
	var far := Chart.position_of(-5.0, 114.0)
	check(voyage.monsoon.velocity_at(far).is_equal_approx(voyage.monsoon.base_velocity_at(far)), "the gale reached 440 kilometers off")
	check(voyage.monsoon.weather.conditions_at(heart) == "Gale", "the heart of a gale reads %s" % voyage.monsoon.weather.conditions_at(heart))


func test_squalls_come_and_go() -> void:
	var voyage := Voyage.new()
	var born := 0
	var seen := {}
	for hour in 24 * 4:
		voyage.monsoon.weather.advance(3600.0, voyage.monsoon, voyage.chart, voyage.random)
		for cell in voyage.monsoon.weather.cells:
			if not seen.has(cell):
				seen[cell] = true
				born += 1
	check(born > 20, "only %d squalls in four days across the whole chart" % born)
	check(voyage.monsoon.weather.cells.size() < born, "no squall ever blew itself out")


func test_full_sail_in_a_gale_strains_the_rigging_and_reefed_does_not() -> void:
	var voyage := Voyage.new()
	var heart := Chart.position_of(-5.0, 110.0)
	_gale_over(voyage, heart)
	var wind := voyage.monsoon.velocity_at(heart)
	var reckless := MapShip.new(ShipDesign.sloop())
	var careful := MapShip.new(ShipDesign.sloop())
	careful.sail_set = careful.prudent_sail(wind.length())
	for ship in [reckless, careful]:
		ship.position = heart
		ship.heading = (-wind).orthogonal().angle()
		for minute in 120:
			ship.step(60.0, wind, voyage.chart)
	check(reckless.rigging < 0.9, "two hours of full sail in a gale left the rigging at %.2f" % reckless.rigging)
	check(careful.rigging == 1.0, "reefed down, the rigging still suffered: %.2f" % careful.rigging)
	check(careful.sail_set < 1.0, "a gale and still all plain sail is prudent")


func test_captains_reef_in_a_gale() -> void:
	var voyage := Voyage.new()
	var merchant: Captain
	for captain in voyage.captains:
		if captain.role == Captain.Role.MERCHANT:
			merchant = captain
			break
	merchant.in_port_for = 0.0
	merchant.ship.position = Chart.position_of(-5.0, 110.0)
	merchant.route = [Chart.position_of(-5.0, 112.0)]
	_gale_over(voyage, merchant.ship.position)
	merchant.update(120.0, voyage.monsoon.velocity_at(merchant.ship.position), voyage)
	check(merchant.ship.sail_set < 1.0, "a merchant carried all plain sail into a gale")


func test_the_crew_shortens_sail_on_a_course_but_never_sets_more() -> void:
	var voyage := Voyage.new()
	voyage.undock()
	voyage.ship.position = Chart.position_of(-5.0, 110.0)
	_gale_over(voyage, voyage.ship.position)
	voyage.set_course(Chart.position_of(-5.0, 111.0))
	voyage.advance(120.0)
	var reefed := voyage.ship.sail_set
	check(reefed < 1.0, "the crew sailed into a gale under all plain sail")
	voyage.monsoon.weather.cells.clear()
	voyage.advance(120.0)
	check(voyage.ship.sail_set == reefed, "the crew set more sail than ordered once the gale passed")


func test_heeling_too_far_strains_the_rigging() -> void:
	var voyage := Voyage.new()
	voyage.undock()
	var merchant := Captain.new(Captain.Role.MERCHANT, ShipDesign.sloop())
	merchant.route = [voyage.port_named("Semarang").position]
	merchant.destination = voyage.port_named("Semarang")
	voyage.captains = [merchant]
	voyage.ship.position = Chart.position_of(-5.6, 107.2)
	merchant.ship.position = voyage.ship.position + Vector2(0.0, -500.0)
	voyage.chase(merchant)
	voyage.advance(1.0)
	var bubble := voyage.bubble
	bubble.wind = Wind.steady(20.0, 0.0)
	bubble.player.heading = deg_to_rad(80.0 - 90.0)
	bubble.player.sail_ordered = 1.0
	bubble.player.sail_set = 1.0
	for step in 60 * 30:
		bubble.step()
	check(bubble.player.rigging < 1.0, "thirty seconds on her ear in 40 knots and the rigging is untouched")
