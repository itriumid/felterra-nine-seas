class_name InterfaceDrawing
extends RefCounted
## The pieces every display draws with: graphite panels of pixel text, arrows and the wind rose.
## Rhodonite on graphite, so every line clears 4.5:1.

const KNOTS_PER_METER_PER_SECOND := 1.943844
const MARGIN := 6.0
const PADDING := 4.0


## Lines of text on a graphite panel. The corner is the panel's top-left, or another corner
## when it hangs from the right or sits on the bottom. Returns the panel's rectangle.
static func text_panel(canvas: CanvasItem, corner: Vector2, lines: Array[String], from_right := false, from_bottom := false) -> Rect2:
	var width := 0.0
	for line in lines:
		width = maxf(width, PixelFont.width(line))
	var panel_size := Vector2(
		width + PADDING * 2.0,
		lines.size() * PixelFont.LINE_HEIGHT - (PixelFont.LINE_HEIGHT - PixelFont.HEIGHT) + PADDING * 2.0 - 2.0)
	var origin := corner
	if from_right:
		origin.x -= panel_size.x
	if from_bottom:
		origin.y -= panel_size.y
	origin = origin.floor()
	canvas.draw_rect(Rect2(origin, panel_size), Palette.PANEL)
	for index in lines.size():
		var color := Palette.TEXT if index == 0 else Palette.TEXT_MUTED
		var top_left := origin + Vector2(PADDING, PADDING + PixelFont.LINE_HEIGHT * index)
		PixelFont.draw(canvas, top_left, lines[index], color)
	return Rect2(origin, panel_size)


## A panel of lines centered on the screen, for help.
static func centered_panel(canvas: CanvasItem, screen_size: Vector2, lines: Array[String]) -> void:
	var width := 0.0
	for line in lines:
		width = maxf(width, PixelFont.width(line))
	var height := lines.size() * PixelFont.LINE_HEIGHT
	text_panel(canvas, ((screen_size - Vector2(width, height)) / 2.0).floor(), lines)


## Sailors' names for the angle between the bow and the wind, in degrees.
static func point_of_sail(angle_off_wind: float, speed: float) -> String:
	if angle_off_wind < 35.0:
		# Stopped this close to the wind is in irons; still moving is pinching, about to be.
		return "In irons" if speed < 0.5 else "Pinching"
	if angle_off_wind < 60.0:
		return "Close-hauled"
	if angle_off_wind < 80.0:
		return "Close reach"
	if angle_off_wind < 100.0:
		return "Beam reach"
	if angle_off_wind < 160.0:
		return "Broad reach"
	return "Running"


## A distance the way the display shows it: meters up close, kilometers further out.
static func distance_text(meters: float) -> String:
	if meters < 2000.0:
		return "%d meters" % roundi(meters)
	return "%d kilometers" % roundi(meters / 1000.0)


## A compass bearing the way navigators write it: three digits, 000 to 359.
static func bearing_text(bearing: float) -> String:
	return "%03d°" % posmod(roundi(bearing), 360)


static func arrow(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	canvas.draw_line(from, to, color)
	var direction := (to - from).normalized()
	var across := direction.orthogonal()
	canvas.draw_colored_polygon(PackedVector2Array([
		to + direction * 3.0, to - direction * 2.0 + across * 3.0, to - direction * 2.0 - across * 3.0,
	]), color)


## A compass in the top-right corner: the ship's heading in the player's color, and the true
## wind as an arrow from the side it blows from, with its speed and bearing underneath.
static func wind_rose(canvas: CanvasItem, screen_size: Vector2, true_wind: Vector2, heading: Vector2) -> void:
	var radius := 22.0
	var center := Vector2(screen_size.x - MARGIN - radius - 4.0, MARGIN + radius + 4.0)
	canvas.draw_rect(Rect2(center - Vector2.ONE * (radius + 4.0), Vector2.ONE * (radius + 4.0) * 2.0), Palette.PANEL)
	canvas.draw_arc(center, radius, 0.0, TAU, 32, Palette.TEXT_MUTED)
	PixelFont.draw(canvas, center + Vector2(-2.0, -radius + 3.0), "N", Palette.TEXT_MUTED)
	canvas.draw_line(center, center + heading * radius * 0.6, Palette.PLAYER)
	var blowing := true_wind.normalized()
	arrow(canvas, center - blowing * radius, center + blowing * radius * 0.3, Palette.TEXT)
	var label := "Wind %.0f knots from %s" % [
		true_wind.length() * KNOTS_PER_METER_PER_SECOND, bearing_text(Wind.direction_to_bearing(-blowing))]
	text_panel(canvas, Vector2(screen_size.x - MARGIN, center.y + radius + 6.0), [label], true)


## Text with a one-pixel graphite outline, readable over any land or sea.
static func outlined_text(canvas: CanvasItem, top_left: Vector2, text: String, color: Color) -> void:
	for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		PixelFont.draw(canvas, top_left + offset, text, Palette.PANEL)
	PixelFont.draw(canvas, top_left, text, color)


static func toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
