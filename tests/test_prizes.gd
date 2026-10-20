extends TestCase
## Prizes: a prize crew of the player's own sails a taken ship in company, into port, where she
## is sold or becomes the player's ship.

const TEST_PATH := "user://voyage_prizes_test.json"


## A voyage with a merchant brig that has just struck to the player.
func _struck_alongside(player_crew := 50) -> Voyage:
	var voyage := Voyage.new()
	voyage.undock()
	var merchant := Captain.new(Captain.Role.MERCHANT, ShipDesign.brig())
	merchant.ship.hold = {"porcelain": 30}
	merchant.destination = voyage.port_named("Semarang")
	merchant.route = [voyage.port_named("Semarang").position]
	voyage.captains = [merchant]
	voyage.ship.crew = player_crew
	voyage.ship.position = Chart.position_of(-5.6, 107.2)
	merchant.ship.position = voyage.ship.position + Vector2(0.0, -500.0)
	voyage.chase(merchant)
	voyage.advance(1.0)
	var bubble := voyage.bubble
	bubble.ships[0].position = bubble.player.position + bubble.player.starboard() * 9.0
	bubble.ships[0].heading = bubble.player.heading
	bubble.ships[0].velocity = bubble.player.velocity
	voyage.board()
	return voyage


func _take_prize(voyage: Voyage) -> String:
	var refusal := voyage.bubble.take_as_prize()
	voyage.step_bubble()
	return refusal


func test_a_prize_crew_takes_her() -> void:
	var voyage := _struck_alongside()
	check(_take_prize(voyage) == "", "couldn't take her as a prize")
	check(voyage.prizes.size() == 1, "%d prizes" % voyage.prizes.size())
	check(voyage.ship.crew == 50 - ShipDesign.brig().crew_minimum, "the player's crew is %d" % voyage.ship.crew)
	check(voyage.prizes[0].ship.crew == ShipDesign.brig().crew_minimum, "the prize crew is %d" % voyage.prizes[0].ship.crew)
	check(not voyage.prizes[0] in voyage.captains, "the prize still sails as a merchant")


func test_no_prize_crew_without_hands_to_spare() -> void:
	var voyage := _struck_alongside(10)
	check(_take_prize(voyage) != "", "took a prize with two sailors to spare")


func test_a_prize_keeps_company_and_comes_into_port() -> void:
	var voyage := _struck_alongside()
	_take_prize(voyage)
	while voyage.bubble != null:
		voyage.bubble.player.position += Vector2(0.0, -100.0)
		voyage.step_bubble()
	voyage.sail_to_port(voyage.port_named("Cirebon"))
	for step in 24 * 30 * 6:
		voyage.advance(120.0)
		if not voyage.docked.is_empty():
			break
	check(voyage.docked.get("name", "") == "Cirebon", "never made Cirebon")
	check(voyage.prizes[0].ship.position.distance_to(voyage.docked.position) < 1.0, "the prize didn't come in with us")
	check(voyage.prizes[0].brought_in, "the prize wasn't counted as brought in")


func test_selling_a_prize_pays_and_returns_the_crew() -> void:
	var voyage := _struck_alongside()
	_take_prize(voyage)
	voyage.bubble = null
	voyage.dock(voyage.port_named("Batavia"))
	voyage.prizes[0].ship.position = voyage.docked.position
	var purse := voyage.purse
	var crew := voyage.ship.crew
	var value := voyage.prize_value(voyage.prizes[0])
	check(voyage.sell_prize(0) == "", "couldn't sell the prize")
	check(is_equal_approx(voyage.purse, purse + value), "paid %.0f, not %.0f" % [voyage.purse - purse, value])
	check(value > ShipDesign.brig().price * 0.4, "a brig and thirty tons of porcelain fetched only %.0f" % value)
	check(voyage.ship.crew > crew, "the prize crew didn't come back aboard")


func test_moving_into_a_prize() -> void:
	var voyage := _struck_alongside()
	_take_prize(voyage)
	voyage.bubble = null
	voyage.dock(voyage.port_named("Batavia"))
	voyage.prizes[0].ship.position = voyage.docked.position
	check(voyage.make_prize_flagship(0) == "", "couldn't move into the prize")
	check(voyage.ship.design.id == "brig", "still in a %s" % voyage.ship.design.id)
	check(voyage.ship.hold.get("porcelain", 0) == 30, "her porcelain went missing")
	check(voyage.prizes.is_empty(), "she's still listed as a prize")


func test_prize_crews_draw_wages() -> void:
	var voyage := _struck_alongside()
	_take_prize(voyage)
	voyage.bubble = null
	var purse := voyage.purse
	voyage.advance(Calendar.SECONDS_PER_DAY)
	check(is_equal_approx(purse - voyage.purse, 50 * Voyage.WAGE), "a day's wages for fifty were %.2f" % (purse - voyage.purse))


func test_prizes_are_saved() -> void:
	var voyage := _struck_alongside()
	_take_prize(voyage)
	voyage.bubble = null
	check(SaveGame.save(voyage, TEST_PATH), "couldn't save")
	var loaded := SaveGame.load_voyage(TEST_PATH)
	check(loaded.prizes.size() == 1 and loaded.prizes[0].consort, "the prize wasn't saved")
	check(loaded.prizes[0].ship.hold.get("porcelain", 0) == 30, "her cargo wasn't saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))



func test_giving_a_course_after_a_fight_makes_sail() -> void:
	var voyage := Voyage.new()
	voyage.undock()
	voyage.ship.sail_set = 0.0
	voyage.set_course(Chart.position_of(-5.6, 108.6))
	check(voyage.ship.sail_set > 0.0, "set a course with every sail furled")
