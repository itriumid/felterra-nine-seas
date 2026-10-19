class_name ShipView
extends Node2D
## Draws a ship from its simulation state every frame instead of from sprites. The hull and
## sails are polygons rasterized straight onto the low-resolution screen, so they stay crisp at
## any heading, and the sails show their real trim: where they sit, how full they are, whether
## they're luffing or taken aback.

var ship: Ship
var pixels_per_meter := 2.0
## World position drawn at the screen's top-left, so the view never handles huge coordinates.
var origin := Vector2.ZERO

var _flutter_time := 0.0


func _process(delta: float) -> void:
	if ship == null:
		return
	_flutter_time += delta
	position = ((ship.position - origin) * pixels_per_meter).floor()
	rotation = ship.heading
	queue_redraw()


func _draw() -> void:
	if ship == null:
		return
	var design := ship.design
	var half_length := design.length_overall / 2.0 * pixels_per_meter
	var half_beam := design.beam / 2.0 * pixels_per_meter

	var hull := _hull_outline(half_length, half_beam)
	draw_colored_polygon(hull, Palette.HULL)
	var deck := PackedVector2Array()
	for point in hull:
		deck.append(Vector2(point.x * 0.86 - 0.5, point.y * 0.7))
	draw_colored_polygon(deck, Palette.DECK)
	draw_line(Vector2(-half_length * 0.7, 0.0), Vector2(half_length * 0.5, 0.0), Palette.DECK_LIGHT)
	var closed := hull.duplicate()
	closed.append(hull[0])
	draw_polyline(closed, Palette.HULL_SHADOW)

	# Heeling leans the masts to leeward, and the sails high on them shift with it.
	var lean := Vector2(0.0, sin(ship.heel) * design.beam * 0.8 * pixels_per_meter)
	for mast in design.masts:
		draw_rect(Rect2(Vector2(mast * pixels_per_meter, 0.0) - Vector2.ONE, Vector2(2.0, 2.0)), Palette.SPAR)

	if design.rig == ShipDesign.Rig.FORE_AND_AFT:
		_draw_fore_and_aft_sails(half_length, lean)
	else:
		_draw_square_sails(half_beam, lean)

	_draw_pennant(Vector2(design.masts[0] * pixels_per_meter, 0.0) + lean)


func _hull_outline(half_length: float, half_beam: float) -> PackedVector2Array:
	var starboard_side: Array[Vector2] = [
		Vector2(half_length, 0.0),
		Vector2(half_length * 0.7, half_beam * 0.55),
		Vector2(half_length * 0.35, half_beam * 0.95),
		Vector2(-half_length * 0.2, half_beam),
		Vector2(-half_length * 0.75, half_beam * 0.88),
		Vector2(-half_length, half_beam * 0.6),
	]
	var outline := PackedVector2Array(starboard_side)
	for index in range(starboard_side.size() - 1, 0, -1):
		var point := starboard_side[index]
		outline.append(Vector2(point.x, -point.y))
	return outline


## How full a sail looks: full when drawing, rippling when it luffs, empty when furled.
func _fullness(phase: float) -> float:
	var flutter := sin(_flutter_time * 24.0 + phase) * 0.5
	return ship.sail_set * lerpf(1.0, flutter, ship.luffing)


func _draw_fore_and_aft_sails(half_length: float, lean: Vector2) -> void:
	var design := ship.design
	var swing := absf(ship.sail_angle)
	var side := signf(ship.sail_angle) if ship.sail_angle != 0.0 else 1.0

	# Jib, set from the bowsprit, sheeted a little wider than the mainsail.
	var bowsprit := Vector2(half_length * 1.25, 0.0)
	draw_line(Vector2(half_length, 0.0), bowsprit, Palette.SPAR)
	var jib_swing := minf(swing + deg_to_rad(4.0), design.sail_angle_maximum)
	var jib_side := side
	var jib_fullness := _fullness(1.3)
	if ship.backing_headsails:
		# Held out to windward, with the wind filling it from the wrong side.
		jib_swing = design.backed_headsail_angle
		jib_side = -side
		jib_fullness = -ship.sail_set
	var jib_length := design.length_overall * 0.32 * pixels_per_meter
	_draw_sail(bowsprit, bowsprit + lean * 0.6, jib_swing, jib_side, jib_length, 0.85, jib_fullness, false)

	var mast := Vector2(design.masts[0] * pixels_per_meter, 0.0)
	var boom_length := design.length_overall * 0.55 * pixels_per_meter
	_draw_sail(mast, mast + lean, swing, side, boom_length, 0.8, _fullness(0.0), true)


func _draw_square_sails(half_beam: float, lean: Vector2) -> void:
	var swing := absf(ship.sail_angle)
	var side := signf(ship.sail_angle) if ship.sail_angle != 0.0 else 1.0
	# Taken aback, the wind fills the sails from the front and they belly the other way.
	var belly := -1.0 if ship.aback else 1.0
	for index in ship.design.masts.size():
		var mast := Vector2(ship.design.masts[index] * pixels_per_meter, 0.0)
		var yard := half_beam * (1.6 if index == 0 else 1.75)
		var mast_swing := swing
		var mast_side := side
		var mast_belly := belly
		if index == 0 and ship.backing_headsails:
			# Foremast braced round the other way, its sails pressed back against the mast.
			mast_swing = ship.design.backed_headsail_angle
			mast_side = -side
			mast_belly = -1.0
		# Course, topsail and topgallant, each higher, shorter and leaning further.
		for tier in 3:
			var height := float(tier + 1) / 3.0
			var center := mast + lean * height
			var half_yard := yard * (1.0 - 0.22 * tier)
			var depth := mast_belly * 0.22 * _fullness(index * 2.1 + tier)
			_draw_square_sail(center, half_yard, mast_swing, mast_side, depth)


func _draw_square_sail(center: Vector2, half_yard: float, swing: float, side: float, depth: float) -> void:
	var chord := Vector2(-cos(swing), sin(swing) * side)
	var normal := Vector2(sin(swing), cos(swing) * side)
	var start := center - chord * half_yard
	var finish := center + chord * half_yard
	if ship.sail_set > 0.05 and absf(depth) * half_yard >= 0.5:
		var curve := PackedVector2Array()
		for index in 9:
			var along := float(index) / 8.0
			curve.append(start.lerp(finish, along) + normal * half_yard * 2.0 * depth * sin(PI * along))
		var shape := PackedVector2Array([start])
		shape.append_array(curve)
		_fill(shape, Palette.SAIL)
		draw_polyline(curve, Palette.SAIL_SHADOW)
	draw_line(start, finish, Palette.SPAR)


## A fore-and-aft sail seen from above: the boom at the foot, and the head twisted further out
## and leaning with the heel. The cloth between them, bellied to leeward, is what shows.
func _draw_sail(foot: Vector2, head: Vector2, swing: float, side: float, length: float, head_ratio: float, fullness: float, with_spar: bool) -> void:
	var foot_chord := Vector2(-cos(swing), sin(swing) * side)
	var twist := minf(swing + deg_to_rad(10.0) * fullness, PI / 2.0)
	var head_chord := Vector2(-cos(twist), sin(twist) * side)
	var head_normal := Vector2(sin(twist), cos(twist) * side)
	var foot_end := foot + foot_chord * length
	if ship.sail_set > 0.05:
		var shape := PackedVector2Array([foot, foot_end])
		var leech := PackedVector2Array()
		var segments := 8
		for index in range(segments, -1, -1):
			var along := float(index) / float(segments)
			var point := head + head_chord * length * head_ratio * along
			leech.append(point + head_normal * length * 0.12 * fullness * sin(PI * along))
		shape.append_array(leech)
		_fill(shape, Palette.SAIL)
		draw_polyline(leech, Palette.SAIL_SHADOW)
		draw_line(foot_end, leech[0], Palette.SAIL_SHADOW)
	if with_spar:
		draw_line(foot, foot_end, Palette.SPAR)


## Fills a polygon unless it has collapsed into a line, which happens for a moment whenever a
## sail swings through the centerline.
func _fill(shape: PackedVector2Array, color: Color) -> void:
	if not Geometry2D.triangulate_polygon(shape).is_empty():
		draw_colored_polygon(shape, color)


## A long pennant at the masthead, streaming with the apparent wind: the same telltale real
## sailors read.
func _draw_pennant(masthead: Vector2) -> void:
	var flow := ship.apparent_wind.rotated(-ship.heading)
	if flow.length_squared() < 0.01:
		return
	var direction := flow.normalized()
	var across := direction.orthogonal()
	var points := PackedVector2Array()
	var spacing := 0.8 * pixels_per_meter
	for index in 6:
		var along := float(index) * spacing
		var wave := sin(_flutter_time * 14.0 - index * 1.2) * 0.15 * index * spacing
		points.append(masthead + direction * along + across * wave)
	draw_polyline(points, Palette.PLAYER)
	draw_rect(Rect2(masthead - Vector2.ONE, Vector2(2.0, 2.0)), Palette.PLAYER_EDGE)
