extends TestCase
## Pirates: they prey on merchants, the navy hunts them, they come for a weak player, and
## fighting them is honest work with a bounty.


func _pirate_near(voyage: Voyage, offset: Vector2) -> Captain:
	var pirate := Captain.new(Captain.Role.PIRATE, ShipDesign.sloop())
	pirate.lair = voyage.lairs[0]
	pirate.ship.position = voyage.ship.position + offset
	pirate.destination = {}
	pirate.loiter_for = 48.0 * 3600.0
	voyage.captains.append(pirate)
	return pirate


func _at_sea(voyage: Voyage) -> void:
	voyage.undock()
	voyage.captains.clear()
	voyage.ship.position = Chart.position_of(-5.6, 107.2)
	voyage.ship.sail_set = 0.0


func test_pirates_take_merchants_they_catch() -> void:
	var voyage := Voyage.new()
	_at_sea(voyage)
	voyage.ship.position = Chart.position_of(-4.0, 108.5)
	var merchant := Captain.new(Captain.Role.MERCHANT, ShipDesign.brig())
	merchant.ship.position = Chart.position_of(-5.6, 107.2)
	merchant.ship.hold = {"porcelain": 40}
	merchant.destination = voyage.port_named("Semarang")
	merchant.route = voyage.navigation.route(merchant.ship.position, merchant.destination.position)
	voyage.captains.append(merchant)
	var pirate := _pirate_near(voyage, Vector2.ZERO)
	pirate.ship.position = merchant.ship.position + Vector2(8000.0, 0.0)
	for step in 24 * 30:
		voyage.advance(120.0)
		if merchant.struck:
			break
	check(merchant.struck, "the pirate never took the merchant")
	check(pirate.ship.hold.get("porcelain", 0) > 0, "the pirate took no porcelain")


func test_the_navy_hunts_down_pirates() -> void:
	var voyage := Voyage.new()
	_at_sea(voyage)
	voyage.ship.position = Chart.position_of(-4.0, 108.5)
	var navy := Captain.new(Captain.Role.NAVY, ShipDesign.brig())
	navy.ship.position = Chart.position_of(-5.6, 107.2)
	navy.patrol = [voyage.port_named("Batavia"), voyage.port_named("Semarang")]
	navy.destination = navy.patrol[1]
	navy.route = voyage.navigation.route(navy.ship.position, navy.destination.position)
	voyage.captains.append(navy)
	var pirate := _pirate_near(voyage, Vector2.ZERO)
	pirate.ship.position = navy.ship.position + Vector2(10000.0, 5000.0)
	for step in 24 * 30:
		voyage.advance(120.0)
		if not pirate in voyage.captains:
			break
	check(not pirate in voyage.captains, "the navy never took the pirate")


func test_pirates_come_for_a_weak_player_but_not_a_strong_one() -> void:
	var voyage := Voyage.new()
	_at_sea(voyage)
	voyage.ship.crew = 12
	var pirate := _pirate_near(voyage, Vector2(15000.0, 0.0))
	voyage.advance(120.0)
	check(pirate.hunting, "sixty pirates let a crew of twelve sail by")
	var strong := Voyage.new()
	_at_sea(strong)
	strong.ship.crew = 70
	var wary := _pirate_near(strong, Vector2(15000.0, 0.0))
	strong.advance(120.0)
	check(not wary.hunting, "sixty pirates went after seventy")


func test_pirates_board_and_strip_a_weak_player() -> void:
	var voyage := Voyage.new()
	_at_sea(voyage)
	voyage.ship.crew = 10
	voyage.ship.hold = {"spices": 8}
	var pirate := _pirate_near(voyage, Vector2(0.0, -500.0))
	pirate.hunting = true
	voyage.advance(1.0)
	var bubble := voyage.bubble
	check(bubble != null, "no bubble with a hunting pirate half a kilometer off")
	if bubble == null:
		return
	bubble.ships[0].position = bubble.player.position + bubble.player.starboard() * 9.0
	bubble.ships[0].heading = bubble.player.heading
	bubble.ships[0].velocity = bubble.player.velocity
	for step in 60 * 60:
		bubble.step()
		if bubble.boarding == Bubble.Boarding.PLUNDERED:
			break
	check(bubble.boarding == Bubble.Boarding.PLUNDERED, "the pirates never boarded and won")
	check(voyage.ship.hold.is_empty(), "the pirates left the spices")


func test_a_strong_crew_beats_off_pirate_boarders() -> void:
	# By the square law, defenders with their deck's edge (1.2) beat off boarders if they number
	# more than about 0.91 of them: sixty holds against sixty.
	var voyage := Voyage.new()
	_at_sea(voyage)
	voyage.ship.crew = 60
	var pirate := _pirate_near(voyage, Vector2(0.0, -500.0))
	pirate.hunting = true
	voyage.advance(1.0)
	var bubble := voyage.bubble
	bubble._pirates_board(0)
	for step in 60 * 120:
		bubble.step()
		if bubble.boarding != Bubble.Boarding.FIGHTING:
			break
	check(bubble.boarding == Bubble.Boarding.BEATEN_OFF, "sixty didn't beat off sixty boarders from their own deck")


func test_taking_a_pirate_earns_honor_and_a_bounty() -> void:
	var voyage := Voyage.new()
	var honor := voyage.honor
	voyage.reckon("captured_pirate")
	check(voyage.honor > honor, "taking a pirate earned no honor")
	var purse := voyage.purse
	voyage.dock(voyage.port_named("Semarang"))
	check(voyage.purse >= purse + Voyage.BOUNTY_TAKEN, "no bounty paid in port")


func test_lost_pirates_are_replaced() -> void:
	var voyage := Voyage.new()
	for captain in voyage.captains.duplicate():
		if captain.role == Captain.Role.PIRATE:
			voyage.remove_captain(captain)
	for day in 6:
		voyage.advance(Calendar.SECONDS_PER_DAY)
	var pirates := voyage.captains.filter(func(captain: Captain) -> bool: return captain.role == Captain.Role.PIRATE)
	check(pirates.size() == 1, "%d pirates after six days" % pirates.size())



func test_a_pirate_to_windward_runs_down_and_boards() -> void:
	# The weather gauge: upwind, the pirate chooses the moment. (To leeward, it can't close.)
	var voyage := Voyage.new()
	_at_sea(voyage)
	voyage.ship.crew = 15
	var pirate := _pirate_near(voyage, Vector2(0.0, -500.0))
	pirate.hunting = true
	voyage.advance(1.0)
	var bubble := voyage.bubble
	var windward := -bubble.wind.velocity_at(bubble.player.position).normalized()
	bubble.ships[0].position = bubble.player.position + windward * 80.0
	bubble.ships[0].heading = bubble.player.heading
	bubble.ships[0].velocity = bubble.player.velocity
	var boarded := false
	for step in 60 * 180:
		bubble.step()
		if bubble.grappled >= 0 or bubble.boarding != Bubble.Boarding.NONE:
			boarded = true
			break
	check(boarded, "a pirate to windward never came alongside in three minutes")
