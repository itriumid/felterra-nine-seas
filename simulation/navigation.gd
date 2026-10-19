class_name Navigation
extends RefCounted
## Plots routes between places on the chart that stay in open water: a search over a coarse grid
## of the sea, then straightened wherever a straight line runs clear. Routes ignore the wind;
## sailing them against it is the captain's job.

## Kilometers per grid cell. Small enough for the narrow straits (Sunda is about 24 kilometers
## across at its narrowest, Singapore about 15), large enough to search quickly.
const CELL_KILOMETERS := 5
## A cell is open water if its center is at least this many kilometers from the coast.
const SEA_ROOM := 2
## Straight legs are checked every this many meters.
const CHECK_SPACING := 400.0

var chart: Chart
var _columns: int
var _rows: int
var _open: PackedByteArray
## How far each cell's center is from the coast, in kilometers, capped.
var _room: PackedByteArray
var _cache := {}
var _edges := {}


func _init(sea_chart: Chart) -> void:
	chart = sea_chart
	_columns = chart.size_in_pixels.x / CELL_KILOMETERS
	_rows = chart.size_in_pixels.y / CELL_KILOMETERS
	_open.resize(_columns * _rows)
	_room.resize(_columns * _rows)
	for row in _rows:
		for column in _columns:
			var pixel := Vector2i(column * CELL_KILOMETERS + CELL_KILOMETERS / 2, row * CELL_KILOMETERS + CELL_KILOMETERS / 2)
			var data := chart.image.get_pixelv(pixel)
			var open_water := data.r < 0.5 and roundi(data.g * 255.0) >= SEA_ROOM
			_open[row * _columns + column] = 1 if open_water else 0
			_room[row * _columns + column] = mini(roundi(data.g * 255.0), 255) if open_water else 0


## Waypoints from one place to another, starting after the start and ending at the finish. Empty
## if there's no way through.
func route(start: Vector2, finish: Vector2) -> Array[Vector2]:
	var key := "%d,%d>%d,%d" % [roundi(start.x), roundi(start.y), roundi(finish.x), roundi(finish.y)]
	if _cache.has(key):
		return _cache[key].duplicate()
	var found := _search(start, finish)
	_cache[key] = found
	return found.duplicate()


## Whether a straight line between two points stays in water with room to spare.
func clear(from: Vector2, to: Vector2, room := 1000.0) -> bool:
	var steps := maxi(ceili(from.distance_to(to) / CHECK_SPACING), 1)
	for index in range(1, steps):
		if chart.signed_distance(from.lerp(to, float(index) / steps)) < room:
			return false
	return true


func _search(start: Vector2, finish: Vector2) -> Array[Vector2]:
	var first := _nearest_open_cell(start)
	var last := _nearest_open_cell(finish)
	if first < 0 or last < 0:
		return []
	# A* over the grid, eight ways, with a binary heap of [estimated total, cell].
	var cost := {first: 0.0}
	var came_from := {}
	var heap: Array = [[0.0, first]]
	var goal := _cell_center(last)
	while not heap.is_empty():
		var current: int = _pop(heap)[1]
		if current == last:
			break
		var column := current % _columns
		var row := current / _columns
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var next_column := column + dx
				var next_row := row + dy
				if next_column < 0 or next_row < 0 or next_column >= _columns or next_row >= _rows:
					continue
				var next := next_row * _columns + next_column
				if _open[next] == 0 or not _edge_clear(current, next):
					continue
				var step := 1.4142 if dx != 0 and dy != 0 else 1.0
				var new_cost: float = cost[current] + step
				if not cost.has(next) or new_cost < cost[next]:
					cost[next] = new_cost
					came_from[next] = current
					var estimate := new_cost + _cell_center(next).distance_to(goal) / (CELL_KILOMETERS * 1000.0)
					_push(heap, [estimate, next])
	if not cost.has(last):
		return []
	var cells: Array[int] = [last]
	while cells[0] != first:
		cells.push_front(came_from[cells[0]])
	var points: Array[Vector2] = [start]
	for cell in cells:
		points.append(_cell_center(cell))
	points.append(finish)
	return _straighten(points)


## Whether a step between two neighboring open cells stays in water. Two cells can each be in
## open water with a headland's tip between them, so steps near the coast are checked along
## their length, once each, on the chart's own pixels.
func _edge_clear(from: int, to: int) -> bool:
	var reach := CELL_KILOMETERS * 2
	if _room[from] >= reach and _room[to] >= reach:
		return true
	var key := mini(from, to) * _open.size() + maxi(from, to)
	if _edges.has(key):
		return _edges[key]
	var start := _cell_center(from)
	var finish := _cell_center(to)
	var clear_water := true
	var steps := ceili(start.distance_to(finish) / 500.0)
	for index in range(1, steps):
		var pixel := Vector2i((start.lerp(finish, float(index) / steps) / Chart.METERS_PER_PIXEL).floor())
		var data := chart.image.get_pixelv(pixel)
		if data.r > 0.5 or roundi(data.g * 255.0) < SEA_ROOM:
			clear_water = false
			break
	_edges[key] = clear_water
	return clear_water


## Drops every waypoint the ship could sail past in a straight line anyway.
func _straighten(points: Array[Vector2]) -> Array[Vector2]:
	var kept: Array[Vector2] = []
	var anchor := 0
	while anchor < points.size() - 1:
		var reach := anchor + 1
		for candidate in range(points.size() - 1, anchor + 1, -1):
			if clear(points[anchor], points[candidate]):
				reach = candidate
				break
		kept.append(points[reach])
		anchor = reach
	return kept


func _nearest_open_cell(world_position: Vector2) -> int:
	var cell_meters := CELL_KILOMETERS * Chart.METERS_PER_PIXEL
	var center := Vector2i((world_position / cell_meters).floor())
	for radius in range(0, 12):
		var best := -1
		var best_distance := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var cell := center + Vector2i(dx, dy)
				if cell.x < 0 or cell.y < 0 or cell.x >= _columns or cell.y >= _rows:
					continue
				var index := cell.y * _columns + cell.x
				if _open[index] == 0:
					continue
				var distance := _cell_center(index).distance_to(world_position)
				if distance < best_distance:
					best_distance = distance
					best = index
		if best >= 0:
			return best
	return -1


func _cell_center(index: int) -> Vector2:
	var cell := Vector2(index % _columns, index / _columns) + Vector2(0.5, 0.5)
	return cell * CELL_KILOMETERS * Chart.METERS_PER_PIXEL


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if heap[parent][0] <= heap[index][0]:
			break
		var swap: Array = heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var index := 0
	while true:
		var smallest := index
		for child in [index * 2 + 1, index * 2 + 2]:
			if child < heap.size() and heap[child][0] < heap[smallest][0]:
				smallest = child
		if smallest == index:
			break
		var swap: Array = heap[smallest]
		heap[smallest] = heap[index]
		heap[index] = swap
		index = smallest
	return top
