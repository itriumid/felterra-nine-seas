class_name MapDisplay
extends Control
## What a navigator would want: the date and season, the wind, how the ship is sailing, how far
## it is to the nearest port, and the scale of the view.

const HELP_LINES: Array[String] = [
	"Click the sea or a port: sail there",
	"Click a ship: give chase, and fight when you meet",
	"A and D, or the arrow keys: take the helm and steer",
	"W and S, or up and down: set or take in sail, to go faster or slower",
	"Minus and equals, or the mouse wheel: zoom",
	"Tab: switch between sloop and brig",
	"F11: full screen",
	"H: close this help",
]

const BUBBLE_HELP_LINES: Array[String] = [
	"A and D, or the arrow keys: rudder",
	"W and S: set or take in sail",
	"Q and E: sheet in or ease the sails",
	"T: automatic or manual trim",
	"Hold B: back the headsails, to get out of irons",
	"Mouse wheel, or minus and equals: zoom",
	"Sail more than 6 kilometers clear to leave",
	"H: close this help",
]

var voyage: Voyage
## Game seconds per real second.
var time_scale := 3600.0
var meters_per_pixel := 1000.0
var show_help := false
## The nearest ship in sight, as {captain, distance}, or empty.
var sighting := {}
## Seconds left to report a collision inside a bubble.
var collision_notice := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	size = get_viewport_rect().size
	queue_redraw()


func _draw() -> void:
	if voyage.bubble != null:
		_draw_bubble()
		return
	var ship := voyage.ship
	var wind := voyage.monsoon.velocity_at(ship.position)
	var latitude := Chart.latitude_at(ship.position)
	var angle := rad_to_deg(absf(ship.forward().angle_to(-wind)))
	var nearest := voyage.nearest_port()
	var lines: Array[String] = [
		voyage.calendar.date_text(),
		voyage.monsoon.season_name(latitude),
		"%s, %.1f knots, heading %s" % [
			ship.design.display_name, ship.speed * InterfaceDrawing.KNOTS_PER_METER_PER_SECOND,
			InterfaceDrawing.bearing_text(Wind.direction_to_bearing(ship.forward()))],
		"%s, sails %d%%" % [InterfaceDrawing.point_of_sail(angle, ship.speed), roundi(ship.sail_set * 100.0)],
		"%s, %s" % [nearest.name, InterfaceDrawing.distance_text(ship.position.distance_to(nearest.position))],
	]
	if voyage.autopilot != null:
		lines.append("Crew sailing your course")
	if ship.aground:
		lines.append("Aground! Steer away from the land")
	if not sighting.is_empty():
		var other: Captain = sighting.captain
		lines.append("Sail sighted: %s %s, %s" % [
			other.role_name(), other.ship.design.display_name.to_lower(),
			InterfaceDrawing.distance_text(sighting.distance)])
	InterfaceDrawing.text_panel(self, Vector2(InterfaceDrawing.MARGIN, InterfaceDrawing.MARGIN), lines)
	InterfaceDrawing.wind_rose(self, size, wind, ship.forward())
	var corner := size - Vector2.ONE * InterfaceDrawing.MARGIN
	var scale_text := "1 pixel: %s" % InterfaceDrawing.distance_text(meters_per_pixel)
	if meters_per_pixel < 1.0:
		scale_text = "%d pixels: 1 meter" % roundi(1.0 / meters_per_pixel)
	InterfaceDrawing.text_panel(self, corner, ["%s   %s   H for help" % [scale_text, _time_text()]], true, true)
	if show_help:
		InterfaceDrawing.centered_panel(self, size, HELP_LINES)


func _time_text() -> String:
	if time_scale >= 3600.0:
		var hours := roundi(time_scale / 3600.0)
		return "%d hour%s a second" % [hours, "" if hours == 1 else "s"]
	return "%d minutes a second" % roundi(time_scale / 60.0)


## Inside a bubble: the ship the way a captain reads it up close, and every other ship in it.
func _draw_bubble() -> void:
	var bubble := voyage.bubble
	var ship := bubble.player
	var wind := bubble.wind.velocity_at(ship.position)
	var angle := rad_to_deg(ship.wind_angle(wind))
	var side := "starboard" if angle > 0.0 else "port"
	var seconds := int(bubble.time)
	var lines: Array[String] = [
		"In action, %d:%02d" % [seconds / 60, seconds % 60],
		"%s, %.1f knots, heading %s" % [
			ship.design.display_name, ship.forward_speed() * InterfaceDrawing.KNOTS_PER_METER_PER_SECOND,
			InterfaceDrawing.bearing_text(Wind.direction_to_bearing(ship.forward()))],
		"%s, wind %.0f° on the %s side" % [
			InterfaceDrawing.point_of_sail(absf(angle), ship.forward_speed()), absf(angle), side],
		"Sails %d%%, %s trim, heel %.0f°" % [
			roundi(ship.sail_set * 100.0), "automatic" if ship.automatic_trim else "manual",
			absf(rad_to_deg(ship.heel))],
	]
	if ship.backing_headsails:
		lines.append("Headsails backed")
	elif ship.aback:
		lines.append("Taken aback!")
	elif ship.luffing > 0.6 and ship.sail_set > 0.05:
		lines.append("Sails luffing")
	if collision_notice > 0.0:
		lines.append("Collision!")
	InterfaceDrawing.text_panel(self, Vector2(InterfaceDrawing.MARGIN, InterfaceDrawing.MARGIN), lines)
	InterfaceDrawing.wind_rose(self, size, wind, ship.forward())

	var others: Array[String] = []
	for index in bubble.ships.size():
		var other := bubble.ships[index]
		var offset := other.position - ship.position
		others.append("%s %s, %s, bearing %s" % [
			bubble.captains[index].role_name(), other.design.display_name.to_lower(),
			InterfaceDrawing.distance_text(offset.length()),
			InterfaceDrawing.bearing_text(Wind.direction_to_bearing(offset))])
	var corner := Vector2(InterfaceDrawing.MARGIN, size.y - InterfaceDrawing.MARGIN)
	InterfaceDrawing.text_panel(self, corner, others, false, true)
	var bottom_right := size - Vector2.ONE * InterfaceDrawing.MARGIN
	InterfaceDrawing.text_panel(self, bottom_right, ["Time ×%d   H for help" % Bubble.TIME_SCALE], true, true)
	if show_help:
		InterfaceDrawing.centered_panel(self, size, BUBBLE_HELP_LINES)
