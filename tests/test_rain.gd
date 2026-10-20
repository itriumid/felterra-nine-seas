extends TestCase
## Rain: it hides ships, so a hunted captain can slip away into a squall, and hunters give up the
## search.

const TEST_PATH := "user://test_rain.json"


func _squall_over(voyage: Voyage, where: Vector2) -> void:
	voyage.monsoon.weather.cells = [{
		"kind": Weather.Kind.SQUALL, "center": where, "velocity": Vector2.ZERO, "radius": 15000.0,
		"push": 1.0, "direction": Vector2.RIGHT, "age": 12.0 * 3600.0, "life": 24.0 * 3600.0,
	}]


func _at_sea(voyage: Voyage) -> void:
	voyage.undock()
	voyage.captains.clear()
	voyage.ship.position = Chart.position_of(-5.6, 107.2)
	voyage.ship.sail_set = 0.0


func _hunter(voyage: Voyage, role: Captain.Role, offset: Vector2) -> Captain:
	var hunter := Captain.new(role, ShipDesign.sloop() if role == Captain.Role.PIRATE else ShipDesign.brig())
	hunter.ship.position = voyage.ship.position + offset
	if role == Captain.Role.PIRATE:
		hunter.lair = voyage.lairs[0]
		hunter.loiter_for = 48.0 * 3600.0
	else:
		hunter.patrol = [voyage.port_named("Batavia"), voyage.port_named("Semarang")]
		hunter.destination = hunter.patrol[0]
	voyage.captains.append(hunter)
	return hunter


func test_rain_hides_ships_that_would_be_seen_in_clear_weather() -> void:
	var voyage := Voyage.new()
	var here := Chart.position_of(-5.6, 107.2)
	var there := here + Vector2(8000.0, 0.0)
	check(voyage.monsoon.weather.in_sight(here, there), "eight kilometers off unseen in clear weather")
	_squall_over(voyage, there)
	check(not voyage.monsoon.weather.in_sight(here, there), "seen eight kilometers off inside a squall")
	check(not voyage.monsoon.weather.in_sight(there, here), "a ship in the rain still saw out of it")
	check(voyage.monsoon.weather.in_sight(there, there + Vector2(500.0, 0.0)), "blind at half a kilometer in a squall")


func test_a_pirate_does_not_spot_a_player_in_the_rain() -> void:
	var voyage := Voyage.new()
	_at_sea(voyage)
	voyage.ship.crew = 12
	_squall_over(voyage, voyage.ship.position)
	var pirate := _hunter(voyage, Captain.Role.PIRATE, Vector2(10000.0, 0.0))
	voyage.advance(120.0)
	check(not pirate.hunting, "a pirate saw through a squall from ten kilometers")


func test_a_pirate_that_loses_the_player_in_a_squall_searches_and_gives_up() -> void:
	var voyage := Voyage.new()
	_at_sea(voyage)
	voyage.ship.crew = 12
	var pirate := _hunter(voyage, Captain.Role.PIRATE, Vector2(12000.0, 0.0))
	voyage.advance(120.0)
	check(pirate.hunting, "the pirate never came after a crew of twelve")
	# She slips into a squall eight kilometers off and lies there; the pirate goes to where she was.
	voyage.ship.position += Vector2(0.0, 8000.0)
	_squall_over(voyage, voyage.ship.position)
	for step in 12 * 30:
		voyage.advance(120.0)
		if not pirate.hunting:
			break
	check(not pirate.hunting, "the pirate never gave up the search")
	check(voyage.bubble == null, "the pirate found her in the rain")
	check(voyage.news.begins_with("You've lost"), "no word that she lost the pirate: %s" % voyage.news)
	voyage.monsoon.weather.cells.clear()
	voyage.advance(120.0)
	check(not pirate.hunting, "the pirate took up the hunt again the moment the rain cleared")


func test_a_hunter_keeps_after_a_player_out_of_sight_in_clear_weather() -> void:
	var voyage := Voyage.new()
	_at_sea(voyage)
	voyage.honor = Voyage.HUNTED_BELOW - 10.0
	var navy := _hunter(voyage, Captain.Role.NAVY, Vector2(60000.0, 0.0))
	for step in 30 * 12:
		# She runs west at four knots; word of her keeps the navy on her track.
		voyage.ship.position += Vector2(-2.0 * 120.0, 0.0)
		voyage.advance(120.0)
	check(navy.hunting, "the navy gave up a hunt out of sight in clear weather")
	check(navy.last_seen.distance_to(voyage.ship.position) < 1000.0, "the navy lost track of her in clear weather")


func test_the_navy_loses_a_player_in_the_rain() -> void:
	var voyage := Voyage.new()
	_at_sea(voyage)
	voyage.honor = Voyage.HUNTED_BELOW - 10.0
	var navy := _hunter(voyage, Captain.Role.NAVY, Vector2(15000.0, 0.0))
	voyage.advance(120.0)
	check(navy.hunting, "the navy never came after a captain without honor")
	voyage.ship.position += Vector2(0.0, 8000.0)
	_squall_over(voyage, voyage.ship.position)
	for step in 12 * 30:
		voyage.advance(120.0)
		if not navy.hunting:
			break
	check(not navy.hunting, "the navy never gave up the search")
	check(navy.given_up_for > 0.0, "the navy will take up the hunt again at once")


func test_a_lost_hunt_is_saved() -> void:
	var voyage := Voyage.new()
	_at_sea(voyage)
	var pirate := _hunter(voyage, Captain.Role.PIRATE, Vector2(12000.0, 0.0))
	pirate.hunting = true
	pirate.last_seen = voyage.ship.position + Vector2(100.0, 200.0)
	pirate.unseen_for = 900.0
	pirate.given_up_for = 3600.0
	check(SaveGame.save(voyage, TEST_PATH), "couldn't save")
	var copy: Captain = SaveGame.load_voyage(TEST_PATH).captains[0]
	DirAccess.remove_absolute(TEST_PATH)
	check(copy.last_seen.is_equal_approx(pirate.last_seen), "last seen came back as %s" % copy.last_seen)
	check(is_equal_approx(copy.unseen_for, 900.0) and is_equal_approx(copy.given_up_for, 3600.0), "the search clock wasn't saved")
