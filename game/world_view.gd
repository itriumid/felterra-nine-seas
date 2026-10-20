class_name WorldView
extends Node2D

## The player's ship has just come in and moored: a good moment to save.
signal moored
## The one view of the game: the Nusantara seas at any zoom, from the whole chart down to the
## ship's deck. The world runs on one clock, ten minutes a second, for every player; zooming only
## changes what you see.

## Game seconds per real second. Fixed: in a shared world every player is on the same clock.
## Ten minutes a second: Batavia to Semarang takes about four minutes, a day two and a half,
## and a monsoon season a few hours of play.
const TIME_SCALE := 600.0
## Meters per screen pixel, from the whole chart down to the ship. Every level keeps screen
## pixels one size; zooming changes how much world each one covers.
const ZOOM_LEVELS: Array[float] = [4000.0, 2000.0, 1000.0, 400.0, 100.0, 25.0, 6.0, 2.0, 1.0, 0.5, 1.0 / 3.0]
const DEFAULT_ZOOM := 2
## Below this many meters a pixel, the ship is drawn at its true size instead of as a symbol.
const TRUE_SIZE_BELOW := 2.5
## How fast the helm turns the ship, in degrees per real second: the crew's turn rate on the
## world clock, so taking over from them or handing back never jumps.
const TURN_RATE := 10.0 / 60.0 * TIME_SCALE
## The longest stretch of game time stepped at once, so ships can't jump across a spit of land.
const LONGEST_STEP := 120.0
## Ships closer than this are reported as sighted.
const SIGHTING_RANGE := 20000.0
## The zoom a bubble opens at: half a meter a pixel, close enough to see the sails work.
const BUBBLE_ZOOM := 9
## How fast the rudder moves toward where it's pushed inside a bubble, in full sweeps per second.
const HELM_RATE := 2.5
## How fast manual trim moves the sails inside a bubble, as a fraction of their range per second.
const SHEET_RATE := 0.35
## Seconds a collision stays reported.
const COLLISION_NOTICE := 2.0
## Pixels around a ship symbol that count as clicking it.
const CLICK_REACH := 8.0
## Game seconds between dots of the ship's track.
const TRACK_INTERVAL := 1800.0
const TRACK_LENGTH := 3000

var voyage: Voyage
var zoom_index := DEFAULT_ZOOM

var _material: ShaderMaterial
var _display: MapDisplay
var _interface_layer: CanvasLayer
var _port_screen: PortScreen
var _plunder_screen: PlunderScreen
## True-size views of ships near the player, the player's first, reused frame to frame.
var _ship_views: Array[ShipView] = []
## Full-physics ships posed to match map ships, so they can be drawn at true size.
var _poses := {}
var _water_offset := Vector2.ZERO
var _wave_time := 0.0
var _track: Array[Vector2] = []
var _since_track := 0.0
## The bubble being drawn, its ships' wakes, and the zoom to go back to when it closes.
var _bubble: Bubble
var _wakes: Array[WakeView] = []
var _effects: EffectsView
var _zoom_before_bubble := DEFAULT_ZOOM
var _collisions_seen := 0


func _ready() -> void:
	var sea_layer := CanvasLayer.new()
	sea_layer.layer = -1
	add_child(sea_layer)
	_material = ShaderMaterial.new()
	_material.shader = load("res://game/world.gdshader")
	_material.set_shader_parameter("chart", voyage.chart.texture)
	var colors := {
		"deep_color": Palette.DEEP_WATER, "slope_color": Palette.SWELL, "water_color": Palette.WATER,
		"swell_color": Palette.SWELL, "ripple_color": Palette.RIPPLE, "foam_color": Palette.FOAM_FADING,
		"crest_color": Palette.FOAM_FADING, "shallows_color": Palette.SHALLOWS,
		"shallows_light_color": Palette.SHALLOWS_LIGHT, "sand_color": Palette.SAND,
		"grass_color": Palette.GRASS, "forest_color": Palette.FOREST,
		"forest_dark_color": Palette.FOREST_DARK, "highland_color": Palette.HIGHLAND,
	}
	for parameter: String in colors:
		_material.set_shader_parameter(parameter, colors[parameter])
	var sea := ColorRect.new()
	sea.material = _material
	sea.set_anchors_preset(Control.PRESET_FULL_RECT)
	sea_layer.add_child(sea)

	_interface_layer = CanvasLayer.new()
	add_child(_interface_layer)
	_display = MapDisplay.new()
	_display.voyage = voyage
	_display.time_scale = TIME_SCALE
	_interface_layer.add_child(_display)


func show_help() -> void:
	_display.show_help = true


func _physics_process(delta: float) -> void:
	if voyage.bubble != null:
		_read_bubble_controls(delta)
		for index in Bubble.TIME_SCALE:
			if voyage.bubble == null:
				break
			voyage.step_bubble()
			if voyage.bubble == null:
				break
			for wake in _wakes:
				wake.advance(Bubble.STEP)
			if _effects != null:
				_effects.advance(Bubble.STEP)
	else:
		_read_controls(delta)
	_follow_bubble()
	_follow_port()
	_follow_plunder()
	# The world's clock never waits for a bubble: in a shared world, it can't.
	var remaining := delta * TIME_SCALE
	while remaining > 0.0:
		var step := minf(remaining, LONGEST_STEP)
		voyage.advance(step)
		remaining -= step
		_since_track += step
		if _since_track >= TRACK_INTERVAL:
			_since_track = 0.0
			_track.append(voyage.ship.position)
			if _track.size() > TRACK_LENGTH:
				_track.pop_front()


func _read_controls(delta: float) -> void:
	if not voyage.docked.is_empty():
		# Moored: the port screen has the controls. The view still zooms.
		_read_view_controls()
		return
	var helm := Input.get_axis("steer_port", "steer_starboard")
	if helm != 0.0:
		voyage.take_helm()
		voyage.ship.heading = wrapf(voyage.ship.heading + deg_to_rad(helm * TURN_RATE * delta), -PI, PI)
	if Input.is_action_just_pressed("set_course") and get_viewport().gui_get_hovered_control() == null:
		var mouse := get_viewport().get_mouse_position()
		var clicked := _captain_at(mouse)
		var port := _port_at(mouse)
		if clicked != null:
			voyage.chase(clicked)
		elif not port.is_empty():
			voyage.sail_to_port(port)
		else:
			voyage.set_course(_origin() + mouse * ZOOM_LEVELS[zoom_index])
	if Input.is_action_just_pressed("moor"):
		_display.notice(voyage.moor())
	if Input.is_action_just_pressed("more_sail"):
		voyage.ship.sail_set = minf(snappedf(voyage.ship.sail_set + 0.25, 0.25), 1.0)
	if Input.is_action_just_pressed("less_sail"):
		voyage.ship.sail_set = maxf(snappedf(voyage.ship.sail_set - 0.25, 0.25), 0.0)
	_read_view_controls()


## Inside a bubble the player sails the ship by hand: rudder, sail and trim.
func _read_bubble_controls(delta: float) -> void:
	var ship := voyage.bubble.player
	var helm := Input.get_axis("steer_port", "steer_starboard")
	ship.rudder = move_toward(ship.rudder, helm, HELM_RATE * delta)
	if Input.is_action_just_pressed("more_sail"):
		ship.sail_ordered = minf(snappedf(ship.sail_ordered + 0.25, 0.25), 1.0)
	if Input.is_action_just_pressed("less_sail"):
		ship.sail_ordered = maxf(snappedf(ship.sail_ordered - 0.25, 0.25), 0.0)
	var trim := Input.get_axis("sheet_in", "sheet_out")
	if trim != 0.0:
		ship.automatic_trim = false
		ship.sheet = clampf(ship.sheet + trim * SHEET_RATE * delta, 0.0, 1.0)
	ship.backing_headsails = Input.is_action_pressed("back_headsails")
	if Input.is_action_just_pressed("toggle_automatic_trim"):
		ship.automatic_trim = not ship.automatic_trim
	if Input.is_action_just_pressed("board"):
		voyage.board()
	if Input.is_action_just_pressed("fire"):
		_display.notice(voyage.bubble.fire())
	if Input.is_action_just_pressed("change_shot"):
		voyage.bubble.gunnery.cycle_shot(voyage.bubble.player)
	_read_view_controls()


func _read_view_controls() -> void:
	if Input.is_action_just_pressed("zoom_in"):
		zoom_index = mini(zoom_index + 1, ZOOM_LEVELS.size() - 1)
	if Input.is_action_just_pressed("zoom_out"):
		zoom_index = maxi(zoom_index - 1, 0)
	if Input.is_action_just_pressed("toggle_help"):
		_display.show_help = not _display.show_help
	if Input.is_action_just_pressed("toggle_fullscreen"):
		InterfaceDrawing.toggle_fullscreen()


## The ship whose symbol is under a point on the screen, or null.
func _captain_at(screen_point: Vector2) -> Captain:
	for captain in voyage.captains:
		if captain.at_sea() and _to_screen(captain.ship.position).distance_to(screen_point) <= CLICK_REACH:
			return captain
	return null


## Opens a tab of the port screen: a development aid for screenshots.
func open_port_tab(tab: int) -> void:
	_follow_port()
	if _port_screen != null:
		_port_screen.open.call_deferred(tab)


## The port whose marker is under a point on the screen, or empty.
func _port_at(screen_point: Vector2) -> Dictionary:
	for port in voyage.ports:
		if _to_screen(port.position).distance_to(screen_point) <= CLICK_REACH:
			return port
	return {}


## Opens the port screen when the ship moors and closes it when the ship casts off.
func _follow_port() -> void:
	var in_port := not voyage.docked.is_empty()
	if in_port and _port_screen == null:
		moored.emit()
		_port_screen = PortScreen.new()
		_port_screen.voyage = voyage
		_interface_layer.add_child(_port_screen)
	elif not in_port and _port_screen != null:
		_port_screen.queue_free()
		_port_screen = null


## Opens the plunder panel while a taken ship lies alongside.
func _follow_plunder() -> void:
	var prize := voyage.bubble != null and voyage.bubble.prize() != null
	if prize and _plunder_screen == null:
		_plunder_screen = PlunderScreen.new()
		_plunder_screen.voyage = voyage
		_interface_layer.add_child(_plunder_screen)
	elif not prize and _plunder_screen != null:
		_plunder_screen.queue_free()
		_plunder_screen = null


## Zooms into a bubble when one opens, back out when it closes, and keeps a wake behind every
## ship in it.
func _follow_bubble() -> void:
	if voyage.bubble == _bubble:
		return
	for wake in _wakes:
		wake.queue_free()
	_wakes.clear()
	if _effects != null:
		_effects.queue_free()
		_effects = null
	if voyage.bubble != null and _bubble == null:
		_zoom_before_bubble = zoom_index
		zoom_index = BUBBLE_ZOOM
	elif voyage.bubble == null:
		zoom_index = _zoom_before_bubble
	_bubble = voyage.bubble
	_collisions_seen = 0
	if _bubble != null:
		for ship in _bubble.all_ships():
			var wake := WakeView.new()
			wake.ship = ship
			add_child(wake)
			move_child(wake, 0)
			_wakes.append(wake)
		_effects = EffectsView.new()
		_effects.bubble = _bubble
		add_child(_effects)


## Inside a bubble the view works in the bubble's own frame, where positions are precise; on
## the map, in world positions. This is the world position of that frame's zero.
func _frame() -> Vector2:
	return voyage.bubble.origin if voyage.bubble != null else Vector2.ZERO


## The position the view centers on, in the current frame: the player's ship.
func _focus() -> Vector2:
	return voyage.bubble.player.position if voyage.bubble != null else voyage.ship.position


func _process(delta: float) -> void:
	var meters_per_pixel := ZOOM_LEVELS[zoom_index]
	var visible_size := get_viewport_rect().size
	var true_wind := voyage.monsoon.velocity_at(_frame() + _focus())

	# The sea under the ship moves past at the ship's real speed, not the world clock's: at an
	# world clock it would be a blur, and this shows how the ship is actually sailing. Inside a
	# bubble it's the bubble's own clock.
	var motion := voyage.ship.forward() * voyage.ship.speed * delta
	if voyage.bubble != null:
		motion = voyage.bubble.player.velocity * delta * Bubble.TIME_SCALE
		true_wind = voyage.bubble.wind.velocity_at(_focus())
	_water_offset += motion / meters_per_pixel
	_water_offset = Vector2(fposmod(_water_offset.x, 65536.0), fposmod(_water_offset.y, 65536.0))
	_wave_time += delta

	# Split the screen's world origin into whole kilometers and the meters past them, without
	# ever adding the small in-frame origin to the large frame position.
	var whole_kilometers := (_frame() / 1000.0).floor()
	var meters := _frame() - whole_kilometers * 1000.0 + _origin()
	var carried := (meters / 1000.0).floor()
	_material.set_shader_parameter("origin_kilometers", whole_kilometers + carried)
	_material.set_shader_parameter("origin_meters", meters - carried * 1000.0)
	_material.set_shader_parameter("meters_per_pixel", meters_per_pixel)
	_material.set_shader_parameter("visible_size", visible_size)
	_material.set_shader_parameter("wind_direction", true_wind.normalized())
	_material.set_shader_parameter("wind_strength", clampf(true_wind.length() / 10.0, 0.0, 1.5))
	_material.set_shader_parameter("water_offset", _water_offset.floor())
	_material.set_shader_parameter("wave_time", _wave_time)
	_display.meters_per_pixel = meters_per_pixel
	var sighting := voyage.nearest_sighting()
	_display.sighting = sighting if not sighting.is_empty() and sighting.distance < SIGHTING_RANGE else {}
	if voyage.bubble != null and voyage.bubble.collisions.size() > _collisions_seen:
		_collisions_seen = voyage.bubble.collisions.size()
		_display.collision_notice = COLLISION_NOTICE
	_display.collision_notice = maxf(_display.collision_notice - delta, 0.0)

	for wake in _wakes:
		wake.pixels_per_meter = 1.0 / meters_per_pixel
		wake.origin = _origin()
	if _effects != null:
		_effects.pixels_per_meter = 1.0 / meters_per_pixel
		_effects.origin = _origin()
		move_child(_effects, get_child_count() - 1)
	if voyage.bubble != null:
		_show_bubble_ships(meters_per_pixel)
	else:
		_pose_ships(meters_per_pixel)
	queue_redraw()


## The screen's top-left pixel in the current frame: the ship at the center, on whole pixels.
func _origin() -> Vector2:
	var meters_per_pixel := ZOOM_LEVELS[zoom_index]
	var half_screen := get_viewport_rect().size / 2.0
	var center := (_focus() / meters_per_pixel).floor()
	return (center - half_screen) * meters_per_pixel


func _to_screen(world_position: Vector2) -> Vector2:
	return _frame_to_screen(world_position - _frame())


func _frame_to_screen(frame_position: Vector2) -> Vector2:
	return ((frame_position - _origin()) / ZOOM_LEVELS[zoom_index]).floor()


## At true-size zoom, every ship on screen is drawn from a full-physics pose of its map ship.
func _pose_ships(meters_per_pixel: float) -> void:
	var shown: Array[MapShip] = []
	if meters_per_pixel < TRUE_SIZE_BELOW:
		var reach := get_viewport_rect().size.length() * meters_per_pixel
		shown.append(voyage.ship)
		for prize in voyage.prizes:
			if prize.ship.position.distance_to(voyage.ship.position) < reach:
				shown.append(prize.ship)
		for captain in voyage.captains:
			if captain.at_sea() and captain.ship.position.distance_to(voyage.ship.position) < reach:
				shown.append(captain.ship)
	while _ship_views.size() < shown.size():
		var view := ShipView.new()
		add_child(view)
		_ship_views.append(view)
	for index in _ship_views.size():
		var view := _ship_views[index]
		view.visible = index < shown.size()
		if not view.visible:
			continue
		var map_ship := shown[index]
		var pose: Ship = _poses.get(map_ship)
		if pose == null or pose.design != map_ship.design:
			pose = Ship.new(map_ship.design)
			_poses[map_ship] = pose
		pose.position = map_ship.position
		pose.heading = map_ship.heading
		pose.velocity = map_ship.forward() * map_ship.speed
		pose.settle(voyage.monsoon.velocity_at(map_ship.position))
		view.ship = pose
		view.pixels_per_meter = 1.0 / meters_per_pixel
		view.origin = _origin()


## Inside a bubble the ships are the bubble's own, drawn at true size from the full physics.
func _show_bubble_ships(meters_per_pixel: float) -> void:
	var ships := voyage.bubble.all_ships()
	while _ship_views.size() < ships.size():
		var view := ShipView.new()
		add_child(view)
		_ship_views.append(view)
	for index in _ship_views.size():
		var view := _ship_views[index]
		view.visible = index < ships.size()
		if view.visible:
			view.ship = ships[index]
			view.pixels_per_meter = 1.0 / meters_per_pixel
			view.origin = _origin()


func _draw() -> void:
	var meters_per_pixel := ZOOM_LEVELS[zoom_index]
	for index in _track.size():
		if index % 2 == 0:
			draw_rect(Rect2(_to_screen(_track[index]), Vector2.ONE), Palette.FOAM_FADING)
	if meters_per_pixel >= 100.0:
		var nearest := voyage.nearest_port()
		for port in voyage.ports:
			var point := _to_screen(port.position)
			draw_rect(Rect2(point - Vector2(2.0, 2.0), Vector2(5.0, 5.0)), Palette.PANEL)
			draw_rect(Rect2(point - Vector2(1.0, 1.0), Vector2(3.0, 3.0)), Palette.BUOY_LIGHT)
			var color := Palette.TEXT if port == nearest else Palette.TEXT_MUTED
			InterfaceDrawing.outlined_text(self, point + Vector2(5.0, -4.0), port.name, color)
	_draw_course()
	if voyage.bubble != null:
		_draw_bubble_markers()
	if voyage.bubble != null and meters_per_pixel < TRUE_SIZE_BELOW:
		return
	if meters_per_pixel >= TRUE_SIZE_BELOW:
		for captain in voyage.captains:
			if captain.at_sea():
				_draw_ship_symbol(captain.ship, flag_color(captain.role), captain.role)
		for prize in voyage.prizes:
			_draw_ship_symbol(prize.ship, Palette.PLAYER, -1)
		_draw_ship_symbol(voyage.ship, Palette.PLAYER, -1)


## Inside a bubble, every ship off the edge of the screen gets a pointer at the edge, in its
## flag color, so the player always knows where the others are.
func _draw_bubble_markers() -> void:
	var size := get_viewport_rect().size
	var inset := Rect2(Vector2.ONE * 20.0, size - Vector2.ONE * 40.0)
	var center := size / 2.0
	for index in voyage.bubble.ships.size():
		var point := _frame_to_screen(voyage.bubble.ships[index].position)
		if inset.has_point(point):
			continue
		var direction := (point - center).normalized()
		var scale_x := (inset.size.x / 2.0) / maxf(absf(direction.x), 0.0001)
		var scale_y := (inset.size.y / 2.0) / maxf(absf(direction.y), 0.0001)
		var edge := (center + direction * minf(scale_x, scale_y)).floor()
		var across := direction.orthogonal()
		var flag := flag_color(voyage.bubble.captains[index].role)
		var marker := PackedVector2Array([edge + direction * 6.0, edge + across * 5.0, edge - across * 5.0])
		draw_colored_polygon(marker, flag)
		var outline := marker.duplicate()
		outline.append(marker[0])
		draw_polyline(outline, Palette.PANEL)


## The course the crew is sailing to, dotted in the player's color, with a ring at the end.
func _draw_course() -> void:
	if voyage.autopilot == null or voyage.autopilot.route.is_empty():
		return
	var previous := _to_screen(voyage.ship.position)
	for waypoint in voyage.autopilot.route:
		var point := _to_screen(waypoint)
		var steps := ceili(previous.distance_to(point) / 4.0)
		for index in steps:
			draw_rect(Rect2(previous.lerp(point, float(index) / steps).floor(), Vector2.ONE), Palette.PLAYER)
		previous = point
	draw_arc(previous, 4.0, 0.0, TAU, 12, Palette.PLAYER_EDGE)


## A ship as a chart symbol, at a fixed size since it's far too small to see at true size, its
## sail swung out to leeward the way the wind sets it, and its flag at the masthead: navy ships
## fly a long pennant, so the flag's shape tells them apart as well as its color.
static func flag_color(role: Captain.Role) -> Color:
	return [Palette.MERCHANT, Palette.NAVY, Palette.PIRATE][role]


## A ship as a chart symbol. Each kind flies its own flag, in its own color and its own shape,
## so they tell apart without relying on color: merchants a small flag, the navy a long
## pennant, pirates a broad square one; the player (role -1) flies pink.
func _draw_ship_symbol(ship: MapShip, flag: Color, role: int) -> void:
	var center := _to_screen(ship.position)
	var screen := Rect2(Vector2.ZERO, get_viewport_rect().size).grow(12.0)
	if not screen.has_point(center):
		return
	var forward := ship.forward()
	var side := forward.orthogonal()
	var hull := PackedVector2Array()
	for point in [Vector2(7, 0), Vector2(3, 3), Vector2(-5, 3), Vector2(-7, 2), Vector2(-7, -2), Vector2(-5, -3), Vector2(3, -3)]:
		hull.append(center + forward * point.x + side * point.y)
	draw_colored_polygon(hull, Palette.HULL)
	var closed := hull.duplicate()
	closed.append(hull[0])
	draw_polyline(closed, Palette.HULL_SHADOW)
	var wind := voyage.monsoon.velocity_at(ship.position)
	var leeward := signf(wind.dot(side)) if wind.dot(side) != 0.0 else 1.0
	var angle_off_wind := absf(forward.angle_to(-wind))
	var swing := clampf(angle_off_wind - deg_to_rad(20.0), deg_to_rad(10.0), deg_to_rad(85.0))
	var sail_direction := (-forward).rotated(swing * leeward)
	var mast := center + forward * 1.0
	var sail_end := mast + sail_direction * 9.0
	var belly := sail_direction.orthogonal() * leeward * -1.5
	draw_colored_polygon(PackedVector2Array([mast, mast.lerp(sail_end, 0.5) + belly, sail_end]), Palette.SAIL)
	draw_line(mast, sail_end, Palette.SPAR)
	draw_rect(Rect2(mast - Vector2.ONE, Vector2(2.0, 2.0)), flag)
	if role == Captain.Role.NAVY:
		draw_line(mast, mast - forward * 4.0, flag)
	elif role == Captain.Role.PIRATE:
		draw_rect(Rect2(mast - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), flag)
