class_name Intro
extends CanvasLayer
## The opening on every launch, filmed like an action-film slow motion: the camera rides along with a single
## bullet crawling through the air towards the designer's emblem, a ripple of displaced air trailing it. It hits:
## the picture freezes for a heartbeat with a shock ring and a burst of dust, then time snaps back to full speed,
## the camera pulls out and the rest of the burst tears into the emblem, the credit comes up, and everything fades
## into the lobby. A tap skips it. The lobby loads underneath meanwhile.

signal done

const LOGO := preload("res://assets/ui/hussain_logo.png")
const PUFF := preload("res://assets/vfx/puff.png")
const SHOTS := 7
const T_BULLET := 0.9         # the slow bullet appears
const T_HIT := 2.6            # ...and lands
const T_FREEZE := 0.32        # the frozen moment after the hit
const T_BURST := 3.3          # the rest of the burst, at full speed
const T_GAP := 0.085
const T_CREDIT := 3.9
const T_FADE := 5.9
const T_END := 6.7
const ZOOM := 1.9             # camera zoom while it rides with the bullet

var _t := 0.0
var _root: Control
var _stage: Control           # the "camera": zoomed, panned and shaken as a whole
var _logo: TextureRect
var _mat: ShaderMaterial
var _flash: ColorRect
var _black: ColorRect
var _credit: Control
var _bars: Array = []         # letterbox bars while in slow motion
var _holes: Array = []        # [uv, time hit]
var _next_shot := 1
var _shake := 0.0
var _finished := false
var _bullet: Node2D
var _from := Vector2.ZERO
var _trail: Line2D
var _rings: Array = []        # air ripples left behind the bullet: {line, born, pos}
var _ring_t := 0.0
var _shock: Line2D
var _dust: Array = []         # {sprite, vel, born, spin}
var _hit_done := false
var _whoosh_done := false

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
	# the vapour trail and the bullet
	_trail = Line2D.new()
	_trail.width = 10.0
	_trail.gradient = _ramp([Color(1, 1, 1, 0), Color(0.85, 0.9, 1.0, 0.16), Color(1, 0.9, 0.7, 0.5)])
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.material = _add_mat()
	_stage.add_child(_trail)
	_bullet = _make_bullet()
	_bullet.visible = false
	_stage.add_child(_bullet)
	_shock = Line2D.new()
	_shock.closed = true
	_shock.visible = false
	_shock.default_color = Color(1, 0.92, 0.75, 0.9)
	_shock.material = _add_mat()
	_stage.add_child(_shock)
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
	_root.add_child(_credit)
	for i in 2:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(bar)
		_bars.append(bar)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0.85, 0.6, 0)
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


## A brass slug with a hot white nose and a soft glow, pointing along +x.
func _make_bullet() -> Node2D:
	var n := Node2D.new()
	var glow := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(Vector2(cos(a) * 34, sin(a) * 11))
	glow.polygon = pts
	glow.color = Color(1, 0.7, 0.35, 0.22)
	glow.material = _add_mat()
	n.add_child(glow)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-20, -5), Vector2(8, -5), Vector2(16, -3.5), Vector2(21, 0), Vector2(16, 3.5),
		Vector2(8, 5), Vector2(-20, 5)])
	body.vertex_colors = PackedColorArray([Color(0.55, 0.38, 0.15), Color(0.95, 0.75, 0.4), Color(1, 0.9, 0.7), Color(1, 1, 0.95),
		Color(1, 0.9, 0.7), Color(0.95, 0.75, 0.4), Color(0.55, 0.38, 0.15)])
	n.add_child(body)
	var shine := Line2D.new()
	shine.points = PackedVector2Array([Vector2(-16, -2.5), Vector2(12, -2.5)])
	shine.width = 1.5
	shine.default_color = Color(1, 1, 0.9, 0.8)
	n.add_child(shine)
	return n


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
	_stage.size = vp
	var h: float = vp.y * 0.5
	var w: float = h * LOGO.get_width() / LOGO.get_height()
	_logo.size = Vector2(w, h)
	_logo.position = Vector2((vp.x - w) / 2, vp.y * 0.12)
	_credit.position = Vector2(0, vp.y * 0.69)
	_credit.size = Vector2(vp.x, vp.y * 0.2)
	# the slow bullet comes in from the upper left, off screen
	_from = Vector2(-vp.x * 0.1, vp.y * 0.06)


## Bullet holes land on the emblem itself: random opaque spots, spread over its width; the first one, the slow
## bullet's, near the middle.
func _pick_holes() -> void:
	var img := LOGO.get_image()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var tries := 0
	while _holes.size() < SHOTS and tries < 4000:
		tries += 1
		var first := _holes.is_empty()
		var u := rng.randf_range(0.4, 0.6) if first else rng.randf_range(0.12, 0.88)
		var v := rng.randf_range(0.3, 0.55) if first else rng.randf_range(0.15, 0.85)
		var px := img.get_pixel(int(u * (img.get_width() - 1)), int(v * (img.get_height() - 1)))
		if px.a < 0.9:
			continue
		var ok := true
		for h in _holes:
			if Vector2(u - h[0].x, v - h[0].y).length() < 0.11:
				ok = false
		if ok:
			_holes.append([Vector2(u, v), -1.0])


func _uv_to_stage(uv: Vector2) -> Vector2:
	return _logo.position + uv * _logo.size


func _on_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed and _t > 1.0 and _t < T_FADE:
		_t = T_FADE   # skip: straight to the fade
		_hit_done = true
		_bullet.visible = false
		_trail.visible = false
		Engine.time_scale = 1.0


## Where the camera looks (stage coordinates) and how far it is zoomed in, over time.
func _camera() -> Array:
	var target := _uv_to_stage(_holes[0][0])
	var vp := _root.size
	if _t < T_BULLET:
		return [vp / 2, 1.0]
	if _t < T_HIT:
		# riding just behind the bullet, the emblem growing ahead of it
		var b := _bullet.position
		var k: float = smoothstep(T_BULLET, T_BULLET + 0.35, _t)
		var z: float = lerp(1.0, ZOOM, k)
		var look := (vp / 2).lerp(b.lerp(target, 0.62), k)
		return [look, z]
	if _t < T_HIT + T_FREEZE:
		return [target, ZOOM * 1.08]
	# pull back out to the whole emblem
	var o: float = smoothstep(T_HIT + T_FREEZE, T_HIT + T_FREEZE + 0.45, _t)
	return [target.lerp(vp / 2, o), lerp(ZOOM * 1.08, 1.0, o)]


func _process(dt: float) -> void:
	if _finished:
		return
	_t += dt
	var vp := _root.size
	_logo.modulate.a = clamp((_t - 0.1) / 0.6, 0.0, 1.0)
	# the slow bullet
	var target := _uv_to_stage(_holes[0][0])
	if _t >= T_BULLET and _t < T_HIT and not _hit_done:
		var k: float = (_t - T_BULLET) / (T_HIT - T_BULLET)
		var pos := _from.lerp(target, k)
		var dir := (target - _from).normalized()
		_bullet.visible = true
		_bullet.position = pos
		_bullet.rotation = dir.angle()
		_bullet.scale = Vector2.ONE * (_logo.size.y / 420.0)
		var tail: Vector2 = pos - dir * min(_from.distance_to(pos), _logo.size.y * 0.9)
		_trail.points = PackedVector2Array([tail, pos.lerp(tail, 0.5), pos - dir * 14.0])
		_trail.width = 9.0 * _bullet.scale.x
		# air ripples peeling off behind it
		_ring_t -= dt
		if _ring_t <= 0.0:
			_ring_t = 0.07
			_ripple(pos - dir * 18.0 * _bullet.scale.x, dir)
		if not _whoosh_done:
			_whoosh_done = true
			Sfx.play("wind", 1.0, 0.45)
			Sfx.play("incoming", 0.5, 0.55)
	if _t >= T_HIT and not _hit_done:
		_hit()
	# ripples grow and fade (frozen while time is frozen)
	var slow := 0.08 if (_t >= T_HIT and _t < T_HIT + T_FREEZE) else 1.0
	for r in _rings.duplicate():
		r.age += dt * slow
		var a: float = r.age / 0.9
		if a >= 1.0:
			r.line.queue_free()
			_rings.erase(r)
			continue
		r.line.scale = Vector2(1.0 + a * 1.4, 1.0 + a * 2.6) * r.size
		r.line.default_color = Color(0.8, 0.88, 1.0, 0.35 * (1.0 - a))
	# shock ring and dust after the hit
	if _shock.visible:
		var sa: float = _shock_age()
		var rad: float = _logo.size.y * (0.08 + 0.75 * (1.0 - exp(-sa * 3.2)))
		_ring_points(_shock, target, rad, rad)
		_shock.width = max(1.0, 6.0 * (1.0 - clamp(sa / 0.8, 0.0, 1.0)))
		_shock.default_color.a = clamp(1.0 - sa / 0.8, 0.0, 1.0) * 0.55
		if sa > 0.8:
			_shock.visible = false
	for d in _dust.duplicate():
		var age: float = _shock_age() - d.delay
		if age < 0:
			continue
		var s: Sprite2D = d.sprite
		s.visible = true
		s.position = d.origin + d.vel * (1.0 - exp(-age * 2.2)) / 2.2
		s.rotation = d.spin * age
		s.scale = Vector2.ONE * d.size * (0.5 + age * 0.9)
		s.modulate.a = clamp(1.0 - age / 1.6, 0.0, 1.0) * 0.85
		if age > 1.6:
			s.queue_free()
			_dust.erase(d)
	# the rest of the burst
	while _hit_done and _next_shot < _holes.size() and _t >= T_BURST + (_next_shot - 1) * T_GAP:
		_shoot(_next_shot)
		_next_shot += 1
	var arr: Array = []
	for i in 8:
		if i < _holes.size() and _holes[i][1] >= 0:
			arr.append(Vector4(_holes[i][0].x, _holes[i][0].y, (_t - _holes[i][1]) * slow, 0))
		else:
			arr.append(Vector4(0, 0, -1, 0))
	_mat.set_shader_parameter("holes", arr)
	_mat.set_shader_parameter("t", _t)
	# camera
	var cam := _camera()
	var z: float = cam[1]
	_shake = max(0.0, _shake - dt * 3.5) if slow == 1.0 else _shake
	_stage.scale = Vector2.ONE * z
	_stage.position = vp / 2 - cam[0] * z + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 16.0
	# letterbox while in slow motion
	var lb: float = smoothstep(T_BULLET - 0.2, T_BULLET + 0.2, _t) * (1.0 - smoothstep(T_HIT + T_FREEZE, T_HIT + T_FREEZE + 0.3, _t))
	_bars[0].position = Vector2.ZERO
	_bars[0].size = Vector2(vp.x, vp.y * 0.11 * lb)
	_bars[1].size = Vector2(vp.x, vp.y * 0.11 * lb)
	_bars[1].position = Vector2(0, vp.y - _bars[1].size.y)
	_credit.modulate.a = clamp((_t - T_CREDIT) / 0.7, 0.0, 1.0)
	_flash.color.a = max(0.0, _flash.color.a - dt * (2.5 if slow < 1.0 else 5.0))
	_black.color.a = clamp((_t - T_FADE) / (T_END - T_FADE - 0.2), 0.0, 1.0)
	if _t >= T_END - 0.2 and _t - dt < T_END - 0.2:
		done.emit()          # the lobby takes over under the black
	if _t >= T_END:
		_finished = true
		queue_free()


func _shock_age() -> float:
	# time since the hit, crawling through the freeze and then running normally
	var since: float = _t - T_HIT
	if since < T_FREEZE:
		return since * 0.08
	return T_FREEZE * 0.08 + (since - T_FREEZE)


func _ring_points(l: Line2D, c: Vector2, rx: float, ry: float) -> void:
	var pts := PackedVector2Array()
	for k in 40:
		var a := TAU * k / 40.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	l.points = pts


## A ring of displaced air, flattened along the flight path.
func _ripple(pos: Vector2, dir: Vector2) -> void:
	var l := Line2D.new()
	l.closed = true
	l.width = 2.0
	l.material = _add_mat()
	var pts := PackedVector2Array()
	for k in 28:
		var a := TAU * k / 28.0
		pts.append(Vector2(cos(a) * 5.0, sin(a) * 9.0))
	l.points = pts
	l.position = pos
	l.rotation = dir.angle()
	_stage.add_child(l)
	_stage.move_child(l, _bullet.get_index())
	_rings.append({"line": l, "age": 0.0, "size": _logo.size.y / 420.0})


func _hit() -> void:
	_hit_done = true
	_holes[0][1] = _t
	var p := _uv_to_stage(_holes[0][0])
	_bullet.visible = false
	var tw := create_tween()
	tw.tween_property(_trail, "modulate:a", 0.0, 0.25).set_delay(T_FREEZE * 0.5)
	_flash.color = Color(1, 0.95, 0.85, 0.16)
	_shake = 0.9
	_shock.visible = true
	_sparks(p, Vector2.LEFT, 40, T_FREEZE)
	for i in 22:
		var spr := Sprite2D.new()
		spr.texture = PUFF
		spr.modulate = Color(0.78, 0.7, 0.6, 0.0)
		spr.visible = false
		_stage.add_child(spr)
		var a := randf() * TAU
		_dust.append({"sprite": spr, "origin": p, "vel": Vector2(cos(a), sin(a) * 0.7) * randf_range(60, 260) * (_logo.size.y / 420.0),
			"spin": randf_range(-1.5, 1.5), "size": randf_range(0.45, 0.95) * (_logo.size.y / 420.0), "delay": randf() * 0.06})
	Sfx.play("boom_small", 1.0, 0.55)
	Sfx.play("hit", 1.0, 0.6)
	Sfx.play("gun_heavy_1", 0.9, 0.7)


func _shoot(i: int) -> void:
	var h: Array = _holes[i]
	h[1] = _t
	var p := _uv_to_stage(h[0])
	var vp := _root.size
	var from := Vector2(-40.0 if randf() < 0.5 else vp.x + 40.0, randf_range(vp.y * 0.1, vp.y * 0.9))
	var tr := Line2D.new()
	tr.points = PackedVector2Array([from, p])
	tr.width = 3.0
	tr.default_color = Color(1, 0.85, 0.5, 0.9)
	tr.material = _add_mat()
	_stage.add_child(tr)
	create_tween().tween_property(tr, "modulate:a", 0.0, 0.09).finished.connect(tr.queue_free)
	_sparks(p, (from - p).normalized(), 26, 0.0)
	_shake = min(1.0, _shake + 0.45)
	_flash.color.a = max(_flash.color.a, 0.10)
	Sfx.play(["gun_heavy_1", "gun_heavy_2", "gun_heavy_3"][i % 3], 0.9, randf_range(0.92, 1.05))
	Sfx.play("hit", 0.8, randf_range(0.8, 1.1))


func _sparks(p: Vector2, dir: Vector2, n: int, hold: float) -> void:
	var sp := CPUParticles2D.new()
	sp.one_shot = true
	sp.explosiveness = 1.0
	sp.amount = n
	sp.lifetime = 0.6
	sp.direction = dir
	sp.spread = 75.0
	sp.initial_velocity_min = 180.0
	sp.initial_velocity_max = 560.0
	sp.gravity = Vector2(0, 900)
	sp.scale_amount_min = 1.5
	sp.scale_amount_max = 3.5
	sp.color_ramp = _ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.15, 1), Color(0.8, 0.2, 0.0, 0)])
	sp.material = _add_mat()
	sp.position = p
	_stage.add_child(sp)
	sp.emitting = true
	if hold > 0.0:   # frozen with the rest of the picture, then let go
		sp.speed_scale = 0.06
		get_tree().create_timer(hold).timeout.connect(func(): if is_instance_valid(sp): sp.speed_scale = 1.0)
	get_tree().create_timer(1.6).timeout.connect(sp.queue_free)
