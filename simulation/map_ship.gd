class_name MapShip
extends RefCounted
## A ship crossing the world map. At this scale a voyage takes days, so instead of stepping
## the full physics sixty times a second, the ship settles toward the steady speed the same
## physics gives for its heading and wind: the speed polar. Same model, a different clock.

## Seconds of game time a ship takes to settle to a new speed.
const SETTLING_TIME := 600.0

var design: ShipDesign
var position := Vector2.ZERO
var heading := 0.0
var speed := 0.0
var aground := false
## How much sail is set, 0 (furled) to 1 (all plain sail). A sailing ship's only throttle.
var sail_set := 1.0
## Tons of each good in the hold, by good identifier.
var hold := {}
var crew := 0
## Soundness of the hull, 1 for new; collisions knock it down and a shipyard repairs it.
var hull := 1.0
## Barnacles and weed, 0 for a clean bottom; each unit doubles the hull's friction.
var fouling := 0.0
## Guns mounted, both sides together.
var guns := 0
## Soundness of masts, yards and sails, 1 for new; chain shot cuts it, and the ship can carry
## only that share of its sail.
var rigging := 1.0

## Set when she's carrying more sail than the wind allows, and straining for it.
var overpressed := false
## How fast a ship carrying too much sail wears out, per hour, for each time over what she can
## stand: blown-out sails and sprung spars, and the hull working under the strain.
const RIGGING_STRAIN := 0.2
const HULL_STRAIN := 0.03

## Days at sea for a clean hull to foul enough to double its friction. Tropical water is hard on
## a wooden bottom; ships were hauled out and scraped every few months.
const FOULING_DAYS := 60.0


func _init(ship_design: ShipDesign) -> void:
	design = ship_design
	crew = design.crew_minimum


func cargo_tons() -> int:
	var total := 0
	for id in hold:
		total += hold[id]
	return total


func free_tons() -> int:
	return int(design.cargo_capacity) - cargo_tons()


## Kilograms aboard beyond the empty ship: cargo and guns.
func carried_mass() -> float:
	return cargo_tons() * 1000.0 + guns * ShipDesign.GUN_MASS


## What's aboard as a fraction of the hold's capacity, which is how the speed polars are keyed.
## Guns count: they weigh the ship down like cargo.
func cargo_load() -> float:
	return clampf(carried_mass() / (design.cargo_capacity * 1000.0), 0.0, 1.0)


## The sail the crew can actually handle: short of the minimum crew, not all of it.
## The most sail she can carry in a wind without straining, rounded down to a quarter: the
## force on the sails grows with the square of the wind.
func prudent_sail(wind_speed: float) -> float:
	var limit := pow(design.full_sail_wind / maxf(wind_speed, 0.1), 2.0)
	return clampf(floorf(limit * 4.0) / 4.0, 0.25, 1.0)


func handled_sail() -> float:
	return minf(minf(sail_set, float(crew) / design.crew_minimum), rigging)


func forward() -> Vector2:
	return Vector2.from_angle(heading)


func step(delta: float, true_wind: Vector2, chart: Chart) -> void:
	var angle_off_wind := rad_to_deg(absf(forward().angle_to(-true_wind)))
	# Drive grows with sail area and drag with the square of speed, so speed goes with the square
	# root of the sail set: half sail is about seven tenths of full speed. Fouling multiplies the
	# hull's friction, which is about half its resistance at a sailing pace.
	var polar := maxf(Polar.lookup(design.id, angle_off_wind, true_wind.length(), cargo_load()), 0.0)
	var target := polar * sqrt(handled_sail()) / sqrt(1.0 + 0.5 * fouling)
	fouling += delta / (FOULING_DAYS * Calendar.SECONDS_PER_DAY)
	# Too much sail for the wind strains the rigging, and in the worst of it the hull.
	var pressure := handled_sail() * pow(true_wind.length() / design.full_sail_wind, 2.0)
	overpressed = pressure > 1.0
	if overpressed:
		var hours := delta / 3600.0
		rigging = maxf(rigging - (pressure - 1.0) * RIGGING_STRAIN * hours, 0.1)
		hull = maxf(hull - (pressure - 1.0) * HULL_STRAIN * hours, 0.1)
	speed = lerpf(speed, target, 1.0 - exp(-delta / SETTLING_TIME))
	var next := position + forward() * speed * delta
	aground = chart.is_land(next)
	if aground:
		speed = 0.0
	else:
		position = next



## Everything about the ship worth keeping, as plain data for a save file.
func to_saved() -> Dictionary:
	return {
		"design": design.id, "position": [position.x, position.y], "heading": heading,
		"speed": speed, "aground": aground, "sail_set": sail_set, "hold": hold.duplicate(), "crew": crew,
		"hull": hull, "fouling": fouling, "guns": guns, "rigging": rigging,
	}


static func from_saved(saved: Dictionary) -> MapShip:
	var ship := MapShip.new(ShipDesign.named(saved.design))
	ship.position = Vector2(saved.position[0], saved.position[1])
	ship.heading = saved.heading
	ship.speed = saved.speed
	# A grounded captain steers to get off, so it's part of what happens next.
	ship.aground = saved.aground
	ship.sail_set = saved.sail_set
	for id: String in saved.hold:
		# Save files store numbers as decimals; tons are whole.
		ship.hold[id] = int(saved.hold[id])
	ship.crew = int(saved.crew)
	ship.hull = saved.hull
	ship.fouling = saved.fouling
	ship.guns = int(saved.guns)
	ship.rigging = saved.rigging
	return ship