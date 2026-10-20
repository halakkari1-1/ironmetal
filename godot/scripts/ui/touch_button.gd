class_name TouchButton
extends Control
## Round on-screen button with a label, an optional badge (ammo, cooldown seconds) and a cooldown sweep.
## Presses are routed by the HUD, which tracks fingers by index; this control only draws itself.

var text := ""
var badge := ""
var color := Color.WHITE
var cooldown := 0.0   # 0 ready .. 1 just used
var down := false
var pulse := 0.0


static func make(t: String, d: float, c: Color) -> TouchButton:
	var b := TouchButton.new()
	b.text = t
	b.color = c
	b.size = Vector2(d, d)
	b.custom_minimum_size = b.size
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func hit(p: Vector2) -> bool:
	return visible and (p - (position + size / 2)).length() <= size.x * 0.62


func _process(dt: float) -> void:
	if pulse > 0:
		pulse -= dt
		queue_redraw()


func _draw() -> void:
	var r := size.x / 2
	var c := size / 2
	var ready := cooldown <= 0.001
	var fill := Color(color, 0.32 if down else (0.16 if ready else 0.08))
	draw_circle(c, r, Color(0.04, 0.035, 0.03, 0.45))
	draw_circle(c, r, fill)
	draw_arc(c, r - 2, 0, TAU, 48, Color(color, 0.85 if ready else 0.35), 3.0, true)
	if not ready:
		draw_arc(c, r - 2, -PI / 2, -PI / 2 + TAU * (1 - cooldown), 48, color, 4.0, true)
	if pulse > 0:
		draw_arc(c, r + (0.4 - pulse) * 40, 0, TAU, 48, Color(color, pulse * 2), 3.0, true)
	var font: Font = UI.font_head
	var fs := int(clamp(size.x * 0.2, 13, 28))
	if text.length() > 8:
		fs = int(fs * 0.7)
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, c - Vector2(ts.x / 2, -fs * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.95 if ready else 0.6))
	if badge != "":
		var bs := 16
		var bw: float = max(26.0, font.get_string_size(badge, HORIZONTAL_ALIGNMENT_CENTER, -1, bs).x + 10)
		var br := Rect2(Vector2(size.x - bw * 0.8, size.y - 24), Vector2(bw, 24))
		draw_rect(br, Color("f5c542"), true)
		draw_string(font, br.position + Vector2((bw - font.get_string_size(badge, HORIZONTAL_ALIGNMENT_CENTER, -1, bs).x) / 2, 18), badge, HORIZONTAL_ALIGNMENT_CENTER, -1, bs, Color(0.1, 0.08, 0.05))
