class_name Voyage
extends RefCounted
## Everything about the player's game that outlives a screen: the date, the winds, the chart,
## the ports and their markets, the player's ship and purse.
##
## Everything the player does goes through a command here (set a course, buy, hire, set
## sail), so a server can run the same voyage for every player. Commands that can be refused
## return the reason, or an empty string when they succeed.

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
## Ships the player has taken as prizes, sailing in company with prize crews of the player's own.
var prizes: Array[Captain] = []
## The player's crew sailing to a chosen point, or null while the player has the helm.
var autopilot: Captain
## The battle bubble the player is in, or null on the open map.
var bubble: Bubble
## Reals in the player's purse.
var purse := STARTING_PURSE
## Each port's market and the sailors in its taverns looking for a berth, by port name.
var markets := {}
var taverns := {}
## The port the player's ship is moored in, or empty at sea.
var docked := {}
var _unpaid_days := 0.0
## How widely the player is known, from 0, and how they're known: honorable above 0, cruel
## below, from -100 to 100.
var renown := 0.0
var honor := 0.0
## The latest thing worth telling the player, and how many game seconds it has been shown.
var news := ""
var news_age := 0.0
## Pirate lairs, as {name, position}, and the reals owed to the player in bounties, paid at the
## next port.
var lairs: Array[Dictionary] = []
var bounty := 0.0
var _since_pirate := 0.0

## A prize within this many meters of the player is in company: she comes into port with them.
const PRIZE_COMPANY := 30000.0
## What a shipyard pays for a prize, against a new ship's price, when her hull is sound.
const PRIZE_SHARE := 0.5

## Islands pirates actually hid among: the Riau islands south of Singapura, Belitung, and the
## Karimata islands off Borneo.
const LAIRS: Array[Array] = [
	["Riau", 0.95, 104.45],
	["Belitung", -2.75, 107.65],
	["Karimata", -1.6, 108.9],
]
const PIRATES := 4
## A pirate lost is replaced, one at a time, this often.
const PIRATE_DAYS := 5.0
## What the authorities pay for a pirate taken or sunk.
const BOUNTY_TAKEN := 600.0
const BOUNTY_SUNK := 400.0
## News of fights between computer ships reaches the player within this many meters.
const NEWS_RANGE := 150000.0

## What the world makes of each deed, as [renown, honor].
const DEEDS := {
	"attacked_merchant": [0.0, -5.0],
	"attacked_navy": [0.0, -10.0],
	"captured_merchant": [5.0, 0.0],
	"captured_navy": [15.0, 0.0],
	"sank_merchant": [3.0, -15.0],
	"sank_navy": [10.0, -5.0],
	"shipwrecked": [-10.0, 0.0],
	# Fighting pirates is defending the trade: no honor lost, and taking them earns it.
	"attacked_pirate": [0.0, 0.0],
	"captured_pirate": [10.0, 5.0],
	"sank_pirate": [6.0, 3.0],
	"plundered_by_pirates": [-3.0, 0.0],
	"took_prize": [2.0, 0.0],
	"brought_in_prize": [3.0, 0.0],
}
## Below this honor the navy hunts the player.
const HUNTED_BELOW := -20.0
## Navy ships within this many meters join the hunt.
const HUNT_RANGE := 120000.0
## Honor drifts back toward nothing as deeds are forgotten, this much a day.
const FORGETTING := 0.2
## Renown from trade: one point per this many reals of goods sold.
const REALS_PER_RENOWN := 5000.0

const STARTING_PURSE := 1500.0
const STARTING_CREW := 12
const STARTING_GUNS := 4
## What a shipyard pays for a gun taken off, against what it charges for one.
const GUN_RESALE_SHARE := 0.5
## A sailor's pay, in reals a day, and the bounty for signing on.
const WAGE := 0.5
const SIGNING_BOUNTY := 5.0
## How many sailors a tavern can have looking for a berth, and how many turn up a day.
const TAVERN_LIMIT := 40
const SAILORS_A_DAY := 4.0
## A port's harbor: within this many meters, a ship that furls its sails comes in and moors.
## At the chart's scale the crew brings her in with anchors and warps rather than waiting for
## her to drift to a stop, which could carry her back out of the harbor first.
const HARBOR_RANGE := 5000.0
## What a shipyard charges: to make good a whole hull, as a share of the ship's price; to haul
## the ship out and scrape its bottom; and what it gives for a ship traded in, when sound.
const REPAIR_SHARE := 0.3
const SCRAPING_SHARE := 0.02
const TRADE_IN_SHARE := 0.6

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
	ship.crew = STARTING_CREW
	ship.guns = STARTING_GUNS
	var distances := _sailing_distances()
	for port in ports:
		var prices := {}
		for id in Goods.ids():
			prices[id] = Market.regional_price(id, port, ports, distances)
		markets[port.name] = Market.new(prices)
		taverns[port.name] = random.randi_range(10, TAVERN_LIMIT)
	for lair in LAIRS:
		lairs.append({"name": lair[0], "position": chart.nearest_water(Chart.position_of(lair[1], lair[2]))})
	dock(port_named(START_PORT))
	_spawn_traffic()
	for index in PIRATES:
		_spawn_pirate(random.randf_range(0.0, 96.0) * 3600.0)


## Meters by sea between every pair of ports, along their routes, by "port>port" key.
func _sailing_distances() -> Dictionary:
	var distances := {}
	for from in ports:
		for to in ports:
			if from == to:
				continue
			var length := 0.0
			var previous: Vector2 = from.position
			for point in navigation.route(from.position, to.position):
				length += previous.distance_to(point)
				previous = point
			distances["%s>%s" % [from.name, to.name]] = length
	return distances


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


## The nearest other ship at sea in sight, and how far it is, or an empty result.
func nearest_sighting() -> Dictionary:
	var nearest := {}
	var nearest_distance := INF
	for captain in captains:
		if not captain.at_sea() or not monsoon.weather.in_sight(ship.position, captain.ship.position):
			continue
		var distance := ship.position.distance_to(captain.ship.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = {"captain": captain, "distance": distance}
	return nearest


func _spawn_pirate(resting: float) -> void:
	var pirate := Captain.new(Captain.Role.PIRATE, ShipDesign.sloop())
	pirate.lair = lairs[random.randi_range(0, lairs.size() - 1)]
	pirate.ship.position = pirate.lair.position
	pirate.destination = pirate.lair
	pirate.in_port_for = resting
	captains.append(pirate)


## Takes a captain out of the world, and out of anyone's sights.
func remove_captain(gone: Captain) -> void:
	captains.erase(gone)
	for captain in captains:
		if captain.quarry == gone:
			captain.quarry = null
			captain.replan = true
	if autopilot != null and autopilot.quarry == gone:
		autopilot = null


## Tells the player of something that happened near enough to hear about.
func tell_near(where: Vector2, message: String) -> void:
	if where.distance_to(ship.position) < NEWS_RANGE:
		tell(message)


func lair_named(lair_name: String) -> Dictionary:
	for lair in lairs:
		if lair.name == lair_name:
			return lair
	return {}


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


## Has the crew sail to a port and moor there.
func sail_to_port(port: Dictionary) -> bool:
	if not set_course(port.position):
		return false
	autopilot.destination = port
	return true


## Has the crew sail the player's ship to a point, around land and against the wind if need
## be. Returns false if there's no way there by sea.
func set_course(target: Vector2) -> bool:
	if not docked.is_empty():
		undock()
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
	_make_sail()
	return true


## Given a course with all sail furled (after a fight, say), the crew makes sail first.
func _make_sail() -> void:
	if ship.sail_set <= 0.0:
		ship.sail_set = 1.0


## Has the crew give chase to another ship. Meeting it opens a bubble.
func chase(captain: Captain) -> void:
	if not docked.is_empty():
		undock()
	var crew := Captain.new(Captain.Role.MERCHANT, ship.design)
	crew.ship = ship
	crew.quarry = captain
	autopilot = crew
	_make_sail()


func take_helm() -> void:
	autopilot = null


## Swaps the player's ship for the next class, for free. A development aid; players buy ships at
## a shipyard.
func switch_ship() -> void:
	autopilot = null
	design_index = (design_index + 1) % designs.size()
	var replacement := MapShip.new(designs[design_index])
	replacement.position = ship.position
	replacement.heading = ship.heading
	replacement.sail_set = ship.sail_set
	replacement.hold = ship.hold
	replacement.crew = maxi(ship.crew, replacement.design.crew_minimum)
	ship = replacement


func advance(delta: float) -> void:
	calendar.advance(delta)
	var wind := monsoon.velocity_at(ship.position)
	if bubble != null or not docked.is_empty():
		pass  # In a bubble, or moored: the world sails on without the player's ship.
	elif autopilot != null:
		if autopilot.navigate(delta, wind, self) and autopilot.quarry == null:
			var arrived := autopilot.destination
			autopilot = null
			if arrived.has("name"):
				dock(arrived)
	else:
		ship.step(delta, wind, chart)
		_check_for_mooring()
	monsoon.weather.advance(delta, monsoon, chart, random)
	for market in markets.values():
		market.advance(delta)
	_fill_taverns(delta)
	_pay_crew(delta)
	_forget(delta)
	_send_the_navy()
	_replace_pirates(delta)
	news_age += delta
	for captain in captains:
		captain.update(delta, monsoon.velocity_at(captain.ship.position), self)
	for place in prizes.size():
		prizes[place].keep_station(delta, monsoon.velocity_at(prizes[place].ship.position), self, place)
	if bubble == null:
		_check_for_meeting()


## Opens a bubble when the ship the player is chasing comes within range, taking in every other
## ship that close too.
func _check_for_meeting() -> void:
	var chased := autopilot != null and autopilot.quarry != null \
		and ship.position.distance_to(autopilot.quarry.ship.position) <= Bubble.OPEN_RANGE
	var hunted := false
	for captain in captains:
		# A hunter has to see her to fall on her: in thick rain she can pass close by unseen.
		if captain.hunting and captain.at_sea() and captain.ship.position.distance_to(ship.position) <= Bubble.OPEN_RANGE \
				and monsoon.weather.in_sight(captain.ship.position, ship.position):
			hunted = true
	if not chased and not hunted:
		return
	if not docked.is_empty():
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
	bubble.surrender_odds = Bubble.SURRENDER_ODDS / fear()
	if hunted:
		tell("The navy has caught up with you!")


func board() -> String:
	if bubble == null:
		return "There's no ship to board"
	return bubble.board()


## Takes goods from a plundered ship into the hold, as much as there is and the hold takes.
func plunder(id: String, tons: int) -> String:
	if bubble == null or bubble.prize() == null:
		return "There's nothing to plunder"
	var prize := bubble.prize()
	var taking := mini(tons, prize.hold.get(id, 0))
	if taking > ship.free_tons():
		return "Not enough room in the hold"
	if taking <= 0:
		return ""
	prize.hold[id] -= taking
	if prize.hold[id] == 0:
		prize.hold.erase(id)
	ship.hold[id] = ship.hold.get(id, 0) + taking
	return ""


func cast_off() -> void:
	if bubble != null:
		bubble.cast_off()


## One step of the bubble's clock, closing it when the ships have drawn apart.
func step_bubble() -> void:
	bubble.step()
	for deed in bubble.deeds:
		reckon(deed)
	bubble.deeds.clear()
	for captain in bubble.sunk:
		remove_captain(captain)
	bubble.sunk.clear()
	for captain in bubble.prizes_taken:
		remove_captain(captain)
		prizes.append(captain)
		tell("Your prize crew has her: she'll follow you into port")
	bubble.prizes_taken.clear()
	if bubble.player_sunk:
		_shipwreck()
		return
	if bubble.should_close():
		bubble.close()
		bubble = null


# Renown and honor.

## Adds a deed to the player's reputation, and to their bounties if it was against pirates.
func reckon(deed: String) -> void:
	var weight: Array = DEEDS[deed]
	renown = maxf(renown + weight[0], 0.0)
	honor = clampf(honor + weight[1], -100.0, 100.0)
	if deed == "captured_pirate":
		bounty += BOUNTY_TAKEN
	elif deed == "sank_pirate":
		bounty += BOUNTY_SUNK
	elif deed == "plundered_by_pirates":
		tell("Pirates have stripped your hold")


## How the world speaks of the player.
func reputation_title() -> String:
	if renown < 10.0:
		return "Unknown"
	var famous := renown >= 50.0
	if honor >= 20.0:
		return "Celebrated" if famous else "Honorable"
	if honor <= HUNTED_BELOW:
		return "Notorious" if famous else "Feared"
	return "Famous" if famous else "Known"


## How much a reputation makes merchants quail: renown counts three times over for a captain
## known for cruelty.
func fear() -> float:
	return 1.0 + renown / (50.0 if honor < 0.0 else 150.0)


func hunted() -> bool:
	return honor <= HUNTED_BELOW


func tell(message: String) -> void:
	news = message
	news_age = 0.0


func _forget(delta: float) -> void:
	honor = move_toward(honor, 0.0, FORGETTING * delta / Calendar.SECONDS_PER_DAY)


## Pirates the navy or the player have accounted for are replaced, one at a time.
func _replace_pirates(delta: float) -> void:
	_since_pirate += delta
	if _since_pirate < PIRATE_DAYS * Calendar.SECONDS_PER_DAY:
		return
	_since_pirate = 0.0
	var pirates := captains.filter(func(captain: Captain) -> bool: return captain.role == Captain.Role.PIRATE)
	if pirates.size() < PIRATES:
		_spawn_pirate(0.0)


## Without honor, every navy ship near enough comes after the player; with it back, they stand
## down and return to their stations.
func _send_the_navy() -> void:
	for captain in captains:
		if captain.role != Captain.Role.NAVY or captain.in_bubble:
			continue
		if hunted() and captain.at_sea() and captain.given_up_for <= 0.0 \
				and captain.ship.position.distance_to(ship.position) < HUNT_RANGE:
			if not captain.hunting:
				captain.start_hunting(self)
				tell("Navy ships are hunting you")
		elif captain.hunting and not hunted():
			captain.hunting = false
			captain.hostile = false
			captain.replan = true


## The player's ship has gone down. The survivors are picked up and landed at the nearest port,
## where the shipyard gives them an old sloop to start again; cargo and guns are lost.
func _shipwreck() -> void:
	var survivors := maxi(ship.crew / 3, 4)
	var port := nearest_port()
	bubble.close()
	bubble = null
	var wreck := MapShip.new(ShipDesign.sloop())
	wreck.crew = mini(survivors, wreck.design.crew_maximum)
	wreck.hull = 0.6
	ship = wreck
	design_index = 0
	dock(port)
	reckon("shipwrecked")
	tell("Your ship went down. The survivors were landed at %s." % port.name)



# Ports.

## Comes in and moors: the ship stops at the port, sails furled. Bounties owed are paid here.
func dock(port: Dictionary) -> void:
	docked = port
	autopilot = null
	ship.position = port.position
	ship.speed = 0.0
	ship.sail_set = 0.0
	if bounty > 0.0:
		tell("The harbor master pays %d reals in bounties for pirates" % roundi(bounty))
		purse += bounty
		bounty = 0.0
	# Prizes in company come in and moor alongside.
	for prize in prizes:
		if prize.ship.position.distance_to(port.position) < PRIZE_COMPANY:
			prize.ship.position = port.position
			prize.ship.speed = 0.0
			prize.route.clear()
			if not prize.brought_in:
				prize.brought_in = true
				reckon("brought_in_prize")


## Casts off and makes sail, heading away from the land.
func undock() -> void:
	if docked.is_empty():
		return
	docked = {}
	ship.sail_set = 1.0
	var reach := 1000.0
	var away := Vector2(
		chart.signed_distance(ship.position + Vector2(reach, 0.0)) - chart.signed_distance(ship.position - Vector2(reach, 0.0)),
		chart.signed_distance(ship.position + Vector2(0.0, reach)) - chart.signed_distance(ship.position - Vector2(0.0, reach)))
	if away.length_squared() > 0.0:
		ship.heading = away.angle()


func market() -> Market:
	return markets.get(docked.get("name", ""), null)


func buy(id: String, tons: int) -> String:
	if docked.is_empty():
		return "You can only trade in port"
	var port_market := market()
	if tons <= 0:
		return ""
	if tons > ship.free_tons():
		return "Not enough room in the hold"
	if tons > floori(port_market.stock[id]):
		return "The port hasn't that much to sell"
	var cost := port_market.cost_to_buy(id, tons)
	if cost > purse:
		return "Not enough reals"
	purse -= cost
	port_market.take(id, tons)
	ship.hold[id] = ship.hold.get(id, 0) + tons
	return ""


func sell(id: String, tons: int) -> String:
	if docked.is_empty():
		return "You can only trade in port"
	if tons <= 0:
		return ""
	if tons > ship.hold.get(id, 0):
		return "You haven't that much aboard"
	var port_market := market()
	var proceeds := port_market.proceeds_from_selling(id, tons)
	purse += proceeds
	renown += proceeds / REALS_PER_RENOWN
	port_market.put(id, tons)
	ship.hold[id] -= tons
	if ship.hold[id] == 0:
		ship.hold.erase(id)
	return ""


func sailors_in_tavern() -> int:
	return taverns.get(docked.get("name", ""), 0)


func hire(count: int) -> String:
	if docked.is_empty():
		return "Sailors sign on in port"
	if count > sailors_in_tavern():
		return "Not that many sailors looking for a berth"
	if ship.crew + count > ship.design.crew_maximum:
		return "No room to berth them"
	if count * SIGNING_BOUNTY > purse:
		return "Not enough reals for their bounty"
	purse -= count * SIGNING_BOUNTY
	taverns[docked.name] -= count
	ship.crew += count
	return ""


func dismiss(count: int) -> String:
	if docked.is_empty():
		return "Sailors are paid off in port"
	if count > ship.crew:
		return "You haven't that many sailors"
	ship.crew -= count
	taverns[docked.name] = mini(taverns[docked.name] + count, TAVERN_LIMIT)
	return ""


func repair_cost() -> float:
	return ((1.0 - ship.hull) + (1.0 - ship.rigging) * 0.5) * ship.design.price * REPAIR_SHARE


## Makes good the hull and the rigging.
func repair() -> String:
	if docked.is_empty():
		return "Repairs are done in port"
	if repair_cost() > purse:
		return "Not enough reals"
	purse -= repair_cost()
	ship.hull = 1.0
	ship.rigging = 1.0
	return ""


func buy_guns(count: int) -> String:
	if docked.is_empty():
		return "Guns are sold in port"
	if ship.guns + count > ship.design.gun_ports:
		return "She hasn't the gun ports"
	if count * ShipDesign.GUN_PRICE > purse:
		return "Not enough reals"
	purse -= count * ShipDesign.GUN_PRICE
	ship.guns += count
	return ""


func sell_guns(count: int) -> String:
	if docked.is_empty():
		return "Guns are sold in port"
	if count > ship.guns:
		return "You haven't that many guns"
	purse += count * ShipDesign.GUN_PRICE * GUN_RESALE_SHARE
	ship.guns -= count
	return ""


func scraping_cost() -> float:
	return ship.design.price * SCRAPING_SHARE


## Hauls the ship out and scrapes the barnacles off its bottom.
func scrape() -> String:
	if docked.is_empty():
		return "Ships are hauled out in port"
	if scraping_cost() > purse:
		return "Not enough reals"
	purse -= scraping_cost()
	ship.fouling = 0.0
	return ""


## What a prize fetches in this port: the ship at the shipyard, her cargo at the market.
func prize_value(prize: Captain) -> float:
	var value := prize.ship.design.price * PRIZE_SHARE * prize.ship.hull
	var port_market := market()
	if port_market != null:
		for id: String in prize.ship.hold:
			value += port_market.proceeds_from_selling(id, prize.ship.hold[id])
	return value


func _prize_in_port(index: int) -> String:
	if docked.is_empty():
		return "Prizes are sold in port"
	if index < 0 or index >= prizes.size():
		return "There's no such prize"
	if prizes[index].ship.position.distance_to(docked.position) > 1.0:
		return "She hasn't come in yet"
	return ""


## Sells a prize, ship and cargo; her prize crew comes back aboard, or to the tavern if there's
## no room for them.
func sell_prize(index: int) -> String:
	var refusal := _prize_in_port(index)
	if not refusal.is_empty():
		return refusal
	var prize := prizes[index]
	purse += prize_value(prize)
	var port_market := market()
	for id: String in prize.ship.hold:
		port_market.put(id, prize.ship.hold[id])
	_take_back_crew(prize.ship.crew)
	prizes.remove_at(index)
	return ""


## Moves into a prize and makes her the player's ship; the old one is sold to the shipyard.
func make_prize_flagship(index: int) -> String:
	var refusal := _prize_in_port(index)
	if not refusal.is_empty():
		return refusal
	var prize := prizes[index]
	var cargo := ship.cargo_tons() + prize.ship.cargo_tons()
	if cargo > prize.ship.design.cargo_capacity:
		return "Your cargo and hers won't both fit in her hold"
	purse += trade_in_value()
	var flagship := prize.ship
	for id: String in ship.hold:
		flagship.hold[id] = flagship.hold.get(id, 0) + ship.hold[id]
	var crew := ship.crew + flagship.crew
	flagship.crew = 0
	flagship.position = ship.position
	flagship.sail_set = 0.0
	ship = flagship
	_take_back_crew(crew)
	design_index = designs.find_custom(func(each: ShipDesign) -> bool: return each.id == flagship.design.id)
	prizes.remove_at(index)
	return ""


func _take_back_crew(count: int) -> void:
	var berths := ship.design.crew_maximum - ship.crew
	var aboard := mini(count, berths)
	ship.crew += aboard
	if not docked.is_empty():
		taverns[docked.name] = taverns.get(docked.name, 0) + count - aboard


func trade_in_value() -> float:
	return ship.design.price * TRADE_IN_SHARE * ship.hull


func cost_of_ship(design: ShipDesign) -> float:
	return design.price - trade_in_value()


## Trades the ship in for another class, keeping the cargo and the crew.
func buy_ship(design: ShipDesign) -> String:
	if docked.is_empty():
		return "Ships are sold in port"
	if design.id == ship.design.id:
		return "That's the ship you have"
	if ship.cargo_tons() > design.cargo_capacity:
		return "Your cargo won't fit in her hold"
	if ship.crew > design.crew_maximum:
		return "She can't berth your crew"
	if ship.guns > design.gun_ports:
		return "She hasn't the gun ports for your guns"
	if cost_of_ship(design) > purse:
		return "Not enough reals"
	purse -= cost_of_ship(design)
	var replacement := MapShip.new(design)
	replacement.position = ship.position
	replacement.heading = ship.heading
	replacement.sail_set = ship.sail_set
	replacement.hold = ship.hold
	replacement.crew = ship.crew
	replacement.guns = ship.guns
	ship = replacement
	design_index = designs.find_custom(func(each: ShipDesign) -> bool: return each.id == design.id)
	return ""


## Moors the ship when she has furled her sails in a harbor.
func _check_for_mooring() -> void:
	if ship.sail_set > 0.0:
		return
	var port := harbor_here()
	if not port.is_empty():
		dock(port)


## The port whose harbor the ship is in, or empty.
func harbor_here() -> Dictionary:
	for port in ports:
		if ship.position.distance_to(port.position) <= HARBOR_RANGE:
			return port
	return {}


## Comes in and moors at the port whose harbor the ship is in.
func moor() -> String:
	if not docked.is_empty():
		return "You're already moored"
	if bubble != null:
		return "Not in the middle of a fight"
	var port := harbor_here()
	if port.is_empty():
		return "There's no harbor here: sail within %d kilometers of a port" % roundi(HARBOR_RANGE / 1000.0)
	dock(port)
	return ""


func _fill_taverns(delta: float) -> void:
	# A famous captain draws sailors looking for a berth.
	var arriving := SAILORS_A_DAY * (1.0 + renown / 50.0) * delta / Calendar.SECONDS_PER_DAY
	for port_name in taverns:
		# Sailors come in whole; a fractional arrival is a chance of one.
		if random.randf() < arriving:
			taverns[port_name] = mini(taverns[port_name] + 1, TAVERN_LIMIT)


## Wages fall due every day. Unpaid sailors desert, one a day.
func _pay_crew(delta: float) -> void:
	var days := delta / Calendar.SECONDS_PER_DAY
	# Prize crews are the player's own sailors, and draw their pay.
	var sailors := ship.crew
	for prize in prizes:
		sailors += prize.ship.crew
	purse -= sailors * WAGE * days
	if purse >= 0.0:
		_unpaid_days = 0.0
		return
	purse = 0.0
	_unpaid_days += days
	while _unpaid_days >= 1.0 and ship.crew > 0:
		_unpaid_days -= 1.0
		ship.crew -= 1



# Saving.

## The voyage as plain data for a save file. Not taken inside a battle bubble: bubbles last
## minutes, and the save waits for the ship to be back on the map.
func to_saved() -> Dictionary:
	var saved_markets := {}
	for port_name: String in markets:
		saved_markets[port_name] = markets[port_name].to_saved()
	var saved_captains: Array = []
	for captain in captains:
		saved_captains.append(captain.to_saved(self))
	return {
		"seconds": calendar.seconds, "purse": purse, "renown": renown, "honor": honor,
		"ship": ship.to_saved(), "design_index": design_index,
		"docked": docked.get("name", ""), "unpaid_days": _unpaid_days,
		"markets": saved_markets, "taverns": taverns.duplicate(),
		"captains": saved_captains,
		"prizes": prizes.map(func(prize: Captain) -> Dictionary: return prize.to_saved(self)),
		"autopilot": autopilot.to_saved(self) if autopilot != null else {},
		"random": str(random.state), "news": news, "news_age": news_age,
		"bounty": bounty, "since_pirate": _since_pirate,
		"weather": monsoon.weather.to_saved(),
	}


## Puts a voyage back as it was saved.
func restore(saved: Dictionary) -> void:
	calendar.seconds = saved.seconds
	purse = saved.purse
	renown = saved.renown
	honor = saved.honor
	ship = MapShip.from_saved(saved.ship)
	design_index = int(saved.design_index)
	docked = port_named(saved.docked)
	_unpaid_days = saved.unpaid_days
	for port_name: String in saved.markets:
		markets[port_name].restore(saved.markets[port_name])
	for port_name: String in saved.taverns:
		taverns[port_name] = int(saved.taverns[port_name])
	captains.clear()
	for captain_data: Dictionary in saved.captains:
		captains.append(Captain.from_saved(captain_data, self))
	# Quarries point at other captains, so they're put back once all the captains are.
	for index in captains.size():
		var quarry_index := int(saved.captains[index].quarry)
		if quarry_index >= 0 and quarry_index < captains.size():
			captains[index].quarry = captains[quarry_index]
	prizes.clear()
	for prize_data: Dictionary in saved.get("prizes", []):
		prizes.append(Captain.from_saved(prize_data, self))
	autopilot = null
	if not saved.autopilot.is_empty():
		autopilot = Captain.from_saved(saved.autopilot, self)
		autopilot.ship = ship
		var quarry_index := int(saved.autopilot.quarry)
		if quarry_index >= 0 and quarry_index < captains.size():
			autopilot.quarry = captains[quarry_index]
	monsoon.weather.restore(saved.get("weather", []))
	bounty = saved.get("bounty", 0.0)
	_since_pirate = saved.get("since_pirate", 0.0)
	random.state = int(saved.random)
	news = saved.news
	news_age = saved.news_age
	bubble = null