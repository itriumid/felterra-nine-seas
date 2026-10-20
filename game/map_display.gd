class_name MapDisplay
extends Control
## What a navigator would want: the date and season, the wind, how the ship is sailing, how far
## it is to the nearest port, and the scale of the view.

const HELP_LINES: Array[String] = [
	"Click the sea: sail there. Click a port: sail there and moor",
	"Click a ship: give chase, and fight when you meet",
	"A and D, or the arrow keys: take the helm and steer",
	"W and S, or up and down: set or take in sail, to go faster or slower",
	"Furl all sail by a port to come in and moor",
	"Minus and equals, or the mouse wheel: zoom",
	"F11: full screen",
	"H: close this help",
]

const BUBBLE_HELP_LINES: Array[String] = [
	"A and D, or the arrow keys: rudder",
	"Space: fire the broadside facing the nearest ship",
	"C: change shot: round for hulls, chain for rigging, grape for crews",
	"G: throw the grapples and board, alongside and moving together",
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
var _notice := ""
var _notice_shown_at := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows a short message, such as why the guns didn't fire, for a few seconds.
func notice(message: String) -> void:
	_notice = message
	_notice_shown_at = Time.get_ticks_msec()


func _notice_line() -> String:
	if _notice.is_empty() or Time.get_ticks_msec() - _notice_shown_at > 3000:
		return ""
	return _notice


## The latest news from the voyage, while it's fresh: about a game day.
func _news_line() -> String:
	if voyage.news.is_empty() or voyage.news_age > Calendar.SECONDS_PER_DAY:
		return ""
	return voyage.news


func _reputation_line() -> String:
	return "Renown %d, honor %d: %s" % [roundi(voyage.renown), roundi(voyage.honor), voyage.reputation_title()]


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
	if not voyage.prizes.is_empty():
		lines.append("Prizes in company: %d" % voyage.prizes.size())
	if not voyage.docked.is_empty():
		lines.append("Moored in %s" % voyage.docked.name)
	elif voyage.autopilot != null:
		lines.append("Crew sailing your course")
	if ship.aground:
		lines.append("Aground! Steer away from the land")
	var moored := not voyage.docked.is_empty()
	lines.append(_reputation_line())
	if voyage.bounty > 0.0:
		lines.append("Bounties owed: %s, paid at the next port" % InterfaceDrawing.reals_text(voyage.bounty))
	if voyage.hunted():
		lines.append("The navy is hunting you")
	if not _news_line().is_empty():
		lines.append(_news_line())
	if not sighting.is_empty():
		var other: Captain = sighting.captain
		lines.append("Sail sighted: %s %s, %s" % [
			other.role_name(), other.ship.design.display_name.to_lower(),
			InterfaceDrawing.distance_text(sighting.distance)])
	# Moored, the port screen shows where and when; this panel would only sit behind it.
	if not moored:
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
		"Hull %d%%, rigging %d%%, crew %d" % [
			roundi(ship.hull * 100.0), roundi(ship.rigging * 100.0), voyage.ship.crew],
		_guns_line(bubble),
	]
	if ship.backing_headsails:
		lines.append("Headsails backed")
	elif ship.aback:
		lines.append("Taken aback!")
	elif ship.luffing > 0.6 and ship.sail_set > 0.05:
		lines.append("Sails luffing")
	if collision_notice > 0.0:
		lines.append("Collision!")
	lines.append(_boarding_line(bubble))
	for extra in [_notice_line(), _news_line()]:
		if not extra.is_empty():
			lines.append(extra)
	InterfaceDrawing.text_panel(self, Vector2(InterfaceDrawing.MARGIN, InterfaceDrawing.MARGIN), lines)
	InterfaceDrawing.wind_rose(self, size, wind, ship.forward())

	var others: Array[String] = []
	for index in bubble.ships.size():
		var other := bubble.ships[index]
		var offset := other.position - ship.position
		var captain := bubble.captains[index]
		var state := "struck" if captain.struck else ("hostile" if captain.hostile else "")
		others.append("%s %s, %s, bearing %s, hull %d%%%s" % [
			captain.role_name(), other.design.display_name.to_lower(),
			InterfaceDrawing.distance_text(offset.length()),
			InterfaceDrawing.bearing_text(Wind.direction_to_bearing(offset)),
			roundi(other.hull * 100.0), (", " + state) if not state.is_empty() else ""])
	if others.is_empty():
		others.append("No other ships")
	var corner := Vector2(InterfaceDrawing.MARGIN, size.y - InterfaceDrawing.MARGIN)
	InterfaceDrawing.text_panel(self, corner, others, false, true)
	var bottom_right := size - Vector2.ONE * InterfaceDrawing.MARGIN
	InterfaceDrawing.text_panel(self, bottom_right, ["Time ×%d   H for help" % Bubble.TIME_SCALE], true, true)
	if show_help:
		InterfaceDrawing.centered_panel(self, size, BUBBLE_HELP_LINES)


func _boarding_line(bubble: Bubble) -> String:
	match bubble.boarding:
		Bubble.Boarding.FIGHTING:
			var fighters := bubble.fighters()
			if bubble.player_boarding:
				return "Boarding! %d of yours against %d of theirs" % [fighters.x, fighters.y]
			return "Pirates boarding! %d of them against %d of yours" % [fighters.x, fighters.y]
		Bubble.Boarding.TAKEN:
			return "She has struck her colors"
		Bubble.Boarding.PLUNDERED:
			return "Your crew struck. The pirates have stripped your hold"
		Bubble.Boarding.BEATEN_OFF:
			return "The pirate boarders are beaten off!"
		Bubble.Boarding.REPELLED:
			return "Thrown back! The grapples are cut"
	if bubble.pirates_closing():
		return "Pirates closing to board you! Grapeshot, or run"
	var hint := bubble.boarding_hint()
	if hint.is_empty():
		return "Alongside! Press G to board"
	return hint


func _guns_line(bubble: Bubble) -> String:
	var per_side := Gunnery.guns_per_side(voyage.ship)
	if per_side == 0:
		return "No guns"
	var shot: String = Gunnery.SHOT_NAMES[bubble.gunnery.shot_of(bubble.player)]
	var sides: Array[String] = []
	for side in [-1, 1]:
		var name := "starboard" if side > 0 else "port"
		var left := bubble.gunnery.reload_left(bubble.player, side)
		if left <= 0.0:
			sides.append("%s ready" % name)
		else:
			sides.append("%s loading" % name)
	return "%d guns a side, %s: %s" % [per_side, shot, ", ".join(sides)]
