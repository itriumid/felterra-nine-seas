class_name Captain
extends RefCounted
## A computer-controlled captain sailing a ship on the world map: merchants trading from port to
## port, navy ships patrolling between their stations, pirates prowling out of their lairs.
##
## The captain follows a route that keeps clear of land and sails it the way a real one would.
## When the next waypoint lies too close to the wind to sail straight at, the captain beats
## toward it: close-hauled at the ship's best upwind angle, tacking from one board to the other
## to stay within a lane around the course, and early if land comes up ahead.

enum Role { MERCHANT, NAVY, PIRATE }

## Meters from a waypoint where the captain may cut the corner to the next one, if the water
## between is clear; and how close counts as reaching it regardless.
const ARRIVAL_RADIUS := 3000.0
const REACHED_RADIUS := 300.0
## Hours a ship spends in port between voyages.
const PORT_HOURS := Vector2(12.0, 48.0)
## Meters ahead the captain looks for land while beating.
const LOOKOUT := 4000.0
## How fast a captain brings the ship onto a new heading, in radians per game second: ten
## degrees a game minute, near enough what a ship really manages, and the same rate as the
## player's helm, so a course change looks like someone turning the wheel and handing over the
## helm never jumps.
const TURN_RATE := deg_to_rad(10.0) / 60.0

var role: Role
var ship: MapShip
var route: Array[Vector2] = []
var destination := {}
## Ports a navy ship patrols between, in order.
var patrol: Array[Dictionary] = []
## Game seconds until the ship sails again; zero while at sea.
var in_port_for := 0.0
## +1 or -1: which board the ship is on while beating.
var tack := 1.0
var tacks_made := 0
## True while this ship is in a battle bubble: the bubble sails it, not the map.
var in_bubble := false
## Set when the ship comes back from a bubble off its course, so the route is plotted again.
var replan := false
## A ship this captain is chasing, or null. The route is its position, updated as it moves.
var quarry: Captain
## Set once the ship has been boarded and taken. It sails on, plundered, but won't strike again.
var struck := false
## At war with the player: fires on them in a bubble. A merchant once attacked; the navy when
## hunting a captain without honor.
var hostile := false
## A ship hunting the player: the navy after a captain without honor, a pirate after easy prey.
var hunting := false
## A pirate's lair, as {name, position}, and how long it has left on its hunting ground.
var lair := {}
var loiter_for := 0.0
## A prize the player took, sailed by a prize crew of the player's own, keeping station astern;
## and whether she has yet been brought into port.
var consort := false
var brought_in := false

## Meters astern of the player that each prize keeps station.
const STATION := 800.0

## Pirates spot prey this far off, and take a merchant they catch this close.
const SIGHT := 25000.0
const STRIKE_DISTANCE := 2000.0
## A pirate hunts within this many meters of its lair, and waits this long on its hunting ground.
const PROWL_REACH := 500000.0
const LOITER_HOURS := 48.0
## A pirate goes after the player when it outnumbers the player's crew this many times over.
const PREY_ODDS := 1.2
## And takes a merchant that it outnumbers this many times over without a fight.
const PIRATE_ODDS := 1.5
## Navy ships go after pirates within this many meters.
const PURSUIT_RANGE := 30000.0
var _beating := false
var _since_route := 0.0


## Of a navy ship's berths, the share filled: warships sailed crowded, to man the guns and fight.
const NAVY_MANNING := 0.7
const PIRATE_MANNING := 0.8


func _init(captain_role: Role, ship_design: ShipDesign) -> void:
	role = captain_role
	ship = MapShip.new(ship_design)
	if role == Role.NAVY:
		ship.crew = roundi(ship_design.crew_maximum * NAVY_MANNING)
		ship.guns = ship_design.gun_ports
	elif role == Role.PIRATE:
		# Pirates sailed crammed and lightly gunned: they meant to board, not to sink their prize.
		ship.crew = roundi(ship_design.crew_maximum * PIRATE_MANNING)
		ship.guns = mini(ship_design.gun_ports, 8)
	else:
		# Merchantmen carried a few guns against small raiders, not a battery.
		ship.guns = ship_design.gun_ports / 4


func role_name() -> String:
	return ["Merchant", "Navy", "Pirate"][role]


func at_sea() -> bool:
	return in_port_for <= 0.0


## Sets the next destination and plots a route to it.
func sail_for(port: Dictionary, navigation: Navigation) -> void:
	destination = port
	route = navigation.route(ship.position, port.position)


func update(delta: float, true_wind: Vector2, voyage: Voyage) -> void:
	if in_bubble:
		return
	if role == Role.PIRATE:
		_prowl(delta, true_wind, voyage)
		return
	if role == Role.NAVY:
		_pursue_pirates(voyage)
	if replan and at_sea() and not destination.is_empty():
		replan = false
		route = voyage.navigation.route(ship.position, destination.position)
	if not at_sea():
		ship.speed = 0.0
		in_port_for -= delta
		if at_sea():
			var next := _next_port(voyage)
			if role == Role.MERCHANT:
				_load_cargo(voyage, next)
			sail_for(next, voyage.navigation)
		return
	if navigate(delta, true_wind, voyage) and not hunting and quarry == null:
		in_port_for = voyage.random.randf_range(PORT_HOURS.x, PORT_HOURS.y) * 3600.0
		if destination.has("position"):
			# Come in and moor: the next voyage starts from the port itself.
			ship.position = destination.position
			_unload_cargo(voyage)


## Sails the route for one step. Returns true once the route is done; the ship doesn't move
## that step.
func navigate(delta: float, true_wind: Vector2, voyage: Voyage) -> bool:
	if hunting:
		_follow(_lead(voyage.ship, voyage), delta, voyage)
	elif quarry != null:
		_follow(_lead(quarry.ship, voyage), delta, voyage)
	while not route.is_empty() and _passed(route, voyage):
		route.pop_front()
	if route.is_empty():
		ship.speed = 0.0 if destination.has("name") else ship.speed
		return true
	_reef(true_wind, voyage)
	var wanted: float
	if ship.aground:
		# Work off the bank: head straight away from the land.
		wanted = _away_from_land(voyage.chart).angle()
	else:
		wanted = _heading_toward(route[0], true_wind, voyage)
	ship.heading = wrapf(rotate_toward(ship.heading, wanted, TURN_RATE * delta), -PI, PI)
	ship.step(delta, true_wind, voyage.chart)
	return false


## A captain carries what sail the wind allows. The player's crew, sailing a course for them,
## only ever shortens sail, never sets more than the player ordered.
func _reef(true_wind: Vector2, voyage: Voyage) -> void:
	var prudent := ship.prudent_sail(true_wind.length())
	if ship == voyage.ship:
		if ship.sail_set > prudent:
			ship.sail_set = prudent
			voyage.tell("The crew shortened sail for the wind")
	elif ship.sail_set > 0.0:
		ship.sail_set = prudent


## Where to steer to cut a ship off rather than chase her tail: where she'll be by the time
## we get there, at her present course and speed. Looked ahead no more than a few hours.
func _lead(target: MapShip, voyage: Voyage) -> Vector2:
	var distance := ship.position.distance_to(target.position)
	var closing := maxf(ship.speed, 2.0)
	var ahead := minf(distance / closing, 3.0 * 3600.0)
	var projected := target.position + target.forward() * target.speed * ahead
	return target.position if voyage.chart.is_land(projected) else projected


## Heads straight for a moving target when the water between is clear; otherwise plots a route
## to where it is now and sails that, plotting again every few hours as it moves.
func _follow(target: Vector2, delta: float, voyage: Voyage) -> void:
	_since_route += delta
	if voyage.navigation.clear(ship.position, target, 500.0):
		route = [target]
	elif route.is_empty() or _since_route > 4.0 * 3600.0:
		_since_route = 0.0
		route = voyage.navigation.route(ship.position, target)


## Whether the next waypoint is done with: reached, or close and with clear water to the one
## after it.
func _passed(waypoints: Array[Vector2], voyage: Voyage) -> bool:
	var distance := ship.position.distance_to(waypoints[0])
	if distance < REACHED_RADIUS:
		return true
	if distance > ARRIVAL_RADIUS:
		return false
	if waypoints.size() == 1:
		# A ship being chased isn't a waypoint to wave at from three kilometers off: close on it.
		return not (hunting or quarry != null)
	return voyage.navigation.clear(ship.position, waypoints[1], 500.0)


func _away_from_land(chart: Chart) -> Vector2:
	var reach := 300.0
	var gradient := Vector2(
		chart.signed_distance(ship.position + Vector2(reach, 0.0)) - chart.signed_distance(ship.position - Vector2(reach, 0.0)),
		chart.signed_distance(ship.position + Vector2(0.0, reach)) - chart.signed_distance(ship.position - Vector2(0.0, reach)))
	return gradient.normalized() if gradient.length_squared() > 0.0 else -ship.forward()


func _heading_toward(target: Vector2, true_wind: Vector2, voyage: Voyage) -> float:
	var course := (target - ship.position)
	var wind_from := -true_wind.normalized()
	var best := deg_to_rad(Polar.best_upwind_angle(ship.design.id, true_wind.length()))
	if absf(wind_from.angle_to(course)) >= best:
		_beating = false
		return course.angle()
	# Beating. Each board's heading, and which side of the wind it carries the ship to.
	var across := wind_from.orthogonal()
	var boards := {1.0: wind_from.rotated(best), -1.0: wind_from.rotated(-best)}
	var offset := course.dot(across)
	if not _beating:
		# Start on the board that heads toward the side the course lies on.
		_beating = true
		tack = 1.0 if signf((boards[1.0] as Vector2).dot(across)) == signf(offset) else -1.0
	# Stay on this board until the course has fallen well off to the other side, so the ship
	# doesn't tack every few minutes on the wind's line.
	var lane := clampf(course.length() * 0.3, 3000.0, 25000.0)
	var board_side := signf((boards[tack] as Vector2).dot(across))
	if signf(offset) != board_side and absf(offset) > lane:
		_go_about()
	var ahead := ship.position + (boards[tack] as Vector2) * LOOKOUT
	if voyage.chart.signed_distance(ahead) < 500.0:
		_go_about()
	return (boards[tack] as Vector2).angle()


func _go_about() -> void:
	tack = -tack
	tacks_made += 1


## A merchant loads whatever will sell best at the next port, as much as the hold takes and the
## port can spare. Merchants trading move prices just as the player does.
func _load_cargo(voyage: Voyage, next: Dictionary) -> void:
	var here: Market = voyage.markets.get(destination.get("name", ""), null)
	var there: Market = voyage.markets.get(next.get("name", ""), null)
	if here == null or there == null:
		return
	var best := ""
	var best_margin := 0.0
	for id in Goods.ids():
		var margin := there.selling_price(id) - here.buying_price(id)
		if margin > best_margin:
			best_margin = margin
			best = id
	if best.is_empty():
		return
	var spare := floori(here.stock[best] - here.settled[best] * 0.5)
	var tons := clampi(spare, 0, ship.free_tons())
	if tons > 0:
		here.take(best, tons)
		ship.hold[best] = ship.hold.get(best, 0) + tons


func _unload_cargo(voyage: Voyage) -> void:
	var here: Market = voyage.markets.get(destination.get("name", ""), null)
	if here == null:
		return
	for id in ship.hold:
		here.put(id, ship.hold[id])
	ship.hold.clear()
	struck = false


# The navy against pirates.

## A navy ship on patrol goes after any pirate it hears of nearby, and when it catches one, it
## fights her; the stronger ship usually wins.
func _pursue_pirates(voyage: Voyage) -> void:
	if quarry != null and (not quarry in voyage.captains or quarry.in_bubble):
		quarry = null
		replan = true
	if not at_sea() or hunting:
		return
	if quarry == null:
		for other in voyage.captains:
			if other.role == Role.PIRATE and other.at_sea() and not other.in_bubble \
					and other.ship.position.distance_to(ship.position) < PURSUIT_RANGE:
				quarry = other
				break
	if quarry != null and quarry.ship.position.distance_to(ship.position) < STRIKE_DISTANCE:
		if strength() * voyage.random.randf_range(0.7, 1.3) > quarry.strength():
			voyage.remove_captain(quarry)
			voyage.tell_near(ship.position, "The navy has taken a pirate sloop")
		else:
			ship.hull = maxf(ship.hull - 0.3, 0.1)
		quarry = null
		replan = true


## A prize keeps station astern of the player, one station further back for each prize ahead of
## her, and lies at her moorings while the player is in port.
func keep_station(delta: float, true_wind: Vector2, voyage: Voyage, place: int) -> void:
	if not voyage.docked.is_empty():
		ship.speed = 0.0
		return
	var leader := voyage.ship
	# The prize crew makes sail if she came out of the fight with it furled.
	if ship.sail_set <= 0.0:
		ship.sail_set = 1.0
	var station := leader.position - leader.forward() * STATION * (place + 1)
	if voyage.chart.is_land(station):
		station = leader.position
	_follow(station, delta, voyage)
	while not route.is_empty() and ship.position.distance_to(route[0]) < REACHED_RADIUS:
		route.pop_front()
	if route.is_empty():
		ship.speed = minf(ship.speed, leader.speed)
		return
	_reef(true_wind, voyage)
	ship.heading = wrapf(rotate_toward(ship.heading, _heading_toward(route[0], true_wind, voyage), TURN_RATE * delta), -PI, PI)
	ship.step(delta, true_wind, voyage.chart)


## A rough measure of a ship's fighting power: her crew, and her guns as long as her hull holds.
func strength() -> float:
	return ship.crew + 8.0 * ship.guns * ship.hull


# Pirates.

## A pirate rests in its lair, sails out to a hunting ground along the trade routes, waits there
## for prey, and takes what it can catch: merchants it outnumbers, and a player who looks weak.
func _prowl(delta: float, true_wind: Vector2, voyage: Voyage) -> void:
	if not at_sea():
		ship.speed = 0.0
		in_port_for -= delta
		if at_sea():
			_set_out(voyage)
		return
	_watch_for_prey(voyage)
	if quarry != null and ship.position.distance_to(quarry.ship.position) < STRIKE_DISTANCE:
		_take(quarry, voyage)
		quarry = null
		_head_home(voyage)
	var done := navigate(delta, true_wind, voyage)
	if not done or quarry != null or hunting:
		return
	if destination.is_empty():
		# On the hunting ground: heave to and wait for prey, then go home.
		ship.speed = 0.0
		loiter_for -= delta
		if loiter_for <= 0.0:
			_head_home(voyage)
	else:
		ship.position = destination.position
		in_port_for = voyage.random.randf_range(PORT_HOURS.x, PORT_HOURS.y) * 3600.0


func _set_out(voyage: Voyage) -> void:
	var grounds: Array[Dictionary] = []
	for port in voyage.ports:
		if port.position.distance_to(lair.position) < PROWL_REACH:
			grounds.append(port)
	if grounds.is_empty():
		grounds = voyage.ports
	var port: Dictionary = grounds[voyage.random.randi_range(0, grounds.size() - 1)]
	# Lie in wait halfway along the sea lane to a port, where merchants pass.
	var lane := voyage.navigation.route(ship.position, port.position)
	var ground: Vector2 = lane[lane.size() / 2] if not lane.is_empty() else port.position
	destination = {}
	route = voyage.navigation.route(ship.position, ground)
	loiter_for = LOITER_HOURS * 3600.0


func _head_home(voyage: Voyage) -> void:
	destination = lair
	route = voyage.navigation.route(ship.position, lair.position)


func _watch_for_prey(voyage: Voyage) -> void:
	if quarry != null and (not quarry in voyage.captains or not quarry.at_sea() or quarry.struck or quarry.in_bubble):
		quarry = null
	var player_at_sea := voyage.docked.is_empty() and voyage.bubble == null
	if hunting and not player_at_sea:
		# Safe in port: the pirate gives up and goes home.
		hunting = false
		hostile = false
		_head_home(voyage)
	if quarry != null or hunting:
		return
	var nearby := voyage.ship.position.distance_to(ship.position) < SIGHT
	if player_at_sea and nearby and ship.crew >= voyage.ship.crew * PREY_ODDS:
		hunting = true
		hostile = true
		voyage.tell("A pirate sloop is coming after you!")
		return
	for other in voyage.captains:
		if other.role == Role.MERCHANT and other.at_sea() and not other.struck and not other.in_bubble \
				and other.ship.position.distance_to(ship.position) < SIGHT:
			quarry = other
			return


## Takes a merchant caught at sea: she strikes if outnumbered enough, and her hold goes into the
## pirate's.
func _take(merchant: Captain, voyage: Voyage) -> void:
	if ship.crew < merchant.ship.crew * PIRATE_ODDS:
		return
	merchant.struck = true
	for id in merchant.ship.hold.keys():
		var taking := mini(merchant.ship.hold[id], ship.free_tons())
		if taking <= 0:
			continue
		merchant.ship.hold[id] -= taking
		if merchant.ship.hold[id] == 0:
			merchant.ship.hold.erase(id)
		ship.hold[id] = ship.hold.get(id, 0) + taking
	voyage.tell_near(ship.position, "Pirates have taken a merchant")


func _next_port(voyage: Voyage) -> Dictionary:
	if role == Role.NAVY and not patrol.is_empty():
		var index := patrol.find(destination)
		return patrol[(index + 1) % patrol.size()]
	var choice: Dictionary = destination
	while choice == destination:
		choice = voyage.ports[voyage.random.randi_range(0, voyage.ports.size() - 1)]
	return choice



## Everything about the captain worth keeping, as plain data. Ports are saved by name; a quarry
## (only the player's crew chases one) by its index among the voyage's captains.
func to_saved(voyage: Voyage) -> Dictionary:
	var waypoints: Array = []
	for point in route:
		waypoints.append([point.x, point.y])
	var stations: Array = []
	for port in patrol:
		stations.append(port.name)
	return {
		"role": role, "ship": ship.to_saved(), "route": waypoints,
		"destination": destination.get("name", ""), "patrol": stations,
		"in_port_for": in_port_for, "tack": tack, "tacks_made": tacks_made,
		"replan": replan, "struck": struck, "hostile": hostile, "hunting": hunting,
		"beating": _beating, "since_route": _since_route,
		"lair": lair.get("name", ""), "loiter_for": loiter_for,
		"consort": consort, "brought_in": brought_in,
		"quarry": voyage.captains.find(quarry) if quarry != null else -1,
	}


static func from_saved(saved: Dictionary, voyage: Voyage) -> Captain:
	var ship := MapShip.from_saved(saved.ship)
	var captain := Captain.new(int(saved.role) as Role, ship.design)
	captain.ship = ship
	for point: Array in saved.route:
		captain.route.append(Vector2(point[0], point[1]))
	captain.destination = voyage.port_named(saved.destination)
	for port_name: String in saved.patrol:
		captain.patrol.append(voyage.port_named(port_name))
	captain.in_port_for = saved.in_port_for
	captain.tack = saved.tack
	captain.tacks_made = int(saved.tacks_made)
	captain.replan = saved.replan
	captain.struck = saved.struck
	captain.hostile = saved.hostile
	captain.hunting = saved.hunting
	captain._beating = saved.beating
	captain._since_route = saved.since_route
	captain.lair = voyage.lair_named(saved.get("lair", ""))
	captain.loiter_for = saved.get("loiter_for", 0.0)
	captain.consort = saved.get("consort", false)
	captain.brought_in = saved.get("brought_in", false)
	return captain