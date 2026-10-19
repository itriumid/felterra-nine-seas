class_name Captain
extends RefCounted
## A computer-controlled captain sailing a ship on the world map: merchants trading from port to
## port, navy ships patrolling between their stations.
##
## The captain follows a route that keeps clear of land and sails it the way a real one would.
## When the next waypoint lies too close to the wind to sail straight at, the captain beats
## toward it: close-hauled at the ship's best upwind angle, tacking from one board to the other
## to stay within a lane around the course, and early if land comes up ahead.

enum Role { MERCHANT, NAVY }

## Meters from a waypoint where the captain may cut the corner to the next one, if the water
## between is clear; and how close counts as reaching it regardless.
const ARRIVAL_RADIUS := 3000.0
const REACHED_RADIUS := 300.0
## Hours a ship spends in port between voyages.
const PORT_HOURS := Vector2(12.0, 48.0)
## Meters ahead the captain looks for land while beating.
const LOOKOUT := 4000.0
## How fast a captain brings the ship onto a new heading, in radians per game second: two
## degrees a game minute, the same rate as the player's helm, so a course change looks like
## someone turning the wheel and handing over the helm never jumps.
const TURN_RATE := deg_to_rad(2.0) / 60.0

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
## A navy ship sent after the player.
var hunting := false
var _beating := false
var _since_route := 0.0


## Of a navy ship's berths, the share filled: warships sailed crowded, to man the guns and fight.
const NAVY_MANNING := 0.7


func _init(captain_role: Role, ship_design: ShipDesign) -> void:
	role = captain_role
	ship = MapShip.new(ship_design)
	if role == Role.NAVY:
		ship.crew = roundi(ship_design.crew_maximum * NAVY_MANNING)
		ship.guns = ship_design.gun_ports
	else:
		# Merchantmen carried a few guns against small raiders, not a battery.
		ship.guns = ship_design.gun_ports / 4


func role_name() -> String:
	return "Navy" if role == Role.NAVY else "Merchant"


func at_sea() -> bool:
	return in_port_for <= 0.0


## Sets the next destination and plots a route to it.
func sail_for(port: Dictionary, navigation: Navigation) -> void:
	destination = port
	route = navigation.route(ship.position, port.position)


func update(delta: float, true_wind: Vector2, voyage: Voyage) -> void:
	if in_bubble:
		return
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
	if navigate(delta, true_wind, voyage) and not hunting:
		in_port_for = voyage.random.randf_range(PORT_HOURS.x, PORT_HOURS.y) * 3600.0
		if destination.has("position"):
			# Come in and moor: the next voyage starts from the port itself.
			ship.position = destination.position
			_unload_cargo(voyage)


## Sails the route for one step. Returns true once the route is done; the ship doesn't move
## that step.
func navigate(delta: float, true_wind: Vector2, voyage: Voyage) -> bool:
	if hunting:
		_follow(voyage.ship.position, delta, voyage)
	elif quarry != null:
		_follow(quarry.ship.position, delta, voyage)
	while not route.is_empty() and _passed(route, voyage):
		route.pop_front()
	if route.is_empty():
		ship.speed = 0.0 if destination.has("name") else ship.speed
		return true
	var wanted: float
	if ship.aground:
		# Work off the bank: head straight away from the land.
		wanted = _away_from_land(voyage.chart).angle()
	else:
		wanted = _heading_toward(route[0], true_wind, voyage)
	ship.heading = wrapf(rotate_toward(ship.heading, wanted, TURN_RATE * delta), -PI, PI)
	ship.step(delta, true_wind, voyage.chart)
	return false


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
		return true
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
	return captain