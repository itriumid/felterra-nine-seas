class_name InterfaceTheme
extends RefCounted
## The look of every Godot control in the game: our pixel font, graphite panels, off-white text,
## and pastel pink for the one thing that matters at a time (the primary action, and focus).
## Every text color clears 4.5:1 on what it sits on, and the focus outline 3:1.

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font = PixelFont.font()
	theme.default_font_size = PixelFont.HEIGHT

	theme.set_stylebox("panel", "PanelContainer", _box(Palette.PANEL, 6))
	theme.set_stylebox("panel", "Panel", _box(Palette.PANEL, 6))
	theme.set_color("font_color", "Label", Palette.TEXT)
	theme.set_constant("line_spacing", "Label", PixelFont.LINE_HEIGHT - PixelFont.HEIGHT)

	theme.set_stylebox("normal", "Button", _box(Palette.PANEL_RAISED, 3))
	theme.set_stylebox("hover", "Button", _box(Palette.PANEL_HOVER, 3))
	theme.set_stylebox("pressed", "Button", _box(Palette.PLAYER, 3))
	theme.set_stylebox("disabled", "Button", _box(Palette.PANEL, 3))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(1)
	focus.border_color = Palette.PLAYER
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Palette.TEXT)
	theme.set_color("font_focus_color", "Button", Palette.TEXT)
	theme.set_color("font_pressed_color", "Button", Palette.PANEL)
	theme.set_color("font_hover_pressed_color", "Button", Palette.PANEL)
	theme.set_color("font_disabled_color", "Button", Palette.TEXT_MUTED)

	# The primary action: pink, with graphite text on it.
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _box(Palette.PLAYER, 3))
	theme.set_stylebox("hover", "PrimaryButton", _box(Palette.PLAYER, 3))
	theme.set_color("font_color", "PrimaryButton", Palette.PANEL)
	theme.set_color("font_hover_color", "PrimaryButton", Palette.PANEL)
	theme.set_color("font_focus_color", "PrimaryButton", Palette.PANEL)
	var primary_focus := focus.duplicate()
	primary_focus.border_color = Palette.TEXT
	theme.set_stylebox("focus", "PrimaryButton", primary_focus)

	# The tab that's open: drawn as pressed, so its edge and color both mark it.
	theme.set_type_variation("OpenTab", "Button")
	theme.set_stylebox("normal", "OpenTab", _box(Palette.PANEL_HOVER, 3, Palette.PLAYER))
	theme.set_stylebox("hover", "OpenTab", _box(Palette.PANEL_HOVER, 3, Palette.PLAYER))

	theme.set_type_variation("MutedLabel", "Label")
	theme.set_color("font_color", "MutedLabel", Palette.TEXT_MUTED)
	_theme = theme
	return theme


static func _box(color: Color, padding: int, underline := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_left = padding + 1
	box.content_margin_right = padding + 1
	box.content_margin_top = padding - 1
	box.content_margin_bottom = padding
	if underline.a > 0.0:
		box.border_width_bottom = 1
		box.border_color = underline
	return box
