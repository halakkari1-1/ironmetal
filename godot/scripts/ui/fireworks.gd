class_name Fireworks
extends Node2D
## Fireworks over the harbour skyline: a shell climbs on a fading trail, bursts into a sphere of coloured
## sparks (sometimes a second crackling ring), flashes, and fades. Drawn in the painting's own coordinates
## (a child of the backdrop), so it stays over the city whatever the screen shape.

var active := false
var _t := 1.0
var _shells: Array = []     # {pos, vel, color, fuse, trail}
var _dot: Texture2D

const COLORS := [Color(1.0, 0.55, 0.15), Color(0.35, 0.6, 1.0), Color(0.8, 0.35, 1.0), Color(1.0, 0.85, 0.35), Color(1.0, 0.95, 0.9), Color(0.3, 1.0, 0.7), Color(1.0, 0.3, 0.45)]


func _ready() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a: float = clamp(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(img)


func _size() -> Vector2:
	return (get_parent() as Control).size


func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _process(dt: float) -> void:
	if not active or not is_visible_in_tree():
		return
	_t -= dt
	if _t <= 0:
		_t = randf_range(0.6, 1.8)
		_launch()
		if randf() < 0.25:
			get_tree().create_timer(0.18).timeout.connect(_launch)
	var s := _size()
	for sh in _shells.duplicate():
		sh.fuse -= dt
		sh.vel.y += 0.09 * s.y * dt          # gravity, in screen terms
		sh.pos += sh.vel * dt
		sh.trail.position = sh.pos
		if sh.fuse <= 0:
			_burst(sh)
			sh.trail.emitting = false
			get_tree().create_timer(1.2).timeout.connect(sh.trail.queue_free)
			_shells.erase(sh)


func _launch() -> void:
	var s := _size()
	var start := Vector2(randf_range(0.36, 0.97) * s.x, 0.47 * s.y)
	var top := randf_range(0.09, 0.3) * s.y
	var fuse := randf_range(0.9, 1.4)
	var vy := -(start.y - top) / fuse - 0.045 * s.y * fuse
	var col: Color = COLORS.pick_random()
	var tr := CPUParticles2D.new()
	tr.amount = 30
	tr.lifetime = 0.5
	tr.texture = _dot
	tr.scale_amount_min = 0.12 * s.y / 720.0
	tr.scale_amount_max = 0.22 * s.y / 720.0
	tr.gravity = Vector2(0, 30)
	tr.initial_velocity_min = 0
	tr.initial_velocity_max = 8
	tr.color_ramp = _ramp([Color(1, 0.9, 0.7, 0.9), Color(col, 0.0)])
	tr.material = _add_mat()
	tr.position = start
	add_child(tr)
	tr.emitting = true
	_shells.append({"pos": start, "vel": Vector2(randf_range(-0.02, 0.02) * s.x, vy), "color": col, "fuse": fuse, "trail": tr})


func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols)
	var offs := PackedFloat32Array()
	for i in cols.size():
		offs.append(float(i) / (cols.size() - 1))
	g.offsets = offs
	return g


func _burst(sh: Dictionary) -> void:
	var s := _size()
	var k := s.y / 720.0
	var col: Color = sh.color
	var big := randf() < 0.35
	for layer in (2 if big else 1):
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 90 if layer == 0 else 50
		p.lifetime = randf_range(1.4, 2.0)
		p.texture = _dot
		p.direction = Vector2.UP
		p.spread = 180.0
		p.initial_velocity_min = (110.0 if layer == 0 else 60.0) * k * (1.3 if big else 1.0)
		p.initial_velocity_max = (150.0 if layer == 0 else 80.0) * k * (1.3 if big else 1.0)
		p.damping_min = 40.0 * k
		p.damping_max = 70.0 * k
		p.gravity = Vector2(0, 40.0 * k)
		p.scale_amount_min = 0.16 * k
		p.scale_amount_max = 0.3 * k
		var c2: Color = col if layer == 0 else (COLORS.pick_random() as Color)
		p.color_ramp = _ramp([Color(1, 1, 1, 1), Color(c2, 1.0), Color(c2.darkened(0.3), 0.7), Color(c2, 0.0)])
		p.material = _add_mat()
		p.position = sh.pos
		add_child(p)
		p.emitting = true
		get_tree().create_timer(2.6).timeout.connect(p.queue_free)
	var flash := Sprite2D.new()       # the bang lights up the sky around it
	flash.texture = _dot
	flash.modulate = Color(col.lightened(0.4), 0.85)
	flash.material = _add_mat()
	flash.position = sh.pos
	flash.scale = Vector2.ONE * 6.0 * k
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.45)
	tw.parallel().tween_property(flash, "scale", Vector2.ONE * 9.0 * k, 0.45)
	tw.finished.connect(flash.queue_free)
	Sfx.play("boom_small", 0.18, randf_range(1.5, 1.9))
