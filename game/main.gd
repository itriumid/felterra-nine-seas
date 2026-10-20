extends Node
## The game's root: holds the voyage and shows it in the world view. Everything that has to
## outlast a screen lives in the voyage, which is saved whenever the ship moors and when the game
## closes, and picked up again on the next start.

var voyage: Voyage
## Off whenever a development flag is given, so trying things out never touches a real save.
var saving := true

# Development aids. --screenshot=<path> saves a frame after --screenshot-after seconds (default
# 4) and quits; --brig starts in the brig; --help-overlay opens the help; --day=<day of the
# year> sets the date; --zoom=<level> picks a zoom level, 0 (the whole chart) to 10 (the deck);
# --bubble starts in a bubble with a merchant brig half a kilometer away; --port-tab=<1 or 2>
# opens the port screen on the shipyard or the tavern; --plunder starts alongside a merchant that
# has just struck; --battle starts trading broadsides with a navy brig; --pirates starts with a
# pirate sloop closing to board; --prize starts moored in Batavia with a prize brig alongside.
# Any of these starts a
# fresh voyage and saves nothing. --new-voyage abandons the saved voyage and starts again.
var _screenshot_path := ""
var _screenshot_after := 4.0


func _ready() -> void:
	InputActions.register()
	get_tree().auto_accept_quit = false
	var arguments := OS.get_cmdline_user_args()
	saving = arguments.is_empty() or arguments == PackedStringArray(["--new-voyage"])
	if saving and not "--new-voyage" in arguments:
		voyage = SaveGame.load_voyage()
	if voyage == null:
		voyage = Voyage.new()
	var view := WorldView.new()
	view.moored.connect(_save)
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
		elif argument == "--plunder":
			_meet_a_merchant()
			_take_her()
		elif argument == "--prize":
			_meet_a_merchant()
			_take_her()
			voyage.bubble.take_as_prize()
			voyage.step_bubble()
			voyage.bubble = null
			voyage.dock(voyage.port_named("Batavia"))
			voyage.prizes[0].ship.position = voyage.docked.position
			view.open_port_tab.call_deferred(3)
		elif argument == "--pirates":
			_meet_a_merchant()
			_pirates_close_in()
		elif argument == "--battle":
			_meet_a_merchant()
			_fight_the_navy()
		elif argument.begins_with("--port-tab="):
			view.open_port_tab.call_deferred(argument.trim_prefix("--port-tab=").to_int())
	add_child(view)
	if show_help:
		view.show_help()


func _meet_a_merchant() -> void:
	voyage.undock()
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


func _fight_the_navy() -> void:
	var bubble := voyage.bubble
	var navy: Captain = bubble.captains[0]
	navy.role = Captain.Role.NAVY
	navy.ship.guns = 16
	navy.ship.crew = 90
	navy.hostile = true
	voyage.ship.guns = 10
	voyage.ship.crew = 50
	bubble.ships[0].position = bubble.player.position + bubble.player.starboard() * 140.0 + bubble.player.forward() * 20.0
	bubble.ships[0].heading = bubble.player.heading
	bubble.ships[0].velocity = bubble.player.velocity
	bubble.fire()


func _pirates_close_in() -> void:
	var bubble := voyage.bubble
	var pirate: Captain = bubble.captains[0]
	pirate.role = Captain.Role.PIRATE
	pirate.hostile = true
	pirate.ship.crew = 60
	pirate.ship.guns = 8
	voyage.ship.crew = 20
	# To windward of the player, where the wind lets her run down and choose her moment.
	var windward := -bubble.wind.velocity_at(bubble.player.position).normalized()
	bubble.ships[0].position = bubble.player.position + windward * 60.0
	bubble.ships[0].heading = bubble.player.heading
	bubble.ships[0].velocity = bubble.player.velocity


func _take_her() -> void:
	var bubble := voyage.bubble
	voyage.ship.crew = 40
	voyage.captains.back().ship.hold = {"spices": 8, "porcelain": 25}
	# Few enough to strike at once, so there's a prize to show.
	voyage.captains.back().ship.crew = 12
	bubble.ships[0].position = bubble.player.position + bubble.player.forward().orthogonal() * 9.0
	bubble.ships[0].heading = bubble.player.heading
	bubble.ships[0].velocity = bubble.player.velocity
	voyage.board()


func _save() -> void:
	if saving:
		SaveGame.save(voyage)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
		get_tree().quit()


func _process(delta: float) -> void:
	if _screenshot_path.is_empty():
		return
	_screenshot_after -= delta
	if _screenshot_after <= 0.0:
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		get_tree().quit()
