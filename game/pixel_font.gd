class_name PixelFont
extends RefCounted
## Our own pixel font, drawn glyph by glyph so every letter lands on whole pixels at any scale.
## Capitals and digits are 7 pixels tall, lowercase has a 5 pixel x-height, and descenders drop
## 2 more. Glyphs are proportional: each is as wide as its longest row, plus a pixel of spacing.
##
## Each glyph is its rows from the top, separated by spaces: # is ink, . is paper.

const ASCENT := 7
const HEIGHT := 9
const LINE_HEIGHT := 11
const SPACE_WIDTH := 3
const LETTER_SPACING := 1

const GLYPHS := {
	"A": ".###. #...# #...# ##### #...# #...# #...#",
	"B": "####. #...# #...# ####. #...# #...# ####.",
	"C": ".###. #...# #.... #.... #.... #...# .###.",
	"D": "####. #...# #...# #...# #...# #...# ####.",
	"E": "##### #.... #.... ####. #.... #.... #####",
	"F": "##### #.... #.... ####. #.... #.... #....",
	"G": ".###. #...# #.... #.### #...# #...# .####",
	"H": "#...# #...# #...# ##### #...# #...# #...#",
	"I": "### .#. .#. .#. .#. .#. ###",
	"J": "..### ...#. ...#. ...#. ...#. #..#. .##..",
	"K": "#...# #..#. #.#.. ##... #.#.. #..#. #...#",
	"L": "#.... #.... #.... #.... #.... #.... #####",
	"M": "#...# ##.## #.#.# #.#.# #...# #...# #...#",
	"N": "#...# #...# ##..# #.#.# #..## #...# #...#",
	"O": ".###. #...# #...# #...# #...# #...# .###.",
	"P": "####. #...# #...# ####. #.... #.... #....",
	"Q": ".###. #...# #...# #...# #.#.# #..#. .##.#",
	"R": "####. #...# #...# ####. #.#.. #..#. #...#",
	"S": ".###. #...# #.... .###. ....# #...# .###.",
	"T": "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
	"U": "#...# #...# #...# #...# #...# #...# .###.",
	"V": "#...# #...# #...# #...# #...# .#.#. ..#..",
	"W": "#...# #...# #...# #.#.# #.#.# #.#.# .#.#.",
	"X": "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
	"Y": "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..",
	"Z": "##### ....# ...#. ..#.. .#... #.... #####",
	"a": ".... .... .##. ...# .### #..# .###",
	"b": "#... #... ###. #..# #..# #..# ###.",
	"c": "... ... .## #.. #.. #.. .##",
	"d": "...# ...# .### #..# #..# #..# .###",
	"e": ".... .... .##. #..# #### #... .###",
	"f": "..# .#. ### .#. .#. .#. .#.",
	"g": ".... .... .### #..# #..# #..# .### ...# .##.",
	"h": "#... #... ###. #..# #..# #..# #..#",
	"i": "# . # # # # #",
	"j": "..# ... ..# ..# ..# ..# ..# ..# ##.",
	"k": "#... #... #..# #.#. ##.. #.#. #..#",
	"l": "#. #. #. #. #. #. .#",
	"m": "..... ..... ####. #.#.# #.#.# #.#.# #.#.#",
	"n": ".... .... ###. #..# #..# #..# #..#",
	"o": ".... .... .##. #..# #..# #..# .##.",
	"p": ".... .... ###. #..# #..# #..# ###. #... #...",
	"q": ".... .... .### #..# #..# #..# .### ...# ...#",
	"r": "... ... #.# ##. #.. #.. #..",
	"s": ".... .... .### #... .##. ...# ###.",
	"t": ".#. .#. ### .#. .#. .#. ..#",
	"u": ".... .... #..# #..# #..# #..# .###",
	"v": "..... ..... #...# #...# .#.#. .#.#. ..#..",
	"w": "..... ..... #...# #...# #.#.# #.#.# .#.#.",
	"x": ".... .... #..# #..# .##. #..# #..#",
	"y": ".... .... #..# #..# #..# #..# .### ...# .##.",
	"z": ".... .... #### ...# .##. #... ####",
	"0": ".##. #..# #..# #..# #..# #..# .##.",
	"1": ".#. ##. .#. .#. .#. .#. ###",
	"2": ".##. #..# ...# ..#. .#.. #... ####",
	"3": "###. ...# ...# .##. ...# ...# ###.",
	"4": "..#. .##. #.#. #..# #### ...# ...#",
	"5": "#### #... ###. ...# ...# #..# .##.",
	"6": ".##. #... #... ###. #..# #..# .##.",
	"7": "#### ...# ..#. ..#. .#.. .#.. .#..",
	"8": ".##. #..# #..# .##. #..# #..# .##.",
	"9": ".##. #..# #..# .### ...# ...# .##.",
	".": ". . . . . . #",
	",": ". . . . . . # # .",
	":": ". . # . . . #",
	";": ". . # . . . # # .",
	"!": "# # # # # . #",
	"?": ".##. #..# ...# ..#. .#.. .... .#..",
	"'": "# # . . . . .",
	"\"": "#.# #.# ... ... ... ... ...",
	"-": "... ... ... ### ... ... ...",
	"+": "... ... .#. ### .#. ... ...",
	"=": "... ... ### ... ### ... ...",
	"/": "...# ...# ..#. .#.. #... #... ....",
	"(": ".# #. #. #. #. #. .#",
	")": "#. .# .# .# .# .# #.",
	"%": "##..# ##.#. ...#. ..#.. .#... .#.## #..##",
	"°": ".#. #.# .#. ... ... ... ...",
	"×": "..... #...# .#.#. ..#.. .#.#. #...# .....",
}

static var _texture: ImageTexture
static var _regions := {}


## Width in pixels of a line of text.
static func width(text: String) -> int:
	_ensure_built()
	var total := 0
	for character in text:
		total += _advance(character)
	return maxi(total - LETTER_SPACING, 0)


## Draws a line of text with its top-left corner at the given point.
static func draw(canvas: CanvasItem, top_left: Vector2, text: String, color: Color) -> void:
	_ensure_built()
	var cursor := top_left.floor()
	for character in text:
		var region: Rect2 = _regions.get(character, _regions["?"]) if character != " " else Rect2()
		if region.size.x > 0.0:
			canvas.draw_texture_rect_region(_texture, Rect2(cursor, region.size), region, color)
		cursor.x += _advance(character)


static func _advance(character: String) -> int:
	if character == " ":
		return SPACE_WIDTH + LETTER_SPACING
	var region: Rect2 = _regions.get(character, _regions["?"])
	return int(region.size.x) + LETTER_SPACING


## Paints every glyph white into one strip, once, so drawing is one textured rectangle per
## letter and color comes from modulation.
static func _ensure_built() -> void:
	if _texture != null:
		return
	var total_width := 0
	for character: String in GLYPHS:
		total_width += glyph_rows(character)[0].length() + 1
	var image := Image.create_empty(total_width, HEIGHT, false, Image.FORMAT_RGBA8)
	var x := 0
	for character: String in GLYPHS:
		var rows := glyph_rows(character)
		var glyph_width := rows[0].length()
		for y in rows.size():
			for column in glyph_width:
				if rows[y][column] == "#":
					image.set_pixel(x + column, y, Color.WHITE)
		_regions[character] = Rect2(x, 0, glyph_width, HEIGHT)
		x += glyph_width + 1
	_texture = ImageTexture.create_from_image(image)


static func glyph_rows(character: String) -> PackedStringArray:
	return (GLYPHS[character] as String).split(" ")
