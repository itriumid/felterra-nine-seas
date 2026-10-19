class_name Chart
extends RefCounted
## The sea the world map sails on, built from real coastlines by tools/build_world_map.py: one
## pixel per kilometer, plate carree. Positions are meters from the chart's top-left corner.

# Keep in step with tools/build_world_map.py.
const WEST := 95.0
const NORTH := 8.0
const KILOMETERS_PER_DEGREE_LONGITUDE := 111.32
const KILOMETERS_PER_DEGREE_LATITUDE := 110.57
const METERS_PER_PIXEL := 1000.0
const IMAGE_PATH := "res://world/nusantara.png"

var texture: Texture2D
var image: Image
var size_in_pixels: Vector2i


func _init() -> void:
	texture = load(IMAGE_PATH)
	image = texture.get_image()
	size_in_pixels = image.get_size()


func size_in_meters() -> Vector2:
	return Vector2(size_in_pixels) * METERS_PER_PIXEL


static func position_of(latitude: float, longitude: float) -> Vector2:
	return Vector2(
		(longitude - WEST) * KILOMETERS_PER_DEGREE_LONGITUDE,
		(NORTH - latitude) * KILOMETERS_PER_DEGREE_LATITUDE
	) * METERS_PER_PIXEL


static func latitude_at(world_position: Vector2) -> float:
	return NORTH - world_position.y / METERS_PER_PIXEL / KILOMETERS_PER_DEGREE_LATITUDE


static func longitude_at(world_position: Vector2) -> float:
	return WEST + world_position.x / METERS_PER_PIXEL / KILOMETERS_PER_DEGREE_LONGITUDE


func contains(world_position: Vector2) -> bool:
	var pixel := _pixel(world_position)
	return pixel.x >= 0 and pixel.y >= 0 and pixel.x < size_in_pixels.x and pixel.y < size_in_pixels.y


## Land, or off the edge of the chart: anywhere a ship can't go.
func is_land(world_position: Vector2) -> bool:
	if not contains(world_position):
		return true
	return signed_distance(world_position) < 0.0


## Meters to the coast, positive at sea and negative on land. The chart only knows the coast to
## a kilometer, so this blends smoothly between its pixels and adds noise for coves and points.
## game/world.gdshader draws the coast from exactly the same calculation, so what the player
## sees is what a ship runs aground on: change one, change both.
func signed_distance(world_position: Vector2) -> float:
	return smooth_distance(world_position) + coast_detail(world_position / METERS_PER_PIXEL) * METERS_PER_PIXEL


## The chart's own coast, blended smoothly between its pixels, before any detail is added. In
## meters, positive at sea.
func smooth_distance(world_position: Vector2) -> float:
	var local := world_position / METERS_PER_PIXEL - Vector2(0.5, 0.5)
	var cell := local.floor()
	var weight := local - cell
	var origin := Vector2i(cell)
	var rows := PackedFloat32Array()
	for row in range(-1, 3):
		rows.append(catmull_rom(
			_texel_distance(origin + Vector2i(-1, row)), _texel_distance(origin + Vector2i(0, row)),
			_texel_distance(origin + Vector2i(1, row)), _texel_distance(origin + Vector2i(2, row)),
			weight.x))
	return catmull_rom(rows[0], rows[1], rows[2], rows[3], weight.y) * METERS_PER_PIXEL


## A smooth curve through four evenly spaced values, at a point between the middle two.
static func catmull_rom(before: float, start: float, finish: float, after: float, weight: float) -> float:
	var squared := weight * weight
	return 0.5 * (
		2.0 * start
		+ (finish - before) * weight
		+ (2.0 * before - 5.0 * start + 4.0 * finish - after) * squared
		+ (3.0 * start - before - 3.0 * finish + after) * squared * weight
	)


## Kilometers of wander added to the coast: broad bays and headlands, then coves, then rocks.
static func coast_detail(chart_coordinate: Vector2) -> float:
	return (
		(smooth_noise(chart_coordinate * 4.0) - 0.5) * 0.3
		+ (smooth_noise(chart_coordinate * 16.0) - 0.5) * 0.12
		+ (smooth_noise(chart_coordinate * 64.0) - 0.5) * 0.04
	)


## Value noise on an integer lattice, matching the shader's bit for bit up to float rounding.
static func smooth_noise(point: Vector2) -> float:
	var cell := point.floor()
	var fraction := point - cell
	var blend := fraction * fraction * (Vector2(3.0, 3.0) - 2.0 * fraction)
	var x := int(cell.x)
	var y := int(cell.y)
	return lerpf(
		lerpf(_lattice(x, y), _lattice(x + 1, y), blend.x),
		lerpf(_lattice(x, y + 1), _lattice(x + 1, y + 1), blend.x),
		blend.y)


## A hash of a lattice point to 0..1, in 32-bit unsigned arithmetic like the shader's.
static func _lattice(x: int, y: int) -> float:
	var hash_value := (x * 374761393 + y * 668265263) & 0xFFFFFFFF
	hash_value = ((hash_value ^ (hash_value >> 13)) * 1274126177) & 0xFFFFFFFF
	hash_value = hash_value ^ (hash_value >> 16)
	return float(hash_value & 0xFFFFFF) / 16777215.0


## A chart pixel's distance to the coast in kilometers, measured from its center: half a pixel
## less than the stored count, negative on land. Off the chart is open sea.
func _texel_distance(pixel: Vector2i) -> float:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= size_in_pixels.x or pixel.y >= size_in_pixels.y:
		return 255.0
	var data := image.get_pixelv(pixel)
	var distance := roundf(data.g * 255.0) - 0.5
	return -distance if data.r > 0.5 else distance


## Kilometers to the nearest coast, up to 255, on either side of it.
func coast_distance(world_position: Vector2) -> int:
	if not contains(world_position):
		return 255
	return roundi(image.get_pixelv(_pixel(world_position)).g * 255.0)


## The nearest open water within a radius, for putting ports and ships where they can float.
func nearest_water(world_position: Vector2, radius_in_pixels := 40) -> Vector2:
	var center := _pixel(world_position)
	var best := world_position
	var best_distance := INF
	for dy in range(-radius_in_pixels, radius_in_pixels + 1):
		for dx in range(-radius_in_pixels, radius_in_pixels + 1):
			var pixel := center + Vector2i(dx, dy)
			var candidate := (Vector2(pixel) + Vector2(0.5, 0.5)) * METERS_PER_PIXEL
			if is_land(candidate):
				continue
			var distance := Vector2(dx, dy).length()
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best


func _pixel(world_position: Vector2) -> Vector2i:
	return Vector2i((world_position / METERS_PER_PIXEL).floor())
