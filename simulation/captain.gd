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
## degrees a game minute, the same rate as the player's helm at an hour a second, so a course
## change looks like someone turning the wheel and handing over the helm never jumps.
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
var _beating := false
var _since_route := 0.0


func _init(captain_role: Role, ship_design: ShipDesign) -> void:
	role = captain_role
	ship = MapShip.new(ship_design)


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
			sail_for(_next_port(voyage), voyage.navigation)
		return
	if navigate(delta, true_wind, voyage):
		in_port_for = voyage.random.randf_range(PORT_HOURS.x, PORT_HOURS.y) * 3600.0
		if destination.has("position"):
			# Come in and moor: the next voyage starts from the port itself.
			ship.position = destination.position


## Sails the route for one step. Returns true once the route is done; the ship doesn't move
## that step.
func navigate(delta: float, true_wind: Vector2, voyage: Voyage) -> bool:
	if quarry != null:
		_follow_quarry(delta, voyage)
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


## Heads straight for the quarry when the water between is clear; otherwise plots a route to
## where it is now and sails that, plotting again every few hours as it moves.
func _follow_quarry(delta: float, voyage: Voyage) -> void:
	var target := quarry.ship.position
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


func _next_port(voyage: Voyage) -> Dictionary:
	if role == Role.NAVY and not patrol.is_empty():
		var index := patrol.find(destination)
		return patrol[(index + 1) % patrol.size()]
	var choice: Dictionary = destination
	while choice == destination:
		choice = voyage.ports[voyage.random.randi_range(0, voyage.ports.size() - 1)]
	return choice
