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
		_steer(captains[index], ships[index])
	for ship in all_ships():
		var before := ship.position
		ship.step(STEP, wind.velocity_at(ship.position))
		if chart.is_land(origin + ship.position):
			# Hard aground: the hull stops where the water ends.
			ship.position = before
			ship.velocity = Vector2.ZERO
			ship.yaw_rate = 0.0
	_collide()


func should_close() -> bool:
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


## A captain's hands on the helm: merchants run from the player, navy ships close with them.
## Either way, never straight into the wind, and never onto the land.
func _steer(captain: Captain, ship: Ship) -> void:
	var to_player := player.position - ship.position
	var wanted := to_player if captain.role == Captain.Role.NAVY else -to_player
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
			var mass_a := a.design.mass
			var mass_b := b.design.mass
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
			collisions.append({"ships": [a, b], "speed": closing})
			return


static func _hull_circles(ship: Ship) -> Array[Vector2]:
	var along := ship.forward() * ship.design.length_overall * 0.3
	return [ship.position + along, ship.position, ship.position - along]


static func _inertia(ship: Ship) -> float:
	return ship.design.mass * pow(ship.design.length_overall / 4.0, 2.0)
