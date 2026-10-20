class_name Bubble
extends RefCounted
## A battle bubble: the patch of sea around ships that have met, where time runs close to real
## and the full sailing physics takes over from the speed polars.
##
## The world outside keeps its own clock (an hour a second) and doesn't wait; inside, ships are
## steered by hand and by their captains, and they can collide. When the ships draw apart the
## bubble closes and each goes back to the world where it ended up.

## Game seconds per real second inside. The same for every bubble, so every player in one
## shares a clock.
const TIME_SCALE := 4
const STEP := 1.0 / 60.0
## Ships this close open a bubble; once every ship is this far from the player, it closes.
const OPEN_RANGE := 3000.0
const CLOSE_RANGE := 6000.0
## How bouncy a collision between hulls is: wooden ships barely bounce.
const RESTITUTION := 0.2
## Hull lost per joule of impact per kilogram of ship: two ships meeting at 3 meters a second
## head on each lose a fifth of their hull; a gentle bump alongside, almost nothing.
const DAMAGE_PER_SPECIFIC_ENERGY := 0.022

var chart: Chart
## The world position of the bubble's own origin. Ships inside are positioned relative to it:
## a ship's 32-bit position far out on the chart can only change in steps of about 12
## centimeters, coarser than a ship moves in one physics step, so world coordinates would leave
## every ship standing still.
var origin := Vector2.ZERO
var wind := Wind.new()
var player: Ship
## The player's ship on the world map, frozen while it's in here.
var player_map_ship: MapShip
var captains: Array[Captain] = []
var ships: Array[Ship] = []
## Seconds of game time since the bubble opened.
var time := 0.0

## How a boarding stands: fighting; taken by the player; the player's boarders thrown back; the
## player's ship stripped by pirate boarders; pirate boarders beaten off.
enum Boarding { NONE, FIGHTING, TAKEN, REPELLED, PLUNDERED, BEATEN_OFF }

## Grapples reach this far between hulls, and only hold if the ships are moving together.
const GRAPPLE_REACH := 6.0
const BOARDING_SPEED := 1.5
## Lanchester's square law: each side loses this share of the other side's fighters every
## second, so numbers count twice over and a big crew wins fast and cheaply.
const FIGHTING_RATE := 0.04
## Defenders fight from their own deck, behind their own bulwarks.
const DEFENDERS_EDGE := 1.2
## Merchant sailors weren't paid to die for the owners' cargo: outnumbered this badly, they
## strike their colors at once.
const SURRENDER_ODDS := 2.0
## Boarders who fall below this share of those who went over give up and cut the grapples.
const GIVE_UP_SHARE := 0.4
## Pirates expected the gallows: they struck only when hopelessly outnumbered.
const PIRATE_SURRENDER_ODDS := 3.0
## A pirate grapples the player when it outnumbers the player's crew this many times over; and
## a player's crew facing boarders this many times their number strikes rather than die.
const PIRATE_BOARDING_ODDS := 1.5
const PLAYER_SURRENDER_ODDS := 3.0
const KNOTS_PER_METER_PER_SECOND := 1.943844

## The guns of every ship in here, and the balls in flight.
var gunnery := Gunnery.new()
## How badly outnumbered a merchant crew must be to strike at once; less for a feared captain.
var surrender_odds := SURRENDER_ODDS
## What the player did in here that the world will remember: event names for the voyage's
## reckoning of renown and honor, taken and cleared by the voyage.
var deeds: Array[String] = []
## Ships sunk in here, by captain; ships taken as prizes, to sail in company with the player;
## and whether the player's own went down.
var sunk: Array[Captain] = []
var prizes_taken: Array[Captain] = []
var player_sunk := false
## Heeling past this, in radians (about 29 degrees), strains masts and rigging; the further
## past, the harder.
const SAFE_HEEL := 0.5
const HEEL_STRAIN := 0.03
## Within this range a navy ship turns to bring its broadside to bear; closer than this it
## bears away a little, to keep its guns clear and not be boarded.
const BROADSIDE_RANGE := 350.0
const CLOSEST_RANGE := 90.0

## The ship the player has grappled, by index into ships, or -1; and how the fight is going.
var grappled := -1
var boarding := Boarding.NONE
## True when the player's crew went over; false when pirates boarded the player.
var player_boarding := true
var _boarders_at_start := 0
var _attackers := 0.0
var _defenders := 0.0
var _offset := Vector2.ZERO
var _heading_offset := 0.0
## Impacts so far, each {"ships": [a, b], "speed": closing speed in meters per second}.
var collisions: Array[Dictionary] = []


## Opens a bubble around the player's ship and the given captains' ships, taking each one's
## speed and heading from the map, in the monsoon blowing there.
static func around(voyage: Voyage, met: Array[Captain]) -> Bubble:
	var bubble := Bubble.new()
	bubble.chart = voyage.chart
	bubble.origin = voyage.ship.position
	var monsoon_wind := voyage.monsoon.velocity_at(voyage.ship.position)
	bubble.wind.base_bearing = Wind.direction_to_bearing(-monsoon_wind)
	bubble.wind.base_speed = maxf(monsoon_wind.length(), 1.0)
	bubble.player_map_ship = voyage.ship
	bubble.player = bubble._full_ship(voyage.ship)
	for captain in met:
		captain.in_bubble = true
		if captain.role == Captain.Role.PIRATE and not captain.struck:
			captain.hostile = true
		bubble.captains.append(captain)
		bubble.ships.append(bubble._full_ship(captain.ship))
	return bubble


func _full_ship(map_ship: MapShip) -> Ship:
	var ship := Ship.new(map_ship.design)
	ship.position = map_ship.position - origin
	ship.heading = map_ship.heading
	ship.velocity = map_ship.forward() * map_ship.speed
	ship.sail_ordered = map_ship.sail_set
	ship.sail_set = map_ship.sail_set
	ship.cargo_mass = map_ship.carried_mass()
	ship.fouling = map_ship.fouling
	ship.hull = map_ship.hull
	ship.rigging = map_ship.rigging
	ship.trim_instantly(wind.velocity_at(ship.position))
	return ship


func all_ships() -> Array[Ship]:
	var everyone: Array[Ship] = [player]
	everyone.append_array(ships)
	return everyone


func step() -> void:
	time += STEP
	wind.advance(STEP)
	for index in ships.size():
		if index != grappled:
			_steer(captains[index], ships[index])
	_pirates_close_to_board()
	for ship in all_ships():
		var before := ship.position
		ship.step(STEP, wind.velocity_at(ship.position))
		if chart.is_land(origin + ship.position):
			# Hard aground: the hull stops where the water ends.
			ship.position = before
			ship.velocity = Vector2.ZERO
			ship.yaw_rate = 0.0
		if absf(ship.heel) > SAFE_HEEL:
			ship.rigging = maxf(ship.rigging - (absf(ship.heel) - SAFE_HEEL) * HEEL_STRAIN * STEP, 0.1)
	if grappled >= 0:
		_hold_alongside()
		_fight()
	_collide()
	gunnery.advance(STEP, all_ships(), _hit)
	for index in ships.size():
		_lay_guns(index)
	_sink_the_sunk()


## The ship the player could grapple right now, by index, or -1: within reach of the hull and
## moving with the player.
func boardable() -> int:
	for index in ships.size():
		var other := ships[index]
		if captains[index].struck:
			continue
		var reach := (player.design.beam + other.design.beam) / 2.0 + GRAPPLE_REACH
		var closest := INF
		for point_a in _hull_circles(player):
			for point_b in _hull_circles(other):
				closest = minf(closest, point_a.distance_to(point_b))
		if closest <= reach and (player.velocity - other.velocity).length() <= BOARDING_SPEED:
			return index
	return -1


## Why the player can't board yet, or an empty string if they can.
func boarding_hint() -> String:
	if boardable() >= 0:
		return ""
	var nearest := INF
	var speed := 0.0
	for index in ships.size():
		var distance := ships[index].position.distance_to(player.position)
		if distance < nearest:
			nearest = distance
			speed = (player.velocity - ships[index].velocity).length()
	if nearest > 60.0:
		return "Close to within a few meters to board"
	return "Match her speed to board: closing at %.1f knots" % (speed * KNOTS_PER_METER_PER_SECOND)


## Throws the grapples and sends the boarders over. Merchants outnumbered badly enough strike
## at once.
func board() -> String:
	var index := boardable()
	if index < 0:
		return boarding_hint()
	grappled = index
	var other := ships[index]
	_offset = (other.position - player.position).rotated(-player.heading)
	_heading_offset = other.heading - player.heading
	# Everyone who can fight goes over or stands to repel them; nobody's minding the sails.
	player.sail_ordered = 0.0
	other.sail_ordered = 0.0
	_attackers = player_map_ship.crew
	_defenders = captains[index].ship.crew
	_boarders_at_start = player_map_ship.crew
	player_boarding = true
	boarding = Boarding.FIGHTING
	_provoke(captains[index])
	if _strikes(captains[index]):
		_take(captains[index])
	return ""


## Pirates throw their grapples aboard the player's ship.
func _pirates_board(index: int) -> void:
	grappled = index
	var other := ships[index]
	_offset = (other.position - player.position).rotated(-player.heading)
	_heading_offset = other.heading - player.heading
	player.sail_ordered = 0.0
	other.sail_ordered = 0.0
	_attackers = captains[index].ship.crew
	_defenders = player_map_ship.crew
	_boarders_at_start = captains[index].ship.crew
	player_boarding = false
	boarding = Boarding.FIGHTING


## Whether the defenders of a boarded ship strike their colors: merchants outnumbered two to
## one, pirates only three to one, navy crews never.
func _strikes(captain: Captain) -> bool:
	match captain.role:
		Captain.Role.MERCHANT:
			return _attackers >= _defenders * surrender_odds
		Captain.Role.PIRATE:
			return _attackers >= _defenders * PIRATE_SURRENDER_ODDS
	return false


## How many of the player's sailors a prize crew for the ship alongside would take: her minimum,
## or as many as the player can spare while keeping their own ship sailable. Zero if none.
func prize_crew_size() -> int:
	if prize() == null:
		return 0
	var spare := player_map_ship.crew - player_map_ship.design.crew_minimum
	return clampi(captains[grappled].ship.design.crew_minimum, 0, maxi(spare, 0))


## Puts a prize crew aboard the ship that has struck and takes her: her own crew are set adrift
## in their boats, and she sails in company with the player from now on.
func take_as_prize() -> String:
	if prize() == null:
		return "There's no ship that has struck to you"
	var crew := prize_crew_size()
	if crew < 4:
		return "You can't spare a prize crew without leaving your own ship short"
	var index := grappled
	var captain := captains[index]
	player_map_ship.crew -= crew
	captain.ship.crew = crew
	captain.consort = true
	captain.hostile = false
	captain.hunting = false
	captain.quarry = null
	_return(ships[index], captain.ship)
	captain.in_bubble = false
	prizes_taken.append(captain)
	ships.remove_at(index)
	captains.remove_at(index)
	grappled = -1
	boarding = Boarding.NONE
	deeds.append("took_prize")
	return ""


## Cuts the grapples. After a capture, the plundered ship goes on its way.
func cast_off() -> void:
	grappled = -1
	boarding = Boarding.NONE


## The plundered ship's hold, while it lies alongside.
func prize() -> MapShip:
	if grappled < 0 or boarding != Boarding.TAKEN or not player_boarding:
		return null
	return captains[grappled].ship


## Fires the player's broadside on whichever side faces the nearest other ship, laid for its
## range. Returns why not, if it can't.
func fire() -> String:
	if grappled >= 0:
		return "Not while you're lashed alongside"
	if player_map_ship.guns < 2:
		return "You have no broadside to fire"
	var target := _nearest_to_player()
	var side := 1
	var aim := player.position + player.starboard() * 300.0
	if target >= 0:
		side = Gunnery.side_toward(player, ships[target].position)
		aim = ships[target].position
	if gunnery.reload_left(player, side) > 0.0:
		return "The %s guns are still loading" % ("starboard" if side > 0 else "port")
	gunnery.fire(player, player_map_ship, side, aim)
	for index in ships.size():
		if Gunnery.bears(player, side, ships[index].position):
			_provoke(captains[index])
	return ""


func _nearest_to_player() -> int:
	var nearest := -1
	var nearest_distance := INF
	for index in ships.size():
		var distance := ships[index].position.distance_to(player.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = index
	return nearest


## The first time the player turns on a ship, it fights back, and the world remembers.
func _provoke(captain: Captain) -> void:
	if captain.hostile:
		return
	captain.hostile = true
	deeds.append(_deed("attacked", captain))


## A deed's name for what was done to a ship of the captain's kind, as the voyage reckons them.
static func _deed(action: String, captain: Captain) -> String:
	return "%s_%s" % [action, ["merchant", "navy", "pirate"][captain.role]]


func _take(captain: Captain) -> void:
	boarding = Boarding.TAKEN
	captain.struck = true
	captain.hostile = false
	deeds.append(_deed("captured", captain))


## A captain's gunners fire whenever a loaded side bears on the player, if they're at war with
## the player: the navy always is once honor is gone, a merchant once it's been attacked.
func _lay_guns(index: int) -> void:
	var captain := captains[index]
	var ship := ships[index]
	if not captain.hostile or captain.struck or index == grappled:
		return
	var distance := ship.position.distance_to(player.position)
	if distance > Gunnery.RANGE[Gunnery.Shot.ROUND] * 0.8:
		return
	var side := Gunnery.side_toward(ship, player.position)
	if Gunnery.bears(ship, side, player.position):
		gunnery.fire(ship, captain.ship, side, player.position)


## What one ball does to the ship it strikes. Heavier ships take less from each.
func _hit(target: Ship, kind: int) -> void:
	var map_ship := _map_ship_of(target)
	var scale := Gunnery.REFERENCE_MASS / target.mass()
	match kind:
		Gunnery.Shot.ROUND:
			target.hull = maxf(target.hull - Gunnery.HULL_PER_ROUND_SHOT * scale, 0.0)
			if gunnery.random.randf() < Gunnery.CREW_KILLED_PER_ROUND_SHOT:
				map_ship.crew = maxi(map_ship.crew - 1, 0)
		Gunnery.Shot.CHAIN:
			target.rigging = maxf(target.rigging - Gunnery.RIGGING_PER_CHAIN_SHOT * sqrt(scale), 0.0)
		Gunnery.Shot.GRAPE:
			if gunnery.random.randf() < Gunnery.CREW_KILLED_PER_GRAPE:
				map_ship.crew = maxi(map_ship.crew - 1, 0)


func _map_ship_of(ship: Ship) -> MapShip:
	if ship == player:
		return player_map_ship
	return captains[ships.find(ship)].ship


## Ships with no hull left go down, with everything in them.
func _sink_the_sunk() -> void:
	if player.hull <= 0.0:
		player_sunk = true
	for index in range(ships.size() - 1, -1, -1):
		if ships[index].hull > 0.0:
			continue
		var captain := captains[index]
		deeds.append(_deed("sank", captain))
		sunk.append(captain)
		gunnery.events.append({"kind": "sinking", "position": ships[index].position, "direction": ships[index].forward()})
		if index == grappled:
			grappled = -1
			boarding = Boarding.NONE
		elif index < grappled:
			grappled -= 1
		ships.remove_at(index)
		captains.remove_at(index)


func fighters() -> Vector2i:
	return Vector2i(ceili(_attackers), ceili(_defenders))


## The lashed ships move as one.
func _hold_alongside() -> void:
	var other := ships[grappled]
	other.position = player.position + _offset.rotated(player.heading)
	other.heading = player.heading + _heading_offset
	other.velocity = player.velocity
	other.yaw_rate = player.yaw_rate


func _fight() -> void:
	if boarding != Boarding.FIGHTING:
		return
	var attackers_before := _attackers
	_attackers = maxf(_attackers - FIGHTING_RATE * _defenders * DEFENDERS_EDGE * STEP, 0.0)
	_defenders = maxf(_defenders - FIGHTING_RATE * attackers_before * STEP, 0.0)
	var captain := captains[grappled]
	if player_boarding:
		player_map_ship.crew = ceili(_attackers)
		captain.ship.crew = ceili(_defenders)
		if _defenders < 0.5 or _strikes(captain):
			_take(captain)
		elif _attackers < _boarders_at_start * GIVE_UP_SHARE:
			boarding = Boarding.REPELLED
			grappled = -1
	else:
		captain.ship.crew = ceili(_attackers)
		player_map_ship.crew = ceili(_defenders)
		if _defenders < 0.5 or _attackers >= _defenders * PLAYER_SURRENDER_ODDS:
			_plundered_by(captain)
		elif _attackers < _boarders_at_start * GIVE_UP_SHARE:
			boarding = Boarding.BEATEN_OFF
			grappled = -1


## The player's crew has struck to pirate boarders: the pirates strip the hold and go.
func _plundered_by(pirate: Captain) -> void:
	for id in player_map_ship.hold.keys():
		var taking := mini(player_map_ship.hold[id], pirate.ship.free_tons())
		if taking <= 0:
			continue
		player_map_ship.hold[id] -= taking
		if player_map_ship.hold[id] == 0:
			player_map_ship.hold.erase(id)
		pirate.ship.hold[id] = pirate.ship.hold.get(id, 0) + taking
	pirate.hostile = false
	pirate.hunting = false
	boarding = Boarding.PLUNDERED
	grappled = -1
	deeds.append("plundered_by_pirates")


func should_close() -> bool:
	if player_sunk:
		return true
	for ship in ships:
		if ship.position.distance_to(player.position) < CLOSE_RANGE:
			return false
	return true


## Hands every ship back to the world map where it ended up.
func close() -> void:
	_return(player, player_map_ship)
	for index in ships.size():
		_return(ships[index], captains[index].ship)
		captains[index].in_bubble = false
		captains[index].replan = true


func _return(ship: Ship, map_ship: MapShip) -> void:
	map_ship.position = origin + ship.position
	map_ship.heading = ship.heading
	map_ship.speed = maxf(ship.forward_speed(), 0.0)
	map_ship.sail_set = ship.sail_ordered
	map_ship.hull = ship.hull
	map_ship.rigging = ship.rigging


## Pirates who outnumber the player throw their grapples as soon as they're alongside.
func _pirates_close_to_board() -> void:
	if grappled >= 0:
		return
	for index in ships.size():
		var captain := captains[index]
		if captain.role == Captain.Role.PIRATE and captain.hostile and not captain.struck \
				and _outnumbers(captain) and _alongside(index):
			_pirates_board(index)
			return


## Whether a pirate that means to board is closing on the player.
func pirates_closing() -> bool:
	for index in ships.size():
		var captain := captains[index]
		if captain.role == Captain.Role.PIRATE and captain.hostile and not captain.struck and _outnumbers(captain) \
				and ships[index].position.distance_to(player.position) < 150.0:
			return true
	return false


func _outnumbers(captain: Captain) -> bool:
	return captain.ship.crew >= player_map_ship.crew * PIRATE_BOARDING_ODDS


## Whether a ship is within grappling reach of the player and moving with her.
func _alongside(index: int) -> bool:
	var other := ships[index]
	var reach := (player.design.beam + other.design.beam) / 2.0 + GRAPPLE_REACH
	for point_a in _hull_circles(player):
		for point_b in _hull_circles(other):
			if point_a.distance_to(point_b) <= reach:
				return (player.velocity - other.velocity).length() <= BOARDING_SPEED
	return false


## A captain's hands on the helm. Merchants run from the player. The navy, and pirates who can't
## outnumber the player, bring their broadside to bear; pirates who can, come alongside to board,
## easing sail if they're ahead. Never straight into the wind, and never onto the land.
func _steer(captain: Captain, ship: Ship) -> void:
	var to_player := player.position - ship.position
	var fighting := captain.role != Captain.Role.MERCHANT and captain.hostile and not captain.struck
	var wanted := to_player if fighting else -to_player
	if captain.role == Captain.Role.NAVY and not fighting:
		# A warship with no quarrel with the player holds her course.
		wanted = ship.forward()
	if fighting and captain.role == Captain.Role.PIRATE and _outnumbers(captain):
		# Lay her alongside: aim for a point a hull's width off the player's beam, then sail with
		# her, easing sail if ahead.
		var side := 1.0 if (ship.position - player.position).dot(player.starboard()) >= 0.0 else -1.0
		var alongside := player.position + player.starboard() * side * (player.design.beam + ship.design.beam)
		wanted = alongside - ship.position
		if to_player.length() < 60.0:
			wanted = player.forward() * 20.0 + wanted
			var ahead := (ship.position - player.position).dot(player.forward())
			ship.sail_ordered = 0.5 if ahead > 0.0 else 1.0
	elif fighting and to_player.length() < BROADSIDE_RANGE:
		# Bring the broadside to bear: put the player on the beam, on whichever side is nearer
		# the present heading; bear away a little when too close.
		var beam_a := to_player.rotated(PI / 2.0)
		var beam_b := to_player.rotated(-PI / 2.0)
		wanted = beam_a if absf(ship.forward().angle_to(beam_a)) < absf(ship.forward().angle_to(beam_b)) else beam_b
		if to_player.length() < CLOSEST_RANGE:
			wanted = wanted.rotated(-signf(wanted.angle_to(to_player)) * 0.4)
	var true_wind := wind.velocity_at(ship.position)
	var wind_from := -true_wind.normalized()
	var closest := deg_to_rad(Polar.best_upwind_angle(ship.design.id, true_wind.length()) + 5.0)
	var off_wind := wind_from.angle_to(wanted)
	if absf(off_wind) < closest:
		wanted = wind_from.rotated(closest * (signf(off_wind) if off_wind != 0.0 else 1.0))
	var lookout := ship.position + ship.forward() * maxf(ship.forward_speed() * 30.0, 100.0)
	if chart.signed_distance(origin + lookout) < 50.0:
		wanted = -wanted.rotated(0.5)
	var error := angle_difference(ship.heading, wanted.angle())
	# Steer toward the heading, easing off as the turn builds so the ship doesn't overshoot.
	ship.rudder = clampf(error * 2.0 - ship.yaw_rate * 4.0, -1.0, 1.0)


## Hulls as three circles along their length. Overlapping ships are pushed apart, and their
## closing speed along the line between them is exchanged by an impulse, which also turns them.
func _collide() -> void:
	var everyone := all_ships()
	for first in everyone.size():
		for second in range(first + 1, everyone.size()):
			_collide_pair(everyone[first], everyone[second])


func _collide_pair(a: Ship, b: Ship) -> void:
	if grappled >= 0 and ((a == player and b == ships[grappled]) or (b == player and a == ships[grappled])):
		return  # Lashed together: fenders and grapples hold them a hull's width apart.
	var reach := (a.design.length_overall + b.design.length_overall) / 2.0
	if a.position.distance_to(b.position) > reach:
		return
	for point_a in _hull_circles(a):
		for point_b in _hull_circles(b):
			var radius_a := a.design.beam / 2.0
			var radius_b := b.design.beam / 2.0
			var between: Vector2 = point_b - point_a
			var distance := between.length()
			if distance >= radius_a + radius_b or distance == 0.0:
				continue
			var normal := between / distance
			var mass_a := a.mass()
			var mass_b := b.mass()
			var overlap := radius_a + radius_b - distance
			a.position -= normal * overlap * mass_b / (mass_a + mass_b)
			b.position += normal * overlap * mass_a / (mass_a + mass_b)
			var closing := (a.velocity - b.velocity).dot(normal)
			if closing <= 0.0:
				continue
			var impulse := (1.0 + RESTITUTION) * closing / (1.0 / mass_a + 1.0 / mass_b)
			a.velocity -= normal * impulse / mass_a
			b.velocity += normal * impulse / mass_b
			a.yaw_rate -= (point_a - a.position).cross(normal * impulse) / _inertia(a)
			b.yaw_rate += (point_b - b.position).cross(normal * impulse) / _inertia(b)
			# Both hulls take the energy of the impact, shared by how much it shook each.
			var energy := 0.5 * closing * closing * mass_a * mass_b / (mass_a + mass_b)
			a.hull = maxf(a.hull - energy / mass_a * DAMAGE_PER_SPECIFIC_ENERGY, 0.0)
			b.hull = maxf(b.hull - energy / mass_b * DAMAGE_PER_SPECIFIC_ENERGY, 0.0)
			collisions.append({"ships": [a, b], "speed": closing})
			return


static func _hull_circles(ship: Ship) -> Array[Vector2]:
	var along := ship.forward() * ship.design.length_overall * 0.3
	return [ship.position + along, ship.position, ship.position - along]


static func _inertia(ship: Ship) -> float:
	return ship.mass() * pow(ship.design.length_overall / 4.0, 2.0)
