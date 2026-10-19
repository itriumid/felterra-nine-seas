class_name PortScreen
extends PanelContainer
## The port the player is moored in: its market, shipyard and tavern, and the way back to sea.
## Every button sends a command to the voyage and shows the reason when it's refused. The world
## keeps its clock in port, so prices and the tavern change while the player looks.

enum Tab { MARKET, SHIPYARD, TAVERN }

const WIDTH := 480.0
const TOP := 78.0

var voyage: Voyage

var _tab := Tab.MARKET
var _title: Label
var _tabs := {}
var _content: VBoxContainer
var _status: Label
var _notice: Label
## Labels that show live values, refreshed every frame: each is [label, callable giving text].
var _live: Array[Array] = []


func _ready() -> void:
	theme = InterfaceTheme.get_theme()
	custom_minimum_size = Vector2(WIDTH, 0.0)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)

	var heading := HBoxContainer.new()
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)
	var leave := Button.new()
	leave.text = "Set sail"
	leave.theme_type_variation = "PrimaryButton"
	leave.pressed.connect(func() -> void: voyage.undock())
	heading.add_child(leave)
	layout.add_child(heading)

	var tab_row := HBoxContainer.new()
	for tab: Tab in [Tab.MARKET, Tab.SHIPYARD, Tab.TAVERN]:
		var button := Button.new()
		button.text = ["Market", "Shipyard", "Tavern"][tab]
		button.pressed.connect(open.bind(tab))
		tab_row.add_child(button)
		_tabs[tab] = button
	layout.add_child(tab_row)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 2)
	layout.add_child(_content)

	_status = Label.new()
	_status.theme_type_variation = "MutedLabel"
	layout.add_child(_status)
	_notice = Label.new()
	layout.add_child(_notice)
	open(Tab.MARKET)
	leave.grab_focus.call_deferred()


func _process(_delta: float) -> void:
	if voyage.docked.is_empty():
		return
	_title.text = "%s, %s" % [voyage.docked.name, voyage.calendar.date_text()]
	_status.text = "Purse %s   Hold %d of %d tons   Crew %d" % [
		InterfaceDrawing.reals_text(voyage.purse), voyage.ship.cargo_tons(),
		int(voyage.ship.design.cargo_capacity), voyage.ship.crew]
	for entry in _live:
		(entry[0] as Label).text = (entry[1] as Callable).call()
	# Centered across the screen, top edge pinned below the wind rose so switching tabs doesn't
	# make the panel jump.
	position = Vector2(floorf((get_viewport_rect().size.x - size.x) / 2.0), TOP)


func open(tab: Tab) -> void:
	_tab = tab
	for each: Tab in _tabs:
		(_tabs[each] as Button).theme_type_variation = "OpenTab" if each == tab else ""
	for child in _content.get_children():
		child.queue_free()
	_live.clear()
	_notice.text = ""
	match tab:
		Tab.MARKET:
			_build_market()
		Tab.SHIPYARD:
			_build_shipyard()
		Tab.TAVERN:
			_build_tavern()


## Runs a command and shows why, if it was refused.
func _command(action: Callable) -> void:
	var refusal: String = action.call()
	_notice.text = refusal


func _live_label(text: Callable, muted := false, width := 0.0) -> Label:
	var label := Label.new()
	if muted:
		label.theme_type_variation = "MutedLabel"
	if width > 0.0:
		label.custom_minimum_size.x = width
	_live.append([label, text])
	label.text = text.call()
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(_command.bind(action))
	return button


func _build_market() -> void:
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 1)
	for heading in ["Good", "Buy at", "Sell at", "In port", "Aboard", "", "", "", ""]:
		var label := Label.new()
		label.text = heading
		label.theme_type_variation = "MutedLabel"
		grid.add_child(label)
	for id in Goods.ids():
		var name_label := Label.new()
		name_label.text = Goods.display_name(id)
		name_label.custom_minimum_size.x = 92.0
		grid.add_child(name_label)
		grid.add_child(_live_label(func() -> String: return "%d" % roundi(voyage.market().buying_price(id)), false, 34.0))
		grid.add_child(_live_label(func() -> String: return "%d" % roundi(voyage.market().selling_price(id)), false, 34.0))
		grid.add_child(_live_label(func() -> String: return "%d" % floori(voyage.market().stock[id]), true, 30.0))
		grid.add_child(_live_label(func() -> String: return "%d" % voyage.ship.hold.get(id, 0), false, 30.0))
		grid.add_child(_button("Buy 1", func() -> String: return voyage.buy(id, 1)))
		grid.add_child(_button("Buy 10", func() -> String: return voyage.buy(id, 10)))
		grid.add_child(_button("Sell 1", func() -> String: return voyage.sell(id, 1)))
		grid.add_child(_button("Sell all", func() -> String: return voyage.sell(id, voyage.ship.hold.get(id, 0))))
	_content.add_child(grid)
	var note := Label.new()
	note.text = "Prices are reals a ton. Every ton you buy raises the price; every ton you sell lowers it."
	note.theme_type_variation = "MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.custom_minimum_size.x = WIDTH - 16.0
	_content.add_child(note)


func _build_shipyard() -> void:
	var hull := HBoxContainer.new()
	hull.add_child(_live_label(func() -> String:
		return "Hull %d%%, rigging %d%%. Repairs: %s" % [
			roundi(voyage.ship.hull * 100.0), roundi(voyage.ship.rigging * 100.0), InterfaceDrawing.reals_text(voyage.repair_cost())],
		false, 300.0))
	hull.add_child(_button("Repair", voyage.repair))
	_content.add_child(hull)

	var bottom := HBoxContainer.new()
	bottom.add_child(_live_label(func() -> String:
		var state := "clean" if voyage.ship.fouling < 0.05 else "fouled, %d%% more drag" % roundi(voyage.ship.fouling * 50.0)
		return "Bottom %s. Haul out and scrape: %s" % [state, InterfaceDrawing.reals_text(voyage.scraping_cost())],
		false, 300.0))
	bottom.add_child(_button("Scrape", voyage.scrape))
	_content.add_child(bottom)

	var guns := HBoxContainer.new()
	guns.add_child(_live_label(func() -> String:
		return "Guns: %d of %d ports. %s each, half back for one taken off" % [
			voyage.ship.guns, voyage.ship.design.gun_ports, InterfaceDrawing.reals_text(ShipDesign.GUN_PRICE)],
		false, 300.0))
	guns.add_child(_button("Buy 2", voyage.buy_guns.bind(2)))
	guns.add_child(_button("Sell 2", voyage.sell_guns.bind(2)))
	_content.add_child(guns)

	var for_sale := Label.new()
	for_sale.text = "Ships for sale, with yours taken in trade:"
	for_sale.theme_type_variation = "MutedLabel"
	_content.add_child(for_sale)
	for design in voyage.designs:
		var row := HBoxContainer.new()
		row.add_child(_live_label(func() -> String:
			var details := "%s: %d tons, %d to %d crew." % [
				design.display_name, int(design.cargo_capacity), design.crew_minimum, design.crew_maximum]
			if design.id == voyage.ship.design.id:
				return details + " Your ship."
			return details + " " + InterfaceDrawing.reals_text(voyage.cost_of_ship(design))
			, false, 300.0))
		if design.id != voyage.ship.design.id:
			row.add_child(_button("Buy her", voyage.buy_ship.bind(design)))
		_content.add_child(row)


func _build_tavern() -> void:
	_content.add_child(_live_label(func() -> String:
		var ship := voyage.ship
		return "Your crew: %d sailors. A %s needs %d to carry all sail and berths %d." % [
			ship.crew, ship.design.display_name.to_lower(), ship.design.crew_minimum, ship.design.crew_maximum]))
	_content.add_child(_live_label(func() -> String:
		return "Wages: %s a day. Signing on: %s a sailor." % [
			InterfaceDrawing.reals_text(voyage.ship.crew * Voyage.WAGE), InterfaceDrawing.reals_text(Voyage.SIGNING_BOUNTY)],
		true))
	_content.add_child(_live_label(func() -> String:
		return "Sailors here looking for a berth: %d" % voyage.sailors_in_tavern()))
	var row := HBoxContainer.new()
	for count in [1, 5, 10]:
		row.add_child(_button("Hire %d" % count, voyage.hire.bind(count)))
	for count in [1, 5]:
		row.add_child(_button("Pay off %d" % count, voyage.dismiss.bind(count)))
	_content.add_child(row)
