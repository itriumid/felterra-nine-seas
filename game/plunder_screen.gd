class_name PlunderScreen
extends PanelContainer
## A taken ship's hold, while she lies alongside: take what you want of it, then cast off.

const WIDTH := 300.0
## Pixels kept clear at the bottom, for the panel listing the ships in the bubble.
const BOTTOM := 26.0

var voyage: Voyage

var _rows: VBoxContainer
var _status: Label
var _notice: Label
var _shown := {}
var _prize_note: Label


func _ready() -> void:
	theme = InterfaceTheme.get_theme()
	custom_minimum_size = Vector2(WIDTH, 0.0)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)
	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "She has struck. Her hold:"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var prize := Button.new()
	prize.text = "Take her as a prize"
	prize.pressed.connect(func() -> void: _notice.text = voyage.bubble.take_as_prize())
	heading.add_child(prize)
	var leave := Button.new()
	leave.text = "Cast off"
	leave.theme_type_variation = "PrimaryButton"
	leave.pressed.connect(func() -> void: voyage.cast_off())
	heading.add_child(leave)
	layout.add_child(heading)
	_prize_note = Label.new()
	_prize_note.theme_type_variation = "MutedLabel"
	layout.add_child(_prize_note)
	_rows = VBoxContainer.new()
	layout.add_child(_rows)
	_status = Label.new()
	_status.theme_type_variation = "MutedLabel"
	layout.add_child(_status)
	_notice = Label.new()
	layout.add_child(_notice)
	leave.grab_focus.call_deferred()


func _process(_delta: float) -> void:
	var prize: MapShip = voyage.bubble.prize() if voyage.bubble != null else null
	if prize == null:
		return
	if prize.hold != _shown:
		_shown = prize.hold.duplicate()
		_rebuild(prize)
	_status.text = "Your hold: %d of %d tons" % [voyage.ship.cargo_tons(), int(voyage.ship.design.cargo_capacity)]
	var crew := voyage.bubble.prize_crew_size()
	_prize_note.text = ("A prize crew would take %d of your %d sailors; her own are set adrift in their boats." % [crew, voyage.ship.crew]) \
		if crew >= 4 else "You can't spare a prize crew for her."
	# Low on the screen: the two ships lashed together in the middle are the point.
	var screen := get_viewport_rect().size
	position = Vector2(floorf((screen.x - size.x) / 2.0), screen.y - size.y - BOTTOM)


func _rebuild(prize: MapShip) -> void:
	for child in _rows.get_children():
		child.queue_free()
	if prize.hold.is_empty():
		var empty := Label.new()
		empty.text = "Nothing left aboard."
		empty.theme_type_variation = "MutedLabel"
		_rows.add_child(empty)
		return
	for id: String in prize.hold:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s, %d tons" % [Goods.display_name(id), prize.hold[id]]
		label.custom_minimum_size.x = 160.0
		row.add_child(label)
		for amount in [1, 10]:
			var take := Button.new()
			take.text = "Take %d" % amount
			take.pressed.connect(func() -> void: _notice.text = voyage.plunder(id, amount))
			row.add_child(take)
		var all := Button.new()
		all.text = "Take all"
		all.pressed.connect(func() -> void:
			_notice.text = voyage.plunder(id, mini(prize.hold.get(id, 0), voyage.ship.free_tons())))
		row.add_child(all)
		_rows.add_child(row)
