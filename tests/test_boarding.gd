extends TestCase
## Boarding: getting alongside is the sailing; then numbers decide, as they did.


func _alongside(player_crew: int, their_crew: int, role := Captain.Role.MERCHANT) -> Voyage:
	var voyage := Voyage.new()
	voyage.undock()
	var other := Captain.new(role, ShipDesign.sloop())
	other.ship.crew = their_crew
	other.ship.hold = {"spices": 12, "rice": 20}
	other.destination = voyage.port_named("Semarang")
	other.route = [voyage.port_named("Semarang").position]
	voyage.captains = [other]
	voyage.ship.crew = player_crew
	voyage.ship.position = Chart.position_of(-5.6, 107.2)
	other.ship.position = voyage.ship.position + Vector2(0.0, -500.0)
	voyage.chase(other)
	voyage.advance(1.0)
	var bubble := voyage.bubble
	# Side by side, 7 meters apart, sailing together.
	bubble.player.position = Vector2.ZERO
	bubble.player.heading = 0.0
	bubble.player.velocity = Vector2(2.0, 0.0)
	bubble.ships[0].position = Vector2(0.0, 7.0)
	bubble.ships[0].heading = 0.0
	bubble.ships[0].velocity = Vector2(2.0, 0.0)
	return voyage


func test_you_can_only_board_alongside_and_moving_together() -> void:
	var voyage := _alongside(30, 8)
	var bubble := voyage.bubble
	bubble.ships[0].velocity = Vector2(6.0, 0.0)
	check(bubble.boardable() < 0, "boarded a ship passing at 4 meters a second")
	bubble.ships[0].velocity = Vector2(2.0, 0.0)
	bubble.ships[0].position = Vector2(0.0, 40.0)
	check(bubble.boardable() < 0, "boarded a ship 40 meters off")
	bubble.ships[0].position = Vector2(0.0, 7.0)
	check(bubble.boardable() == 0, "couldn't board alongside")


func test_outnumbered_merchants_strike_at_once() -> void:
	var voyage := _alongside(30, 8)
	check(voyage.board() == "", "couldn't board")
	check(voyage.bubble.boarding == Bubble.Boarding.TAKEN, "eight merchant sailors fought thirty")
	check(voyage.ship.crew == 30, "lost men taking a ship that struck")


func test_a_bigger_crew_wins_a_fight() -> void:
	var voyage := _alongside(30, 20)
	voyage.board()
	check(voyage.bubble.boarding == Bubble.Boarding.FIGHTING, "the fight never started")
	for step in 60 * 120:
		voyage.bubble.step()
		if voyage.bubble.boarding != Bubble.Boarding.FIGHTING:
			break
	check(voyage.bubble.boarding == Bubble.Boarding.TAKEN, "thirty didn't take a ship from twenty")
	check(voyage.ship.crew < 30 and voyage.ship.crew > 15, "won with %d of 30 left" % voyage.ship.crew)


func test_boarders_outnumbered_are_thrown_back() -> void:
	var voyage := _alongside(12, 25)
	voyage.board()
	for step in 60 * 120:
		voyage.bubble.step()
		if voyage.bubble.boarding != Bubble.Boarding.FIGHTING:
			break
	check(voyage.bubble.boarding == Bubble.Boarding.REPELLED, "twelve weren't thrown back by twenty-five")
	check(voyage.bubble.grappled < 0, "the grapples weren't cut")


func test_navy_crews_fight_rather_than_strike() -> void:
	var voyage := _alongside(30, 12, Captain.Role.NAVY)
	voyage.board()
	check(voyage.bubble.boarding == Bubble.Boarding.FIGHTING, "a navy crew struck without a fight")


func test_plunder_fills_the_hold_and_no_more() -> void:
	var voyage := _alongside(30, 8)
	voyage.board()
	check(voyage.plunder("spices", 99) == "", "couldn't take the spices")
	check(voyage.ship.hold.get("spices", 0) == 12, "took %d tons of spices" % voyage.ship.hold.get("spices", 0))
	check(voyage.plunder("rice", 20) != "", "fitted 32 tons in a 30-ton hold")
	check(voyage.plunder("rice", 18) == "", "couldn't take the rice that fits")
	check(voyage.ship.cargo_tons() == 30, "the hold has %d tons" % voyage.ship.cargo_tons())


func test_lashed_ships_move_as_one() -> void:
	var voyage := _alongside(30, 20)
	voyage.board()
	var bubble := voyage.bubble
	var gap := bubble.ships[0].position - bubble.player.position
	for step in 120:
		bubble.step()
	check((bubble.ships[0].position - bubble.player.position).distance_to(gap) < 0.5, "the lashed ships drifted apart")


func test_merchants_carry_cargo_between_ports() -> void:
	var voyage := Voyage.new()
	var loaded := 0
	for hour in 96:
		voyage.advance(3600.0)
		for captain in voyage.captains:
			if captain.role == Captain.Role.MERCHANT and captain.at_sea() and captain.ship.cargo_tons() > 0:
				loaded += 1
	check(loaded > 0, "no merchant ever sailed with cargo")
