extends TestCase
## Glyphs are typed by hand, so a dropped dot or row would silently misdraw a letter.


func test_every_glyph_is_a_clean_rectangle() -> void:
	for character: String in PixelFont.GLYPHS:
		var rows := PixelFont.glyph_rows(character)
		check(rows.size() == PixelFont.ASCENT or rows.size() == PixelFont.HEIGHT,
			"%s has %d rows" % [character, rows.size()])
		for row in rows:
			check(row.length() == rows[0].length(), "%s has rows of different widths" % character)
			check(row.replace("#", "").replace(".", "").is_empty(), "%s has a stray character" % character)


func test_the_display_never_falls_back_to_a_question_mark() -> void:
	# Everything the heads-up display can print, including the symbols.
	var used := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:!?'-+/()%°×"
	for character in used:
		check(PixelFont.GLYPHS.has(character), "no glyph for %s" % character)


func test_width_adds_letter_spacing_between_glyphs() -> void:
	check(PixelFont.width("I") == 3, "I was %d wide" % PixelFont.width("I"))
	check(PixelFont.width("II") == 7, "II was %d wide" % PixelFont.width("II"))
	check(PixelFont.width("") == 0, "empty text had width")


func test_bearings_read_000_to_359() -> void:
	check(InterfaceDrawing.bearing_text(359.6) == "000°", "359.6 read %s" % InterfaceDrawing.bearing_text(359.6))
	check(InterfaceDrawing.bearing_text(45.0) == "045°", "45 read %s" % InterfaceDrawing.bearing_text(45.0))
