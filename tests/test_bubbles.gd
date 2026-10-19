extends TestCase
## Battle bubbles: meeting a ship hands both to the full physics; collisions push hulls apart
## the way momentum says; ships part and go back to the map where they ended up.


func _voyage_near_merchant(distance: float) -> Array:
	var voyage := Voyage.new()
	voyage.captains.clear()
	var merchant := Captain.new(Captain.Role.MERCHANT, ShipDesign.brig())
	merchant.destination = voyage.port_named("Semarang")
	merchant.route = [voyage.port_named("Semarang").position]
	voyage.captains.append(merchant)
	# Put the player out at sea, clear of the coast at Batavia.
	voyage.ship.position = Chart.position_of(-5.6, 107.2)
	merchant.ship.position = voyage.ship.position + Vector2(0.0, -distance)
	# Both under way, as ships that meet at sea are.
	voyage.ship.speed = 3.0
	merchant.ship.speed = 3.0
	return [voyage, merchant]


func test_chasing_a_ship_opens_a_bubble_when_close() -> void:
	# A sloop catches a brig to windward, where it's far faster; running before the wind, the
	# brig would pull away, as square-riggers did. So the merchant is bound for Palembang, up
	# into the January monsoon.
	var setup := _voyage_near_merchant(20000.0)
	var voyage: Voyage = setup[0]
	var merchant: Captain = setup[1]
	merchant.destination = voyage.port_named("Palembang")
	merchant.route = voyage.navigation.route(merchant.ship.position, merchant.destination.position)
	voyage.chase(merchant)
	for step in 24 * 30:
		voyage.advance(120.0)
		if voyage.bubble != null:
			break
	check(voyage.bubble != null, "never met the merchant")
	if voyage.bubble != null:
		check(voyage.bubble.ships.size() == 1, "the bubble has %d other ships" % voyage.bubble.ships.size())
		check((setup[1] as Captain).in_bubble, "the merchant is still sailing the map")


func test_the_world_runs_on_while_the_player_is_in_a_bubble() -> void:
	var setup := _voyage_near_merchant(1000.0)
	var voyage: Voyage = setup[0]
	voyage.chase(setup[1])
	voyage.advance(1.0)
	check(voyage.bubble != null, "no bubble at a kilometer")
	var frozen := voyage.ship.position
	var before := voyage.calendar.seconds
	voyage.advance(3600.0)
	check(voyage.calendar.seconds > before, "the world clock stopped")
	check(voyage.ship.position == frozen, "the player's map ship moved while in the bubble")


func test_a_merchant_runs_from_the_player() -> void:
	var setup := _voyage_near_merchant(800.0)
	var voyage: Voyage = setup[0]
	voyage.chase(setup[1])
	voyage.advance(1.0)
	var bubble := voyage.bubble
	var away := bubble.ships[0].position - bubble.player.position
	for step in 60 * 60:
		bubble.step()
	var heading := bubble.ships[0].forward()
	check(heading.dot(away.normalized()) > 0.0, "the merchant is sailing toward the player")


func test_colliding_hulls_push_apart_and_keep_their_momentum() -> void:
	var setup := _voyage_near_merchant(1000.0)
	var voyage: Voyage = setup[0]
	voyage.chase(setup[1])
	voyage.advance(1.0)
	var bubble := voyage.bubble
	var other := bubble.ships[0]
	# Head on, 30 meters apart, closing at 8 meters a second; nobody steering.
	bubble.player.position = Vector2.ZERO
	other.position = bubble.player.position + Vector2(30.0, 0.0)
	bubble.player.heading = 0.0
	other.heading = PI
	bubble.player.velocity = Vector2(4.0, 0.0)
	other.velocity = Vector2(-4.0, 0.0)
	var momentum_before := bubble.player.velocity * bubble.player.mass() + other.velocity * other.mass()
	bubble._collide()
	for step in 120:
		bubble.player.position += bubble.player.velocity * Bubble.STEP
		other.position += other.velocity * Bubble.STEP
		bubble._collide()
	var momentum_after := bubble.player.velocity * bubble.player.mass() + other.velocity * other.mass()
	check(not bubble.collisions.is_empty(), "the hulls never touched")
	check((momentum_after - momentum_before).length() < momentum_before.length() * 0.01 + 1.0,
		"momentum went from %s to %s" % [momentum_before, momentum_after])
	var gap := bubble.player.position.distance_to(other.position)
	check(gap >= (bubble.player.design.beam + other.design.beam) / 2.0 - 0.5, "hulls still overlap: %.1f meters apart" % gap)
	check(bubble.player.velocity.x < 4.0, "the sloop didn't slow down")


func test_the_bubble_closes_when_ships_part() -> void:
	var setup := _voyage_near_merchant(1000.0)
	var voyage: Voyage = setup[0]
	voyage.chase(setup[1])
	voyage.advance(1.0)
	var merchant: Captain = setup[1]
	voyage.bubble.ships[0].position = voyage.bubble.player.position + Vector2(0.0, -Bubble.CLOSE_RANGE - 100.0)
	var where := voyage.bubble.origin + voyage.bubble.ships[0].position
	voyage.step_bubble()
	check(voyage.bubble == null, "the bubble stayed open")
	check(not merchant.in_bubble, "the merchant is still in a bubble")
	check(merchant.ship.position.distance_to(where) < 50.0, "the merchant went back somewhere else")


func test_no_bubble_opens_when_the_quarry_has_made_port() -> void:
	var setup := _voyage_near_merchant(1000.0)
	var voyage: Voyage = setup[0]
	var merchant: Captain = setup[1]
	merchant.in_port_for = 3600.0
	voyage.chase(merchant)
	voyage.advance(1.0)
	check(voyage.bubble == null, "a bubble opened around a ship in port")


func test_ships_in_a_bubble_really_move() -> void:
	# Far out on the chart, a world position can't change by a few centimeters; bubbles keep
	# their own origin so ships move at any speed.
	var setup := _voyage_near_merchant(1000.0)
	var voyage: Voyage = setup[0]
	voyage.chase(setup[1])
	voyage.advance(1.0)
	var bubble := voyage.bubble
	var start := bubble.player.position
	var other_start := bubble.ships[0].position
	for step in 60 * 60:
		bubble.step()
	check(bubble.player.position.distance_to(start) > 100.0,
		"the player moved %.1f meters in a minute" % bubble.player.position.distance_to(start))
	check(bubble.ships[0].position.distance_to(other_start) > 100.0,
		"the merchant moved %.1f meters in a minute" % bubble.ships[0].position.distance_to(other_start))
