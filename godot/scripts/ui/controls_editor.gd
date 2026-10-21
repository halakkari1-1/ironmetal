class_name ControlsEditor
extends Control
## Touch-button layout editor: drag the fire, rocket and ability buttons anywhere, tap one and size it with the
## slider, and size the steering stick. Saved in Save.state.layout as fractions of the screen, so the same
## layout fits any phone or tablet. The HUD reads it when a match starts.

signal done

## Default layout: [x, y] in fractions of the screen, and size multiplier.
const DEFAULTS := {"fire": [0.906, 0.822, 1.0], "rocket": [0.805, 0.872, 1.0], "special": [0.928, 0.628, 1.0]}
const BASE := {"fire": 116.0, "rocket": 80.0, "special": 80.0}

var layout := {}
var stick_scale := 1.0
var _buttons := {}
var _sel := "fire"
var _drag := ""
var _drag_off := Vector2.ZERO
var _size_slider: HSlider
var _sel_label: Label


static func current() -> Dictionary:
	var out := {}
	var saved = Save.state.get("layout")
	for k in DEFAULTS:
		var v: Array = DEFAULTS[k].duplicate()
		if saved is Dictionary and saved.has(k):
			var s: Array = saved[k]
			v = [float(s[0]), float(s[1]), float(s[2]) if s.size() > 2 else 1.0]
		out[k] = v
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_direction = Control.LAYOUT_DIRECTION_LTR     # button spots match the match HUD, which is never mirrored
	layout = current()
	stick_scale = float(Save.state.get("stick_scale", 1.0))
	var bg := UI.full(ColorRect.new())
	bg.color = Color(0.03, 0.03, 0.03, 0.72)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var stick_hint := Label.new()
	stick_hint.text = I18n.t("Steering stick area")
	stick_hint.add_theme_font_size_override("font_size", 26)
	stick_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	stick_hint.anchor_top = 0.5
	stick_hint.anchor_bottom = 0.5
	stick_hint.offset_left = 60
	stick_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stick_hint)
	for k in ["fire", "rocket", "special"]:
		var label: String = {"fire": I18n.t("FIRE"), "rocket": I18n.t("RKT"), "special": I18n.t("Ability")}[k]
		var b := TouchButton.make(label, BASE[k], UI.ACCENT if k == "fire" else (UI.GOOD if k == "special" else Color("e8e0d0")))
		add_child(b)
		_buttons[k] = b
	var panel := UI.panel(0.85)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.offset_top = 16
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.layout_direction = Control.LAYOUT_DIRECTION_RTL if I18n.is_ar() else Control.LAYOUT_DIRECTION_LTR
	var v := UI.vbox(10)
	var tip := UI.label(I18n.t("Drag a button to move it. Tap it, then use the slider to resize."), 22)
	v.add_child(tip)
	var row := UI.hbox(12)
	_sel_label = UI.label("", 24, UI.ACCENT_2, UI.font_head)
	_sel_label.custom_minimum_size.x = 170
	row.add_child(_sel_label)
	_size_slider = UI.slider(1.0, 0.6, 1.6, func(val):
		layout[_sel][2] = val
		_place(), func(): pass)
	row.add_child(_size_slider)
	v.add_child(row)
	var row2 := UI.hbox(12)
	var sl := UI.label(I18n.t("STICK"), 24, UI.ACCENT_2, UI.font_head)
	sl.custom_minimum_size.x = 170
	row2.add_child(sl)
	row2.add_child(UI.slider(stick_scale, 0.7, 1.5, func(val): stick_scale = val, func(): pass))
	v.add_child(row2)
	var row3 := UI.hbox(12)
	var reset := UI.button(I18n.t("Reset"), func():
		layout = {}
		for k in DEFAULTS:
			layout[k] = DEFAULTS[k].duplicate()
		stick_scale = 1.0
		_select(_sel)
		_place(), false, 24)
	var save := UI.button(I18n.t("Save"), func():
		Save.state.layout = layout
		Save.state.stick_scale = stick_scale
		Save.write()
		done.emit(), true, 26)
	reset.custom_minimum_size = Vector2(180, 62)
	save.custom_minimum_size = Vector2(220, 62)
	row3.add_child(reset)
	row3.add_child(save)
	v.add_child(row3)
	panel.add_child(v)
	add_child(panel)
	resized.connect(_place)
	_select("fire")
	_place()


func _place() -> void:
	for k in _buttons:
		var b: TouchButton = _buttons[k]
		var d: float = BASE[k] * float(layout[k][2])
		b.size = Vector2(d, d)
		b.custom_minimum_size = b.size
		b.position = Vector2(layout[k][0] * size.x, layout[k][1] * size.y) - b.size / 2
		b.down = k == _sel
		b.queue_redraw()


func _select(k: String) -> void:
	_sel = k
	_sel_label.text = _buttons[k].text
	_size_slider.set_value_no_signal(float(layout[k][2]))
	_place()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			for k in _buttons:
				var b: TouchButton = _buttons[k]
				if b.hit(e.position):
					_drag = k
					_drag_off = e.position - (b.position + b.size / 2)
					_select(k)
					accept_event()
					return
		else:
			_drag = ""
	elif e is InputEventMouseMotion and _drag != "":
		var p: Vector2 = e.position - _drag_off
		p.x = clamp(p.x, 40.0, size.x - 40.0)
		p.y = clamp(p.y, 40.0, size.y - 40.0)
		layout[_drag][0] = p.x / size.x
		layout[_drag][1] = p.y / size.y
		_place()
		accept_event()
