extends Node
## The game's root: holds the voyage and shows it in the world view. Everything that has to
## outlast a screen lives in the voyage.

var voyage := Voyage.new()

# Development aids. --screenshot=<path> saves a frame after --screenshot-after seconds (default
# 4) and quits; --brig starts in the brig; --help-overlay opens the help; --day=<day of the
# year> sets the date; --zoom=<level> picks a zoom level, 0 (the whole chart) to 10 (the deck);
# --bubble starts in a bubble with a merchant brig half a kilometer away.
var _screenshot_path := ""
var _screenshot_after := 4.0


func _ready() -> void:
	InputActions.register()
	var view := WorldView.new()
	view.voyage = voyage
	var show_help := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot="):
			_screenshot_path = argument.trim_prefix("--screenshot=")
		elif argument.begins_with("--screenshot-after="):
			_screenshot_after = argument.trim_prefix("--screenshot-after=").to_float()
		elif argument == "--brig":
			voyage.switch_ship()
		elif argument == "--help-overlay":
			show_help = true
		elif argument.begins_with("--day="):
			voyage.calendar.seconds = argument.trim_prefix("--day=").to_float() * Calendar.SECONDS_PER_DAY
		elif argument.begins_with("--zoom="):
			view.zoom_index = argument.trim_prefix("--zoom=").to_int()
		elif argument == "--bubble":
			_meet_a_merchant()
	add_child(view)
	if show_help:
		view.show_help()


func _meet_a_merchant() -> void:
	voyage.ship.position = Chart.position_of(-5.6, 107.2)
	voyage.ship.speed = 3.0
	var merchant := Captain.new(Captain.Role.MERCHANT, ShipDesign.brig())
	merchant.ship.position = voyage.ship.position + Vector2(150.0, -450.0)
	merchant.ship.heading = voyage.ship.heading
	merchant.ship.speed = 3.0
	merchant.destination = voyage.port_named("Semarang")
	merchant.route = [voyage.port_named("Semarang").position]
	voyage.captains.append(merchant)
	voyage.chase(merchant)
	voyage.advance(1.0)


func _process(delta: float) -> void:
	if _screenshot_path.is_empty():
		return
	_screenshot_after -= delta
	if _screenshot_after <= 0.0:
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		get_tree().quit()
