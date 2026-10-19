extends TestCase
## Broadsides, shot, sinking, and what the world makes of it.


func _in_bubble(role := Captain.Role.MERCHANT, their_guns := 2) -> Voyage:
	var voyage := Voyage.new()
	voyage.undock()
	var other := Captain.new(role, ShipDesign.sloop())
	other.ship.guns = their_guns
	other.destination = voyage.port_named("Semarang")
	other.route = [voyage.port_named("Semarang").position]
	voyage.captains = [other]
	voyage.ship.guns = 10
	voyage.ship.crew = 40
	voyage.ship.position = Chart.position_of(-5.6, 107.2)
	other.ship.position = voyage.ship.position + Vector2(0.0, -500.0)
	voyage.chase(other)
	voyage.advance(1.0)
	# The player heading north, the other ship 150 meters off the starboard beam, both still.
	var bubble := voyage.bubble
	bubble.player.position = Vector2.ZERO
	bubble.player.heading = -PI / 2.0
	bubble.player.velocity = Vector2.ZERO
	bubble.player.sail_ordered = 0.0
	bubble.player.sail_set = 0.0
	bubble.ships[0].position = Vector2(150.0, 0.0)
	bubble.ships[0].heading = -PI / 2.0
	bubble.ships[0].velocity = Vector2.ZERO
	bubble.ships[0].sail_ordered = 0.0
	bubble.ships[0].sail_set = 0.0
	return voyage


func _let_balls_fly(bubble: Bubble) -> void:
	for step in 120:
		bubble.gunnery.advance(Bubble.STEP, bubble.all_ships(), bubble._hit)


func test_a_broadside_at_close_range_holes_the_hull() -> void:
	var voyage := _in_bubble()
	var bubble := voyage.bubble
	check(voyage.bubble.fire() == "", "couldn't fire")
	_let_balls_fly(bubble)
	check(bubble.ships[0].hull < 0.97, "five balls at 150 meters left the hull at %.3f" % bubble.ships[0].hull)


func test_guns_must_reload() -> void:
	var voyage := _in_bubble()
	check(voyage.bubble.fire() == "", "couldn't fire")
	check(voyage.bubble.fire() != "", "fired the same broadside twice at once")


func test_short_hands_reload_slowly() -> void:
	var voyage := _in_bubble()
	voyage.ship.crew = 5
	voyage.bubble.fire()
	var side := Gunnery.side_toward(voyage.bubble.player, voyage.bubble.ships[0].position)
	var left := voyage.bubble.gunnery.reload_left(voyage.bubble.player, side)
	check(left > Gunnery.RELOAD_SECONDS * 3.0, "five hands reload five guns in %.0f seconds" % left)


func test_chain_shot_cuts_rigging_and_grape_kills_crew() -> void:
	var voyage := _in_bubble()
	var bubble := voyage.bubble
	bubble.gunnery.cycle_shot(bubble.player)
	bubble.fire()
	_let_balls_fly(bubble)
	check(bubble.ships[0].rigging < 1.0, "chain shot left the rigging whole")
	check(bubble.ships[0].hull == 1.0, "chain shot holed the hull")
	var crew := voyage.captains[0].ship.crew
	bubble.gunnery.cycle_shot(bubble.player)
	bubble.gunnery.reloading.clear()
	bubble.fire()
	_let_balls_fly(bubble)
	check(voyage.captains[0].ship.crew < crew, "grapeshot at 150 meters killed nobody")


func test_shot_falls_short_beyond_its_range() -> void:
	var voyage := _in_bubble()
	var bubble := voyage.bubble
	bubble.ships[0].position = Vector2(1500.0, 0.0)
	bubble.fire()
	for step in 600:
		bubble.gunnery.advance(Bubble.STEP, bubble.all_ships(), bubble._hit)
	check(bubble.ships[0].hull == 1.0, "round shot hit at a kilometer and a half")


func test_a_ship_with_no_hull_sinks_and_leaves_the_world() -> void:
	var voyage := _in_bubble()
	var merchant := voyage.captains[0]
	voyage.bubble.ships[0].hull = 0.0
	voyage.step_bubble()
	check(not merchant in voyage.captains, "the sunk merchant still sails")
	check(voyage.honor < 0.0, "sinking a merchant cost no honor")


func test_firing_on_a_merchant_makes_it_fight_back() -> void:
	var voyage := _in_bubble()
	voyage.bubble.fire()
	check(voyage.captains[0].hostile, "the merchant didn't take it personally")
	voyage.step_bubble()
	check(voyage.honor < 0.0, "attacking a merchant cost no honor")


func test_a_hostile_navy_ship_turns_its_broadside_on_you() -> void:
	var voyage := _in_bubble(Captain.Role.NAVY, 16)
	var bubble := voyage.bubble
	voyage.captains[0].hostile = true
	bubble.ships[0].position = Vector2(0.0, -250.0)
	bubble.ships[0].sail_ordered = 1.0
	bubble.ships[0].sail_set = 1.0
	bubble.ships[0].velocity = Vector2(0.0, -3.0)
	var hull := bubble.player.hull
	for step in 60 * 90:
		bubble.step()
	check(bubble.player.hull < hull, "ninety seconds near a hostile navy brig and not a scratch")


func test_renown_titles_and_the_navy_hunt() -> void:
	var voyage := Voyage.new()
	check(voyage.reputation_title() == "Unknown", "a new captain is %s" % voyage.reputation_title())
	for capture in 3:
		voyage.reckon("captured_merchant")
	check(voyage.reputation_title() == "Known", "three captures make %s" % voyage.reputation_title())
	voyage.reckon("sank_merchant")
	voyage.reckon("sank_merchant")
	check(voyage.hunted(), "two sinkings and still not hunted")
	check(voyage.reputation_title() == "Feared", "a sinker of merchants is %s" % voyage.reputation_title())
	check(voyage.fear() > 1.3, "fear is only %.2f" % voyage.fear())


func test_the_navy_comes_for_a_captain_without_honor() -> void:
	# Out at sea: moored in a port, a ship is safe from the hunt.
	var voyage := Voyage.new()
	voyage.undock()
	voyage.ship.position = Chart.position_of(-5.6, 107.2)
	voyage.honor = -50.0
	var navy: Captain
	for captain in voyage.captains:
		if captain.role == Captain.Role.NAVY:
			navy = captain
	navy.in_port_for = 0.0
	navy.ship.position = voyage.ship.position + Vector2(20000.0, -20000.0)
	voyage.ship.sail_set = 0.0
	for step in 24 * 30:
		voyage.advance(120.0)
		if voyage.bubble != null:
			break
	check(navy.hunting, "the navy didn't take up the hunt")
	check(voyage.bubble != null, "the navy never caught up")


func test_honor_is_slowly_forgotten() -> void:
	var voyage := Voyage.new()
	voyage.honor = -30.0
	for day in 30:
		voyage.advance(Calendar.SECONDS_PER_DAY)
	check(voyage.honor > -30.0 and voyage.honor < -20.0, "after a month honor is %.1f" % voyage.honor)


func test_a_sunk_player_is_landed_at_the_nearest_port() -> void:
	var voyage := _in_bubble()
	voyage.ship.hold = {"spices": 10}
	voyage.bubble.player.hull = 0.0
	voyage.step_bubble()
	check(voyage.bubble == null, "still in the bubble")
	check(not voyage.docked.is_empty(), "not landed anywhere")
	check(voyage.ship.cargo_tons() == 0, "the cargo survived the sinking")
	check(voyage.ship.guns == 0, "the guns survived the sinking")


func test_guns_weigh_the_ship_down() -> void:
	var light := MapShip.new(ShipDesign.sloop())
	var armed := MapShip.new(ShipDesign.sloop())
	armed.guns = 10
	check(armed.cargo_load() > light.cargo_load() + 0.25, "ten guns load a sloop by %.2f" % (armed.cargo_load() - light.cargo_load()))


func test_buying_guns_at_the_shipyard() -> void:
	var voyage := Voyage.new()
	var guns := voyage.ship.guns
	check(voyage.buy_guns(2) == "", "couldn't buy two guns")
	check(voyage.ship.guns == guns + 2, "has %d guns" % voyage.ship.guns)
	check(voyage.buy_guns(20) != "", "mounted more guns than ports")


func test_guns_are_trained_on_a_target_off_the_beam() -> void:
	# A ship 20 meters ahead of abeam is still in the arc a gun can be trained through.
	var voyage := _in_bubble()
	var bubble := voyage.bubble
	bubble.ships[0].position = Vector2(140.0, -20.0)
	bubble.fire()
	_let_balls_fly(bubble)
	check(bubble.ships[0].hull < 0.99, "a broadside at a ship 20 meters ahead of abeam missed entirely")
