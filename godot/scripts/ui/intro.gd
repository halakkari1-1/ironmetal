class_name Intro
extends CanvasLayer
## The opening on every launch: the designer's emblem is shot up (sparks, smoking bullet holes) while the
## credit fades in, then everything fades into the lobby. A tap skips it. The lobby loads underneath meanwhile.

signal done

const LOGO := preload("res://assets/ui/hussain_logo.png")
const FIRE := preload("res://assets/vfx/fb_fire.png")
const SHOTS := 7
const T_SHOTS := 0.9          # first shot
const T_GAP := 0.2            # between shots
const T_IGNITE := 999.0       # no fire: the emblem only takes the hits
const T_CREDIT := 2.6
const T_FADE := 4.7
const T_END := 5.5

var _t := 0.0
var _root: Control
var _stage: Control           # shaken as a whole
var _logo: TextureRect
var _mat: ShaderMaterial
var _flash: ColorRect
var _black: ColorRect
var _credit: Control
var _holes: Array = []        # [uv, time hit]
var _flames: Array = []       # {sprite, born, size}
var _embers: CPUParticles2D
var _next_shot := 0
var _shake := 0.0
var _ignited := false
var _finished := false


const SHADER := """
shader_type canvas_item;
uniform vec4 holes[8];      // xy: uv of a bullet hole, z: seconds since hit (<0: not yet), w: unused
uniform float burn = 0.0;   // 0..1 how far the fire has spread
uniform float t = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; } return v; }

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 asp = vec2(1.26, 1.0);
	float heat = 0.0;
	float hole = 0.0;
	float rim = 0.0;
	for (int i = 0; i < 8; i++) {
		if (holes[i].z < 0.0) continue;
		float d = length((UV - holes[i].xy) * asp);
		float age = holes[i].z;
		hole = max(hole, 1.0 - smoothstep(0.013, 0.02, d));
		rim = max(rim, (1.0 - smoothstep(0.02, 0.045, d)) * (0.35 + 0.65 * exp(-age * 2.0)));
		heat = max(heat, (1.0 - smoothstep(0.0, 0.06 + burn * 0.55, d)) * burn);
	}
	float n = fbm(UV * 7.0 + vec2(0.0, -t * 1.4));
	heat = clamp(heat * (0.55 + 0.9 * n) + burn * 0.25 * n, 0.0, 1.0);
	// metal heating up: red -> orange -> yellow-white at the hottest, charred dark where it has burnt longest
	vec3 base = c.rgb * (1.0 - 0.45 * burn);
	vec3 hot = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.85, 0.45), smoothstep(0.55, 1.0, heat));
	vec3 col = mix(base, hot * 1.25, smoothstep(0.35, 0.95, heat) * 0.8);
	col = mix(col, vec3(0.05, 0.03, 0.02), smoothstep(0.75, 0.95, heat * burn) * 0.5);
	col += vec3(1.0, 0.55, 0.15) * rim * 2.0;
	col = mix(col, vec3(0.02, 0.01, 0.01), hole);
	COLOR = vec4(col, c.a);
}
"""


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_input)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stage)
	_logo = TextureRect.new()
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_logo.material = _mat
	_stage.add_child(_logo)
	_embers = CPUParticles2D.new()
	_embers.emitting = false
	_embers.amount = 90
	_embers.lifetime = 2.2
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.direction = Vector2(0, -1)
	_embers.spread = 25.0
	_embers.gravity = Vector2(0, -60)
	_embers.initial_velocity_min = 40.0
	_embers.initial_velocity_max = 140.0
	_embers.scale_amount_min = 1.5
	_embers.scale_amount_max = 4.0
	_embers.color_ramp = _ramp([Color(1, 0.9, 0.5, 1), Color(1, 0.45, 0.1, 0.9), Color(0.6, 0.1, 0.0, 0)])
	_embers.material = _add_mat()
	_stage.add_child(_embers)
	_credit = VBoxContainer.new()
	(_credit as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_credit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credit.modulate.a = 0.0
	var l1 := UI.label(I18n.t("DESIGNED BY"), 26, Color(1, 0.8, 0.6, 0.85), UI.font_head)
	var l2 := UI.label(I18n.t("ENG. HUSSAIN AL-AKARI"), 44, Color(1, 0.93, 0.85), UI.font_head)
	for l in [l1, l2]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_credit.add_child(l)
	_stage.add_child(_credit)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0.75, 0.4, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.material = _add_mat()
	_root.add_child(_flash)
	_black = ColorRect.new()
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_black)
	_pick_holes()
	_root.resized.connect(_layout)
	_layout.call_deferred()


func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols)
	var offs := PackedFloat32Array()
	for i in cols.size():
		offs.append(float(i) / (cols.size() - 1))
	g.offsets = offs
	return g


func _layout() -> void:
	var vp := _root.size
	var h: float = vp.y * 0.5
	var w: float = h * LOGO.get_width() / LOGO.get_height()
	_logo.size = Vector2(w, h)
	_logo.position = Vector2((vp.x - w) / 2, vp.y * 0.12)
	_logo.pivot_offset = _logo.size / 2
	_embers.position = _logo.position + Vector2(w / 2, h * 0.55)
	_embers.emission_rect_extents = Vector2(w * 0.4, h * 0.3)
	_credit.position = Vector2(0, vp.y * 0.69)
	_credit.size = Vector2(vp.x, vp.y * 0.2)


## Bullet holes land on the emblem itself: random opaque spots, spread over its width.
func _pick_holes() -> void:
	var img := LOGO.get_image()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var tries := 0
	while _holes.size() < SHOTS and tries < 4000:
		tries += 1
		var u := rng.randf_range(0.12, 0.88)
		var v := rng.randf_range(0.15, 0.85)
		var px := img.get_pixel(int(u * (img.get_width() - 1)), int(v * (img.get_height() - 1)))
		if px.a < 0.9:
			continue
		var ok := true
		for h in _holes:
			if Vector2(u - h[0].x, v - h[0].y).length() < 0.11:
				ok = false
		if ok:
			_holes.append([Vector2(u, v), -1.0])
	_holes.sort_custom(func(a, b): return a[0].x < b[0].x if randf() < 0.5 else a[0].x > b[0].x)


func _uv_to_screen(uv: Vector2) -> Vector2:
	return _logo.position + uv * _logo.size


func _on_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed and _t > 1.0 and _t < T_FADE:
		_t = T_FADE   # skip: straight to the fade


func _process(dt: float) -> void:
	if _finished:
		return
	_t += dt
	# emblem fades in, a slow push in
	_logo.modulate.a = clamp((_t - 0.15) / 0.5, 0.0, 1.0)
	_logo.scale = Vector2.ONE * (0.94 + 0.06 * min(1.0, _t / T_FADE))
	# gunfire
	while _next_shot < _holes.size() and _t >= T_SHOTS + _next_shot * T_GAP + (0.12 if _next_shot > 3 else 0.0):
		_shoot(_next_shot)
		_next_shot += 1
	# fire
	if not _ignited and _t >= T_IGNITE:
		_ignite()
	var burn: float = clamp((_t - T_IGNITE) / 2.2, 0.0, 1.0)
	_mat.set_shader_parameter("burn", burn)
	_mat.set_shader_parameter("t", _t)
	var arr: Array = []
	for i in 8:
		if i < _holes.size() and _holes[i][1] >= 0:
			arr.append(Vector4(_holes[i][0].x, _holes[i][0].y, _t - _holes[i][1], 0))
		else:
			arr.append(Vector4(0, 0, -1, 0))
	_mat.set_shader_parameter("holes", arr)
	for f in _flames:
		var age: float = _t - f.born
		var s: float = f.size * clamp(age / 0.6, 0.0, 1.0) * (0.92 + 0.08 * sin(_t * 9 + f.size))
		f.sprite.scale = Vector2.ONE * s
		f.sprite.frame = int((_t + f.phase) * 24.0) % 36
		f.sprite.position = _uv_to_screen(f.uv) - Vector2(0, f.sprite.get_rect().size.y * s * 0.32)
	# credit
	_credit.modulate.a = clamp((_t - T_CREDIT) / 0.7, 0.0, 1.0)
	# shake and flashes
	_shake = max(0.0, _shake - dt * 4.0)
	_stage.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 14.0
	_flash.color.a = max(0.0, _flash.color.a - dt * 6.0)
	# out
	_black.color.a = clamp((_t - T_FADE) / (T_END - T_FADE - 0.2), 0.0, 1.0)
	if _t >= T_END - 0.2 and _t - dt < T_END - 0.2:
		done.emit()          # the lobby takes over under the black
	if _t >= T_END:
		_finished = true
		queue_free()


func _shoot(i: int) -> void:
	var h: Array = _holes[i]
	h[1] = _t
	var p := _uv_to_screen(h[0])
	var vp := _root.size
	# a tracer from off screen
	var from := Vector2(-40.0 if randf() < 0.5 else vp.x + 40.0, randf_range(vp.y * 0.1, vp.y * 0.9))
	var tr := Line2D.new()
	tr.points = PackedVector2Array([from, p])
	tr.width = 3.0
	tr.default_color = Color(1, 0.85, 0.5, 0.9)
	tr.material = _add_mat()
	_stage.add_child(tr)
	create_tween().tween_property(tr, "modulate:a", 0.0, 0.09).finished.connect(tr.queue_free)
	# sparks
	var sp := CPUParticles2D.new()
	sp.one_shot = true
	sp.explosiveness = 1.0
	sp.amount = 26
	sp.lifetime = 0.55
	sp.direction = (from - p).normalized()
	sp.spread = 70.0
	sp.initial_velocity_min = 180.0
	sp.initial_velocity_max = 520.0
	sp.gravity = Vector2(0, 900)
	sp.scale_amount_min = 1.5
	sp.scale_amount_max = 3.5
	sp.color_ramp = _ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.15, 1), Color(0.8, 0.2, 0.0, 0)])
	sp.material = _add_mat()
	sp.position = p
	_stage.add_child(sp)
	sp.emitting = true
	get_tree().create_timer(1.0).timeout.connect(sp.queue_free)
	_shake = min(1.0, _shake + 0.45)
	_flash.color.a = 0.10
	Sfx.play(["gun_heavy_1", "gun_heavy_2", "gun_heavy_3"][i % 3], 0.9, randf_range(0.92, 1.05))
	Sfx.play("hit", 0.8, randf_range(0.8, 1.1))


func _ignite() -> void:
	_ignited = true
	_embers.emitting = true
	Sfx.play("boom_small", 0.8, 0.9)
	Sfx.play("flame", 0.9)
	_flash.color = Color(1, 0.5, 0.15, 0.22)
	_shake = 0.6
	# flames from every bullet hole, then along the horns and the crown
	var spots: Array = []
	for h in _holes:
		spots.append([h[0], 0.0])
	for uv in [Vector2(0.07, 0.12), Vector2(0.93, 0.12), Vector2(0.3, 0.35), Vector2(0.7, 0.35), Vector2(0.5, 0.62), Vector2(0.5, 0.9)]:
		spots.append([uv, 0.45 + randf() * 0.5])
	for s in spots:
		var spr := Sprite2D.new()
		spr.texture = FIRE
		spr.hframes = 6
		spr.vframes = 6
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		spr.material = m
		spr.scale = Vector2.ZERO
		_stage.add_child(spr)
		_stage.move_child(spr, _stage.get_child_count() - 2)   # in front of the emblem, behind the credit
		_flames.append({"sprite": spr, "uv": s[0], "born": _t + s[1], "size": _logo.size.y / 420.0 * randf_range(0.38, 0.62), "phase": randf() * 3.0})
