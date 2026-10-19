extends TestCase
## Ports: markets that answer supply and demand, a tavern, a shipyard, wages, and cargo that
## weighs the ship down.


func test_the_game_starts_moored_in_batavia() -> void:
	var voyage := Voyage.new()
	check(voyage.docked.get("name", "") == "Batavia", "started at %s" % voyage.docked.get("name", "sea"))


func test_prices_climb_with_distance_from_where_goods_are_produced() -> void:
	var voyage := Voyage.new()
	var makassar: float = voyage.markets["Makassar"].price("spices")
	var batavia: float = voyage.markets["Batavia"].price("spices")
	var aceh: float = voyage.markets["Aceh"].price("spices")
	check(makassar < batavia and batavia < aceh, "spices: Makassar %d, Batavia %d, Aceh %d" % [makassar, batavia, aceh])


func test_neighboring_ports_keep_close_prices() -> void:
	# Banten and Batavia are a few hours apart: no fortune in hopping between them.
	var voyage := Voyage.new()
	for id in Goods.ids():
		var banten: float = voyage.markets["Banten"].price(id)
		var batavia: float = voyage.markets["Batavia"].price(id)
		check(absf(banten - batavia) < maxf(banten, batavia) * 0.25, "%s: Banten %d, Batavia %d" % [id, banten, batavia])


func test_buying_raises_the_price_and_selling_lowers_it() -> void:
	var voyage := Voyage.new()
	var market: Market = voyage.markets["Batavia"]
	var before := market.price("sugar")
	check(voyage.buy("sugar", 10) == "", "couldn't buy sugar")
	check(market.price("sugar") > before, "buying didn't raise the price")
	check(voyage.ship.hold.get("sugar", 0) == 10, "the sugar isn't in the hold")
	var after_buying := market.price("sugar")
	check(voyage.sell("sugar", 10) == "", "couldn't sell sugar")
	check(market.price("sugar") < after_buying, "selling didn't lower the price")


func test_a_round_trip_in_one_port_loses_money() -> void:
	# Buying and selling straight back costs the margin both ways: no money for nothing.
	var voyage := Voyage.new()
	var before := voyage.purse
	check(voyage.buy("rice", 10) == "", "couldn't buy the rice")
	check(voyage.sell("rice", 10) == "", "couldn't sell the rice back")
	check(voyage.purse < before, "made money buying and selling the same rice")


func test_stocks_recover_over_the_days() -> void:
	var voyage := Voyage.new()
	var market: Market = voyage.markets["Batavia"]
	voyage.buy("sugar", 20)
	var low: float = market.stock["sugar"]
	market.advance(30.0 * Calendar.SECONDS_PER_DAY)
	check(market.stock["sugar"] > low + 15.0, "sugar only recovered to %.1f tons" % market.stock["sugar"])


func test_trading_respects_the_hold_and_the_purse() -> void:
	var voyage := Voyage.new()
	check(voyage.buy("timber", 31) != "", "bought more than a sloop holds")
	voyage.purse = 10.0
	check(voyage.buy("porcelain", 1) != "", "bought porcelain with ten reals")
	check(voyage.sell("tin", 1) != "", "sold tin we don't have")


func test_cargo_slows_the_ship() -> void:
	var speeds: Array[float] = []
	for tons in [0, 30]:
		var ship := MapShip.new(ShipDesign.sloop())
		ship.position = Chart.position_of(-5.0, 110.0)
		ship.heading = Vector2.RIGHT.angle()
		if tons > 0:
			ship.hold["rice"] = tons
		var chart := Chart.new()
		for minute in 120:
			ship.step(60.0, Wind.bearing_to_direction(180.0) * 7.0, chart)
		speeds.append(ship.speed)
	check(speeds[1] < speeds[0] * 0.97, "a full hold made %.2f against %.2f empty" % [speeds[1], speeds[0]])


func test_a_loaded_ship_heels_less() -> void:
	var heels: Array[float] = []
	for cargo in [0.0, 30000.0]:
		var ship := Ship.new(ShipDesign.sloop())
		ship.cargo_mass = cargo
		ship.heading = deg_to_rad(60.0 - 90.0)
		var wind := Wind.steady(8.0, 0.0)
		for step in 600:
			ship.step(1.0 / 60.0, wind.velocity_at(ship.position))
			ship.heading = deg_to_rad(60.0 - 90.0)
			ship.yaw_rate = 0.0
		heels.append(absf(ship.heel))
	check(heels[1] < heels[0], "loaded heel %.3f against empty %.3f" % [heels[1], heels[0]])


func test_hiring_costs_a_bounty_and_fills_berths() -> void:
	var voyage := Voyage.new()
	var before := voyage.purse
	var crew := voyage.ship.crew
	check(voyage.hire(5) == "", "couldn't hire five")
	check(voyage.ship.crew == crew + 5, "crew is %d" % voyage.ship.crew)
	check(is_equal_approx(voyage.purse, before - 5 * Voyage.SIGNING_BOUNTY), "the bounty wasn't paid")
	check(voyage.hire(200) != "", "berthed two hundred on a sloop")


func test_short_handed_ships_cannot_carry_full_sail() -> void:
	var ship := MapShip.new(ShipDesign.sloop())
	ship.crew = 4
	check(is_equal_approx(ship.handled_sail(), 0.5), "four sailors handle %.2f of a sloop's sail" % ship.handled_sail())


func test_unpaid_sailors_desert() -> void:
	var voyage := Voyage.new()
	voyage.purse = 0.0
	var crew := voyage.ship.crew
	for hour in 24 * 3:
		voyage.advance(3600.0)
	check(voyage.ship.crew < crew, "nobody deserted after three unpaid days")


func test_barnacles_slow_the_ship_and_scraping_cleans_it() -> void:
	var voyage := Voyage.new()
	voyage.ship.fouling = 1.0
	check(voyage.scrape() == "", "couldn't haul out and scrape")
	check(voyage.ship.fouling == 0.0, "the hull is still fouled")
	var clean := MapShip.new(ShipDesign.sloop())
	var fouled := MapShip.new(ShipDesign.sloop())
	fouled.fouling = 1.0
	var chart := Chart.new()
	for ship in [clean, fouled]:
		ship.position = Chart.position_of(-5.0, 110.0)
		ship.heading = Vector2.RIGHT.angle()
	for minute in 120:
		clean.step(60.0, Wind.bearing_to_direction(180.0) * 7.0, chart)
		fouled.fouling = 1.0
		fouled.step(60.0, Wind.bearing_to_direction(180.0) * 7.0, chart)
	check(fouled.speed < clean.speed * 0.9, "fouled %.2f, clean %.2f" % [fouled.speed, clean.speed])


func test_trading_in_for_a_brig_keeps_the_cargo_and_crew() -> void:
	var voyage := Voyage.new()
	voyage.purse = 20000.0
	voyage.buy("rice", 10)
	var crew := voyage.ship.crew
	var spent := voyage.purse
	check(voyage.buy_ship(ShipDesign.brig()) == "", "couldn't buy a brig")
	check(voyage.ship.design.id == "brig", "still a %s" % voyage.ship.design.id)
	check(voyage.ship.hold.get("rice", 0) == 10, "the rice was lost")
	check(voyage.ship.crew == crew, "the crew changed")
	check(spent - voyage.purse < ShipDesign.brig().price, "no trade-in for the sloop")


func test_furling_sail_by_a_port_moors_the_ship() -> void:
	var voyage := Voyage.new()
	voyage.undock()
	for hour in 2:
		voyage.advance(600.0)
	check(voyage.docked.is_empty(), "cast off and moored again at once")
	voyage.ship.position = voyage.port_named("Semarang").position + Vector2(1000.0, -1000.0)
	voyage.ship.sail_set = 0.0
	for minute in 60:
		voyage.advance(60.0)
	check(voyage.docked.get("name", "") == "Semarang", "didn't moor at Semarang")


func test_collisions_damage_hulls() -> void:
	var voyage := Voyage.new()
	var merchant := Captain.new(Captain.Role.MERCHANT, ShipDesign.sloop())
	merchant.route = [voyage.port_named("Semarang").position]
	merchant.destination = voyage.port_named("Semarang")
	voyage.captains = [merchant]
	voyage.undock()
	voyage.ship.position = Chart.position_of(-5.6, 107.2)
	merchant.ship.position = voyage.ship.position + Vector2(0.0, -500.0)
	voyage.chase(merchant)
	voyage.advance(1.0)
	var bubble := voyage.bubble
	bubble.player.position = Vector2.ZERO
	bubble.ships[0].position = Vector2(25.0, 0.0)
	bubble.player.heading = 0.0
	bubble.player.velocity = Vector2(3.0, 0.0)
	bubble.ships[0].velocity = Vector2(-3.0, 0.0)
	# 25 meters between centers, hulls meeting about 7 meters in: a second or two at 6 a second.
	for step in 180:
		bubble.player.position += bubble.player.velocity * Bubble.STEP
		bubble.ships[0].position += bubble.ships[0].velocity * Bubble.STEP
		bubble._collide()
	check(not bubble.collisions.is_empty(), "the hulls never met")
	check(bubble.player.hull < 0.9 and bubble.player.hull > 0.6, "head on at 3 meters a second left the hull at %.2f" % bubble.player.hull)


func test_sailing_to_a_port_ends_moored_there() -> void:
	var voyage := Voyage.new()
	check(voyage.sail_to_port(voyage.port_named("Cirebon")), "no course to Cirebon")
	check(voyage.docked.is_empty(), "still moored in Batavia after setting a course")
	for step in 24 * 30 * 6:
		voyage.advance(120.0)
		if not voyage.docked.is_empty():
			break
	check(voyage.docked.get("name", "") == "Cirebon", "moored at %s" % voyage.docked.get("name", "sea"))
