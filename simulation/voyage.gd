class_name Voyage
extends RefCounted
## Everything about the player's game that outlives a screen: the date, the winds, the chart,
## the ports and the player's ship.

## The game starts at dawn on the 15th of January, in the steady northeast monsoon.
const START_DAY := 14
const START_HOUR := 6.0
const START_PORT := "Batavia"

var chart := Chart.new()
var calendar := Calendar.starting_on(START_DAY, START_HOUR)
var monsoon := Monsoon.new(calendar)
var ports := Ports.on(chart)
var designs := ShipDesign.all()
var design_index := 0
var ship: MapShip
var navigation := Navigation.new(chart)
var random := RandomNumberGenerator.new()
## Every computer-controlled ship at sea or in port.
var captains: Array[Captain] = []
## The player's crew sailing to a chosen point, or null while the player has the helm.
var autopilot: Captain
## The battle bubble the player is in, or null on the open map.
var bubble: Bubble

const MERCHANTS := 14
## Navy squadrons and the ports each patrols between.
const NAVY_PATROLS: Array[Array] = [
	["Batavia", "Banten", "Palembang"],
	["Malacca", "Singapura", "Aceh"],
	["Semarang", "Surabaya", "Banjarmasin"],
	["Makassar", "Surabaya"],
]


func _init(seed_value := 39) -> void:
	random.seed = seed_value
	ship = MapShip.new(designs[design_index])
	ship.position = port_named(START_PORT).position
	# Head away from the land, out to sea.
	ship.heading = Vector2.UP.angle()
	_spawn_traffic()


## Merchants spread across the ports, navy squadrons on their stations, each leaving port at a
## different time so the sea fills up gradually rather than all at once.
func _spawn_traffic() -> void:
	for index in MERCHANTS:
		var design := designs[random.randi_range(0, designs.size() - 1)]
		var captain := Captain.new(Captain.Role.MERCHANT, design)
		var home: Dictionary = ports[random.randi_range(0, ports.size() - 1)]
		captain.ship.position = home.position
		captain.destination = home
		captain.in_port_for = random.randf_range(0.0, 72.0) * 3600.0
		captains.append(captain)
	for stations in NAVY_PATROLS:
		var captain := Captain.new(Captain.Role.NAVY, ShipDesign.brig())
		for port_name: String in stations:
			captain.patrol.append(port_named(port_name))
		captain.ship.position = captain.patrol[0].position
		captain.destination = captain.patrol[0]
		captain.in_port_for = random.randf_range(0.0, 24.0) * 3600.0
		captains.append(captain)


## The nearest other ship at sea and how far it is, or an empty result.
func nearest_sighting() -> Dictionary:
	var nearest := {}
	var nearest_distance := INF
	for captain in captains:
		if not captain.at_sea():
			continue
		var distance := ship.position.distance_to(captain.ship.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = {"captain": captain, "distance": distance}
	return nearest


func port_named(port_name: String) -> Dictionary:
	for port in ports:
		if port.name == port_name:
			return port
	return {}


func nearest_port() -> Dictionary:
	var nearest: Dictionary = ports[0]
	for port in ports:
		if ship.position.distance_to(port.position) < ship.position.distance_to(nearest.position):
			nearest = port
	return nearest


## Has the crew sail the player's ship to a point, around land and against the wind if need
## be. Returns false if there's no way there by sea.
func set_course(target: Vector2) -> bool:
	if chart.is_land(target):
		target = chart.nearest_water(target, 3)
		if chart.is_land(target):
			return false
	var crew := Captain.new(Captain.Role.MERCHANT, ship.design)
	crew.ship = ship
	crew.route = navigation.route(ship.position, target)
	if crew.route.is_empty():
		return false
	autopilot = crew
	return true


## Has the crew give chase to another ship. Meeting it opens a bubble.
func chase(captain: Captain) -> void:
	var crew := Captain.new(Captain.Role.MERCHANT, ship.design)
	crew.ship = ship
	crew.quarry = captain
	autopilot = crew


func take_helm() -> void:
	autopilot = null


func switch_ship() -> void:
	autopilot = null
	design_index = (design_index + 1) % designs.size()
	var replacement := MapShip.new(designs[design_index])
	replacement.position = ship.position
	replacement.heading = ship.heading
	replacement.sail_set = ship.sail_set
	ship = replacement


func advance(delta: float) -> void:
	calendar.advance(delta)
	var wind := monsoon.velocity_at(ship.position)
	if bubble != null:
		pass  # The player's ship is in the bubble; the world sails on without it.
	elif autopilot != null:
		if autopilot.navigate(delta, wind, self) and autopilot.quarry == null:
			autopilot = null
	else:
		ship.step(delta, wind, chart)
	for captain in captains:
		captain.update(delta, monsoon.velocity_at(captain.ship.position), self)
	if bubble == null:
		_check_for_meeting()


## Opens a bubble when the ship the player is chasing comes within range, taking in every other
## ship that close too.
func _check_for_meeting() -> void:
	if autopilot == null or autopilot.quarry == null:
		return
	if ship.position.distance_to(autopilot.quarry.ship.position) > Bubble.OPEN_RANGE:
		return
	var met: Array[Captain] = []
	for captain in captains:
		if captain.at_sea() and captain.ship.position.distance_to(ship.position) <= Bubble.OPEN_RANGE:
			met.append(captain)
	if met.is_empty():
		# The quarry made port before we caught it.
		autopilot = null
		return
	autopilot = null
	bubble = Bubble.around(self, met)


## One step of the bubble's clock, closing it when the ships have drawn apart.
func step_bubble() -> void:
	bubble.step()
	if bubble.should_close():
		bubble.close()
		bubble = null
