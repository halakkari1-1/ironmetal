class_name AvatarBadge
extends Control
## The player's photo in a round frame dressed by rank: plain for Scrap, a warm glow for Rust, a light sweep for
## Steel, orbiting sparks for Gold, a turning aura for Platinum and a shifting prism with sparks for Diamond.
## A small rank emblem with the level sits on the frame. Rank emblem art can replace the drawn one by adding
## assets/ui/ranks/<rank id>.png.

var tier: Dictionary = Profile.TIERS[0]
var lvl := 1
var photo: Texture2D
var initial := "?"
var show_level := true
var _t := 0.0
var _img: TextureRect
var _emblems := {}

const MASK := """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = length(UV - vec2(0.5));
	COLOR = vec4(c.rgb, c.a * (1.0 - smoothstep(0.485, 0.5, d)));
}
"""


static func for_me(px: float) -> AvatarBadge:
	var b := AvatarBadge.new()
	b.custom_minimum_size = Vector2(px, px)
	b.size = Vector2(px, px)
	b.refresh()
	return b


func refresh() -> void:
	lvl = Profile.level()
	tier = Profile.tier_of(lvl)
	photo = Profile.avatar()
	initial = Save.player_name().substr(0, 1).to_upper()
	if _img:
		_img.texture = photo
		_img.visible = photo != null
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_SCALE
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = MASK
	var m := ShaderMaterial.new()
	m.shader = sh
	_img.material = m
	_img.show_behind_parent = true   # the frame and the rank emblem draw over the photo
	add_child(_img)
	_img.texture = photo
	_img.visible = photo != null
	resized.connect(_place)
	_place()


func _place() -> void:
	var r := _inner_r()
	var c := size / 2
	_img.position = c - Vector2(r, r)
	_img.size = Vector2(r, r) * 2


func _inner_r() -> float:
	return min(size.x, size.y) * 0.5 * 0.78


func _process(dt: float) -> void:
	if tier.fx != "none" and is_visible_in_tree():
		_t += dt
		queue_redraw()


func _draw() -> void:
	var c := size / 2
	var R: float = min(size.x, size.y) * 0.5
	var r := _inner_r()
	var col: Color = tier.color
	var fx: String = tier.fx
	var ring_w: float = max(3.0, R * 0.09)
	var rr := r + ring_w * 0.5 + 1
	if fx == "prism":
		col = Color.from_hsv(fmod(_t * 0.12, 1.0), 0.45, 1.0)
	# glow behind the frame
	if fx != "none":
		var pulse := 0.6 + 0.4 * sin(_t * 2.4)
		for i in 6:   # soft halo outside the frame (rings, so the photo underneath isn't tinted)
			var k := float(i) / 6.0
			draw_arc(c, rr + ring_w * (0.8 + k * 1.8), 0, TAU, 48, Color(col, (0.16 if fx == "glow" else 0.2) * (1 - k) * pulse), ring_w * 0.6, true)
	# the photo, or the first letter of the name on a dark disc
	if photo == null:
		draw_circle(c, r, Color(0.13, 0.12, 0.11))
		var f: Font = UI.font_head
		var fs := int(r * 1.1)
		var w := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w / 2, fs * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, 0.9))
	# frame
	draw_arc(c, rr, 0, TAU, 64, Color(col.darkened(0.35), 1.0), ring_w + 2, true)
	draw_arc(c, rr, 0, TAU, 64, col, ring_w, true)
	match fx:
		"shine":   # a bright highlight travelling round the frame
			var a := fmod(_t * 1.6, TAU)
			draw_arc(c, rr, a, a + 0.9, 16, Color(1, 1, 1, 0.85), ring_w * 0.6, true)
		"sparks", "prism":
			for i in 5:
				var a := _t * (0.9 + i * 0.13) + i * TAU / 5
				var p := c + Vector2(cos(a), sin(a)) * (rr + ring_w * 0.2)
				var s: float = ring_w * (0.5 + 0.35 * sin(_t * 6 + i))
				_star(p, s, Color(1, 0.97, 0.8, 0.95))
		"aura":
			for i in 2:
				var a := _t * (1.4 if i == 0 else -1.0) + i * PI
				draw_arc(c, rr + ring_w * 1.4, a, a + 1.6, 20, Color(col, 0.75), ring_w * 0.45, true)
	# rank emblem with the level
	if show_level:
		var e := c + Vector2(R * 0.62, R * 0.62)
		var es: float = R * 0.36
		var tex := _emblem(tier.id)
		if tex:
			draw_texture_rect(tex, Rect2(e - Vector2(es, es), Vector2(es, es) * 2), false)
		else:
			var pts := PackedVector2Array([e + Vector2(0, -es), e + Vector2(es * 0.9, -es * 0.45), e + Vector2(es * 0.75, es * 0.6),
				e + Vector2(0, es), e + Vector2(-es * 0.75, es * 0.6), e + Vector2(-es * 0.9, -es * 0.45)])
			draw_colored_polygon(pts, Color(0.08, 0.07, 0.06))
			pts.append(pts[0])
			draw_polyline(pts, col, max(2.0, es * 0.14), true)
		var f2: Font = UI.font_head
		var fs2 := int(es * 0.95)
		var txt := str(lvl)
		var w2 := f2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		draw_string_outline(f2, e + Vector2(-w2 / 2, fs2 * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 4, Color(0, 0, 0, 0.8))
		draw_string(f2, e + Vector2(-w2 / 2, fs2 * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color.WHITE)


func _star(p: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.25, -s * 0.25), p + Vector2(s, 0), p + Vector2(s * 0.25, s * 0.25),
		p + Vector2(0, s), p + Vector2(-s * 0.25, s * 0.25), p + Vector2(-s, 0), p + Vector2(-s * 0.25, -s * 0.25)]), col)


func _emblem(id: String) -> Texture2D:
	if not _emblems.has(id):
		var path := "res://assets/ui/ranks/%s.png" % id
		_emblems[id] = load(path) if ResourceLoader.exists(path) else null
	return _emblems[id]
