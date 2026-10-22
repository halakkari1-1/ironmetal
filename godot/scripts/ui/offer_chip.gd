class_name OfferChip
extends Control
## The lobby's offers button, up in the top bar: a purple premium chip with the featured car's art in a round
## window, a light sweep running across it every few seconds, a breathing glow round the edge and a small "NEW"
## tag that bobs. Tapping it opens the offers window.

signal pressed

var text := "OFFERS"
var art: Texture2D
var _t := 0.0
var _down := false
var _label: Label
var _new: Label
var _img: TextureRect

const ROUND := """
shader_type canvas_item;
void fragment() {
	float d = length(UV - vec2(0.5));
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb, c.a * (1.0 - smoothstep(0.47, 0.5, d)));
}
"""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(280, 76)
	_img = TextureRect.new()
	_img.texture = art
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = ROUND
	var m := ShaderMaterial.new()
	m.shader = sh
	_img.material = m
	add_child(_img)
	_label = UI.label(text, 30, Color.WHITE, UI.font_head)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color(0.15, 0.02, 0.25, 0.9))
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_new = UI.label("NEW", 15, Color(0.12, 0.04, 0.0), UI.font_title)
	_new.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_new.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_new)
	resized.connect(_place)
	_place()


func _place() -> void:
	var h := size.y
	var r := h - 14.0
	_img.position = Vector2(8, 7)
	_img.size = Vector2(r, r)
	_label.position = Vector2(r + 22, 0)
	_label.size = Vector2(size.x - r - 30, h)
	_new.size = Vector2(52, 22)


func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT) or e is InputEventScreenTouch:
		if e.pressed:
			_down = true
		elif _down:
			_down = false
			if Rect2(Vector2.ZERO, size).has_point(e.position):
				Sfx.play("click")
				pressed.emit()
		accept_event()


func _process(dt: float) -> void:
	_t += dt
	# pops in when the lobby opens
	var k: float = clamp(_t / 0.5, 0.0, 1.0)
	var pop := 1.0 + 2.7 * pow(k - 1.0, 3) + 1.7 * pow(k - 1.0, 2)
	scale = Vector2.ONE * (0.5 + 0.5 * pop) * (0.96 if _down else 1.0)
	modulate.a = k
	pivot_offset = size / 2
	_new.position = Vector2(size.x - 46, -10 + sin(_t * 3.2) * 2.5)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rad := size.y * 0.5
	# breathing glow around the chip
	var pulse := 0.5 + 0.5 * sin(_t * 2.4)
	for i in 5:
		var g := float(i + 1) * 2.2
		_round_rect(r.grow(g), rad + g, Color(0.75, 0.35, 1.0, (0.12 - i * 0.02) * (0.6 + 0.6 * pulse)), true)
	# body: deep purple to violet, lighter on top
	_round_rect(r, rad, Color(0.24, 0.06, 0.42), true)
	_round_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, r.size.y * 0.5)), rad - 2, Color(0.55, 0.25, 0.85, 0.55), true)
	# light sweep every 3.5 s
	var ph := fmod(_t, 3.5) / 0.9
	if ph < 1.0:
		var x: float = lerp(-size.x * 0.3, size.x * 1.2, ph)
		var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + 34, 0), Vector2(x + 6, size.y), Vector2(x - 28, size.y)])
		var clip := _clip(pts, r)
		if clip.size() >= 3:
			draw_colored_polygon(clip, Color(1, 1, 1, 0.28))
	# rim
	_round_rect(r, rad, Color(0.85, 0.6, 1.0, 0.9), false, 2.0)
	# ring round the art
	var c := Vector2(8 + (size.y - 14) / 2, size.y / 2)
	draw_arc(c, (size.y - 14) / 2 + 1.5, 0, TAU, 40, Color(1, 0.85, 0.4, 0.95), 2.5, true)
	# the NEW tag
	var tag := Rect2(_new.position - Vector2(0, 1), _new.size)
	_round_rect(tag, 11, Color(1, 0.8, 0.25), true)


func _round_rect(r: Rect2, rad: float, col: Color, fill: bool, width := 1.0) -> void:
	rad = min(rad, r.size.y / 2, r.size.x / 2)
	var pts := PackedVector2Array()
	var corners := [[r.position + Vector2(r.size.x - rad, rad), -PI / 2], [r.position + Vector2(r.size.x - rad, r.size.y - rad), 0.0],
		[r.position + Vector2(rad, r.size.y - rad), PI / 2], [r.position + Vector2(rad, rad), PI]]
	for c in corners:
		for k in 9:
			var a: float = c[1] + PI / 2 * k / 8.0
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	if fill:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, width, true)


func _clip(pts: PackedVector2Array, r: Rect2) -> PackedVector2Array:
	var box := PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)])
	var res := Geometry2D.intersect_polygons(pts, box)
	return res[0] if res.size() > 0 else PackedVector2Array()
