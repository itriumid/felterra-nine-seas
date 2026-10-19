class_name Gunnery
extends RefCounted
## Broadsides inside a battle bubble: every gun on one side fires at once, each ball flies on
## its own, and the guns take a minute to reload, longer with too few hands.
##
## Balls fly flat at a few hundred meters a second. The gun captains lay their guns for the
## range to the target, and each ball falls somewhere around that range and a little off the
## line, more so the further it goes; whatever hull lies under its path before it falls, it
## hits. Round shot holes hulls, chain shot cuts rigging, grapeshot kills crews at close range.

enum Shot { ROUND, CHAIN, GRAPE }

const SHOT_NAMES: Array[String] = ["round shot", "chain shot", "grapeshot"]
## A well-drilled crew runs out, fires and reloads a broadside in about a minute.
const RELOAD_SECONDS := 60.0
## Hands to serve one gun. Crews shift to whichever side is fighting.
const GUN_CREW := 4
## Average speed of a ball over its flight, in meters a second.
const BALL_SPEED := 300.0
## Furthest each kind of shot carries, in meters.
const RANGE: Array[float] = [900.0, 500.0, 250.0]
## How far off the line each kind of shot strays, in degrees, and how much it falls short or
## long, as a share of the range.
const SPREAD: Array[float] = [1.5, 2.5, 6.0]
const RANGE_SPREAD := 0.08
## Grapeshot is a canister of small balls; each gun throws a handful.
const BALLS_PER_GUN: Array[int] = [1, 1, 6]
## A gun bears on a target within this many degrees of straight out from its side.
const ARC := 25.0
## What one ball does, to a ship of the reference mass; heavier ships take less from each.
const REFERENCE_MASS := 60000.0
const HULL_PER_ROUND_SHOT := 0.015
const RIGGING_PER_CHAIN_SHOT := 0.05
const CREW_KILLED_PER_GRAPE := 0.35
const CREW_KILLED_PER_ROUND_SHOT := 0.25

## Per ship: seconds until each side is loaded again, by side (-1 port, 1 starboard), and the
## shot loaded next.
var reloading := {}
var shot := {}
var balls: Array[Dictionary] = []
## Firings, splashes and hits since the view last looked, for drawing smoke and spray.
var events: Array[Dictionary] = []
var random := RandomNumberGenerator.new()


func _init(seed_value := 39) -> void:
	random.seed = seed_value


func shot_of(ship: Ship) -> Shot:
	return shot.get(ship, Shot.ROUND)


func cycle_shot(ship: Ship) -> void:
	shot[ship] = (shot_of(ship) + 1) % SHOT_NAMES.size()


## Seconds until a side is loaded; zero when it's ready.
func reload_left(ship: Ship, side: int) -> float:
	return reloading.get(ship, {}).get(side, 0.0)


## Which side of a ship a point lies on: 1 for starboard, -1 for port.
static func side_toward(ship: Ship, point: Vector2) -> int:
	return 1 if (point - ship.position).dot(ship.starboard()) >= 0.0 else -1


## Whether a side's guns can be laid on a point.
static func bears(ship: Ship, side: int, point: Vector2) -> bool:
	var outward := ship.starboard() * side
	return absf(outward.angle_to(point - ship.position)) <= deg_to_rad(ARC)


static func guns_per_side(map_ship: MapShip) -> int:
	return map_ship.guns / 2


## Fires one side's guns at a point. Each gun is trained on it with handspikes, as far as the gun
## port allows (ARC either way of straight out), and laid for its range. Returns false if the
## side isn't loaded or has no guns.
func fire(ship: Ship, map_ship: MapShip, side: int, target: Vector2) -> bool:
	var guns := guns_per_side(map_ship)
	if guns == 0 or reload_left(ship, side) > 0.0 or map_ship.crew == 0:
		return false
	var kind := shot_of(ship)
	var outward := ship.starboard() * side
	for gun in guns:
		var along := (float(gun) / maxf(guns - 1, 1) - 0.5) * ship.design.length_overall * 0.6
		var muzzle := ship.position + ship.forward() * along + outward * ship.design.beam / 2.0
		var training := clampf(outward.angle_to(target - muzzle), -deg_to_rad(ARC), deg_to_rad(ARC))
		var trained := outward.rotated(training)
		var laid := clampf(muzzle.distance_to(target), 30.0, RANGE[kind])
		events.append({"kind": "fire", "position": muzzle, "direction": trained})
		for ball in BALLS_PER_GUN[kind]:
			var direction := trained.rotated(deg_to_rad(random.randfn(0.0, SPREAD[kind])))
			balls.append({
				"position": muzzle,
				"velocity": direction * BALL_SPEED + ship.velocity,
				"travelled": 0.0,
				"falls_at": minf(laid * (1.0 + random.randfn(0.0, RANGE_SPREAD)), RANGE[kind]),
				"shooter": ship,
				"shot": kind,
			})
	# Crews too small for every gun on a side reload more slowly.
	var hands_short := float(guns * GUN_CREW) / maxf(map_ship.crew, 1.0)
	if not reloading.has(ship):
		reloading[ship] = {}
	reloading[ship][side] = RELOAD_SECONDS * maxf(1.0, hands_short)
	return true


## Moves every ball one step; calls hit(target, shot) for each that strikes a hull.
func advance(delta: float, ships: Array[Ship], hit: Callable) -> void:
	for ship in reloading:
		for side in reloading[ship]:
			reloading[ship][side] = maxf(reloading[ship][side] - delta, 0.0)
	var flying: Array[Dictionary] = []
	for ball in balls:
		var from: Vector2 = ball.position
		var step: Vector2 = ball.velocity * delta
		var remaining: float = ball.falls_at - ball.travelled
		if step.length() > remaining:
			step = step.normalized() * remaining
		var to := from + step
		var struck := _struck_ship(from, to, ships, ball.shooter)
		if struck != null:
			hit.call(struck, ball.shot)
			events.append({"kind": "hit", "position": to, "direction": step.normalized()})
			continue
		ball.position = to
		ball.travelled += step.length()
		if ball.travelled >= ball.falls_at - 0.01:
			events.append({"kind": "splash", "position": to, "direction": step.normalized()})
			continue
		flying.append(ball)
	balls = flying


func _struck_ship(from: Vector2, to: Vector2, ships: Array[Ship], shooter: Ship) -> Ship:
	for ship in ships:
		if ship == shooter:
			continue
		var along := ship.forward() * ship.design.length_overall * 0.3
		for center in [ship.position + along, ship.position, ship.position - along]:
			var closest := Geometry2D.get_closest_point_to_segment(center, from, to)
			if closest.distance_to(center) <= ship.design.beam / 2.0:
				return ship
	return null
