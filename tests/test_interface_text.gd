extends TestCase
## How the display writes bearings, distances and money. The font's own tests live with the
## font, in itriumid/pixel-font.


func test_bearings_read_000_to_359() -> void:
	check(InterfaceDrawing.bearing_text(359.6) == "000°", "359.6 read %s" % InterfaceDrawing.bearing_text(359.6))
	check(InterfaceDrawing.bearing_text(45.0) == "045°", "45 read %s" % InterfaceDrawing.bearing_text(45.0))


func test_distances_and_money_read_naturally() -> void:
	check(InterfaceDrawing.distance_text(1000.0) == "1 kilometer", "1000 meters read %s" % InterfaceDrawing.distance_text(1000.0))
	check(InterfaceDrawing.distance_text(450.0) == "450 meters", "450 meters read %s" % InterfaceDrawing.distance_text(450.0))
	check(InterfaceDrawing.reals_text(1500.0) == "1,500 reals", "1500 read %s" % InterfaceDrawing.reals_text(1500.0))
	check(InterfaceDrawing.reals_text(1234567.0) == "1,234,567 reals", "a million read %s" % InterfaceDrawing.reals_text(1234567.0))


func test_the_godot_font_has_every_glyph() -> void:
	var font := PixelFont.font()
	for character: String in PixelFont.GLYPHS:
		check(font.has_char(character.unicode_at(0)), "the Godot font lacks %s" % character)
	var width := font.get_string_size("Hold", HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.HEIGHT).x
	check(is_equal_approx(width, PixelFont.width("Hold") + PixelFont.LETTER_SPACING), "Hold measured %.0f" % width)
