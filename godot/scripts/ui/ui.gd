class_name UI
extends RefCounted
## Shared look for every screen: dark glass panels, warm accent, Saira for Latin text with Cairo as the fallback
## for Arabic (Godot shapes and lays out Arabic right-to-left on its own), plus small builders for common widgets.

const ACCENT := Color("ff7a2e")
const ACCENT_2 := Color("ffb347")
const TEXT := Color("f3ece2")
const DIM := Color("b9ab9b")
const GOOD := Color("62e07a")
const BAD := Color("ff5a4a")
const GLASS := Color(0.07, 0.065, 0.06, 0.62)
const GLASS_EDGE := Color(1, 0.85, 0.7, 0.16)

static var theme: Theme
static var font_body: FontVariation
static var font_head: FontVariation
static var font_title: FontVariation


static func init() -> void:
	if theme:
		return
	var cairo: FontFile = load("res://assets/fonts/Cairo-Variable.ttf")
	font_body = _font("res://assets/fonts/SairaCondensed-SemiBold.ttf", cairo)
	font_head = _font("res://assets/fonts/SairaCondensed-ExtraBold.ttf", cairo)
	font_title = _font("res://assets/fonts/SairaStencilOne-Regular.ttf", cairo)
	theme = Theme.new()
	theme.default_font = font_body
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	theme.set_constant("outline_size", "Label", 0)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "Button", button_box(state))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(TEXT, 0.4))
	theme.set_font("font", "Button", font_head)
	theme.set_font_size("font_size", "Button", 24)
	theme.set_stylebox("panel", "PanelContainer", glass())
	theme.set_stylebox("panel", "Panel", glass())
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = ACCENT
	grabber.set_corner_radius_all(10)
	for k in [["slider", Color(1, 1, 1, 0.14)], ["grabber_area", Color(ACCENT, 0.85)], ["grabber_area_highlight", ACCENT]]:
		var sb := _flat(k[1], 6, 0)
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		theme.set_stylebox(k[0], "HSlider", sb)
	var scroll := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ScrollContainer", scroll)


static func _font(path: String, fallback: Font) -> FontVariation:
	var base: FontFile = load(path)
	base.fallbacks = [fallback]
	var v := FontVariation.new()
	v.base_font = base
	return v


static func _flat(c: Color, r: int, border: int, edge := GLASS_EDGE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.set_border_width_all(border)
	s.border_color = edge
	s.anti_aliasing = true
	return s


static func glass(alpha := 0.62, r := 18) -> StyleBoxFlat:
	var s := _flat(Color(GLASS, alpha), r, 1)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	return s


static func button_box(state: String, accent := false) -> StyleBoxFlat:
	var base := Color(ACCENT, 0.92) if accent else Color(0.1, 0.09, 0.08, 0.7)
	match state:
		"hover": base = base.lightened(0.08)
		"pressed": base = base.darkened(0.15)
		"disabled": base = Color(base, 0.35)
		"focus": base = Color(0, 0, 0, 0)
	var s := _flat(base, 14, 1, Color(1, 0.8, 0.6, 0.35) if accent else GLASS_EDGE)
	if state == "focus":
		s.border_color = Color(0, 0, 0, 0)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func label(text: String, size := 22, color := TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


static func heading(text: String, size := 34) -> Label:
	var l := label(text, size, TEXT, font_head)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	return l


## A button that lets drags through to the scroll area behind it: a finger that slides more than a few
## pixels scrolls the list instead of pressing the button it started on.
static func button(text: String, cb: Callable, accent := false, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if accent:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(state, button_box(state, true))
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.button_down.connect(func(): b.set_meta("down_at", b.get_global_mouse_position()))
	b.pressed.connect(func():
		var start: Vector2 = b.get_meta("down_at", b.get_global_mouse_position())
		if start.distance_to(b.get_global_mouse_position()) > 14.0:
			return
		Sfx.play("click", 0.8)
		cb.call())
	b.focus_mode = Control.FOCUS_NONE
	return b


## A wide slider with a visible track, fill and a big round grab handle.
static func slider(value: float, lo: float, hi: float, on_change: Callable, on_release: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 40.0
	s.value = value
	s.custom_minimum_size = Vector2(360, 48)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := _flat(Color(1, 1, 1, 0.16), 8, 1)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	var fill := _flat(ACCENT, 8, 0)
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob_texture(30)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	s.value_changed.connect(func(v): on_change.call(v))
	s.drag_ended.connect(func(_c): on_release.call())
	s.focus_mode = Control.FOCUS_NONE
	return s


static var _knob: ImageTexture


static func _knob_texture(d: int) -> Texture2D:
	if _knob:
		return _knob
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) / 2.0
	for y in d:
		for x in d:
			var r := Vector2(x - c, y - c).length()
			var a: float = clamp(c - r + 0.5, 0.0, 1.0)
			var col := Color(1, 1, 1, a) if r < c - 3 else Color(ACCENT.r, ACCENT.g, ACCENT.b, a)
			img.set_pixel(x, y, col)
	_knob = ImageTexture.create_from_image(img)
	return _knob


static func panel(alpha := 0.62) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", glass(alpha))
	return p


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## A horizontal stat bar (0..1).
static func bar(value: float, color := ACCENT, width := 160.0, height := 10.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.value = clamp(value, 0.0, 1.0)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(width, height)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.1), int(height / 2), 0))
	p.add_theme_stylebox_override("fill", _flat(color, int(height / 2), 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func spacer(h := 0.0, w := 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if w == 0.0:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if h == 0.0:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c
