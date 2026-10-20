class_name Weather
extends RefCounted
## Squalls and gales moving over the Nusantara seas, on top of the monsoon.
##
## A squall is a sudden local blow, a few kilometers to fifteen across, that rises to 30 or 35
## knots and dies away within a couple of hours as it travels with the wind. They're most common
## when the monsoons change, and at night in the Malacca Strait during the southwest monsoon:
## the "Sumatras" that sweep across from Sumatra. A gale is a great area of strong wind, a
## hundred kilometers or more across, blowing for a day or two at the height of a monsoon.
##
## Each is a cell: the wind inside is the monsoon plus the cell's own push, strongest at its
## heart and in the middle of its life.

enum Kind { SQUALL, GALE }

## Squalls born a day across the whole chart, and the most cells at once.
const SQUALLS_A_DAY := 60.0
## Gales born a day across the chart, at the height of a monsoon.
const GALES_A_DAY := 0.15
const MOST_CELLS := 32
## Where the Sumatras blow: the Malacca Strait, between these latitudes and longitudes.
const STRAIT_LATITUDES := Vector2(0.5, 6.0)
const STRAIT_LONGITUDES := Vector2(97.0, 104.0)

## Each cell: {kind, center (meters), velocity (meters a second), radius (meters), push
## (meters a second, the wind it adds at its heart), direction (the way its wind blows), age and
## life (seconds)}.
var cells: Array[Dictionary] = []


## The wind a cell adds at a point, given the monsoon's own wind there.
func push_at(world_position: Vector2) -> Vector2:
	var total := Vector2.ZERO
	for cell in cells:
		var strength := _strength(cell, world_position)
		if strength > 0.0:
			total += (cell.direction as Vector2) * cell.push * strength
	return total


## The strongest weather at a point, as the name a sailor would give it, or empty in fair
## weather.
func conditions_at(world_position: Vector2) -> String:
	var squall := 0.0
	var gale := 0.0
	for cell in cells:
		var strength := _strength(cell, world_position)
		if cell.kind == Kind.SQUALL:
			squall = maxf(squall, strength)
		else:
			gale = maxf(gale, strength)
	if gale > 0.3:
		return "Gale"
	if squall > 0.3:
		return "Squall"
	if gale > 0.05 or squall > 0.05:
		return "Wind rising"
	return ""


## How hard a cell blows at a point, 0 to 1: strongest at its heart, and in the middle of its
## life, rising and falling away smoothly.
func _strength(cell: Dictionary, world_position: Vector2) -> float:
	var distance: float = (cell.center as Vector2).distance_to(world_position)
	if distance >= cell.radius:
		return 0.0
	var across := 1.0 - pow(distance / cell.radius, 2.0)
	return across * across * sin(PI * clampf(cell.age / cell.life, 0.0, 1.0))


func advance(delta: float, monsoon: Monsoon, chart: Chart, random: RandomNumberGenerator) -> void:
	var lasting: Array[Dictionary] = []
	for cell in cells:
		cell.age += delta
		cell.center += (cell.velocity as Vector2) * delta
		if cell.age < cell.life:
			lasting.append(cell)
	cells = lasting
	if cells.size() >= MOST_CELLS:
		return
	var days := delta / Calendar.SECONDS_PER_DAY
	var season := monsoon.season()
	# Squalls come thickest when the monsoons change, gales at their height.
	var changing := 1.0 - absf(season)
	if random.randf() < SQUALLS_A_DAY * (0.6 + changing) * days:
		_spawn(Kind.SQUALL, monsoon, chart, random)
	if absf(season) > 0.6 and random.randf() < GALES_A_DAY * days:
		_spawn(Kind.GALE, monsoon, chart, random)
	if _sumatras_season(monsoon) and random.randf() < SQUALLS_A_DAY * 0.5 * days:
		_spawn_sumatra(monsoon, chart, random)


## Southwest monsoon nights, when the Sumatras blow across the Malacca Strait.
func _sumatras_season(monsoon: Monsoon) -> bool:
	var hour := fmod(monsoon.calendar.seconds / 3600.0, 24.0)
	return monsoon.season() < -0.5 and (hour > 20.0 or hour < 6.0)


func _spawn(kind: Kind, monsoon: Monsoon, chart: Chart, random: RandomNumberGenerator) -> void:
	var size := chart.size_in_meters()
	for attempt in 10:
		var center := Vector2(random.randf() * size.x, random.randf() * size.y)
		if not chart.is_land(center):
			_add(kind, center, monsoon, random)
			return


## A Sumatra: born over the strait's Sumatran shore and driven across it by the monsoon.
func _spawn_sumatra(monsoon: Monsoon, chart: Chart, random: RandomNumberGenerator) -> void:
	for attempt in 10:
		var center := Chart.position_of(
			random.randf_range(STRAIT_LATITUDES.x, STRAIT_LATITUDES.y),
			random.randf_range(STRAIT_LONGITUDES.x, STRAIT_LONGITUDES.y))
		if not chart.is_land(center):
			_add(Kind.SQUALL, center, monsoon, random)
			return


func _add(kind: Kind, center: Vector2, monsoon: Monsoon, random: RandomNumberGenerator) -> void:
	var wind := monsoon.base_velocity_at(center)
	var direction := wind.normalized() if wind.length_squared() > 0.01 else Vector2.from_angle(random.randf() * TAU)
	var squall := kind == Kind.SQUALL
	cells.append({
		"kind": kind,
		"center": center,
		# Squalls race along with the wind; gales drift slowly.
		"velocity": direction * (random.randf_range(6.0, 10.0) if squall else random.randf_range(1.5, 3.0)),
		"radius": random.randf_range(6000.0, 15000.0) if squall else random.randf_range(100000.0, 200000.0),
		"push": random.randf_range(8.0, 12.0) if squall else random.randf_range(10.0, 16.0),
		"direction": direction,
		"age": 0.0,
		"life": random.randf_range(1.5, 3.0) * 3600.0 if squall else random.randf_range(24.0, 48.0) * 3600.0,
	})


func to_saved() -> Array:
	var saved: Array = []
	for cell in cells:
		saved.append({
			"kind": cell.kind, "center": [cell.center.x, cell.center.y],
			"velocity": [cell.velocity.x, cell.velocity.y], "radius": cell.radius, "push": cell.push,
			"direction": [cell.direction.x, cell.direction.y], "age": cell.age, "life": cell.life,
		})
	return saved


func restore(saved: Array) -> void:
	cells.clear()
	for cell: Dictionary in saved:
		cells.append({
			"kind": int(cell.kind), "center": Vector2(cell.center[0], cell.center[1]),
			"velocity": Vector2(cell.velocity[0], cell.velocity[1]), "radius": cell.radius,
			"push": cell.push, "direction": Vector2(cell.direction[0], cell.direction[1]),
			"age": cell.age, "life": cell.life,
		})
