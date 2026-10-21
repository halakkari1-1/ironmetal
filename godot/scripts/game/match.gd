class_name Match
extends Node3D
## A single match: cars, driving, weapons, specials, AI, pickups, airdrops, map events, and win/lose.
## Modes: "deathmatch" (last car running, or most kills when time runs out) and "survival" (endless waves).

signal finished(result: Dictionary)

const LIVES := 3
const TIME_LIMIT := 300.0
const STREAKS := {2: ["DOUBLE WRECK", 40], 3: ["TRIPLE WRECK", 80], 4: ["RAMPAGE", 150], 5: ["UNSTOPPABLE", 220]}
const BULLET_SPEED := 120.0
const MAX_BULLETS := 160

var hud  # the HUD node (scripts/ui/hud.gd)
var arena: Arena
var fx: FX
var camera: Camera3D
var map: Dictionary
var mode := "deathmatch"
var diff: Dictionary
var cars: Array[Car] = []
var player: Car
var spawns: Array = []
var bullets: Array = []      # {x, y, z, dx, dz, life, owner, dmg}
var rockets: Array = []      # {node, trail, x, y, z, dir, speed, life, owner, kind, dmg, radius, homing, warned}
var pickups: Array = []
var drops: Array = []
var zones: Array = []
var strikes: Array = []
var wrecks: Array = []
var time := 0.0
var state := "countdown"
var countdown := 3.5
var shake := 0.0
var over := false
var running := false
var stats := {"kills": 0, "rocket_kills": 0, "barrels": 0, "airdrops": 0, "streak_max": 0, "bounty": 0, "wave": 0, "first_blood": false, "bonus": []}
var streak := 0
var last_kill_t := -99.0
var drop_t := 20.0
var event_t := 25.0
var storm := 0.0
var wave := 0
var break_t := 0.0
var end_t := 0.0
var result := ""
var cam_mode := "near"
var _cam_mode_t := 0.0
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _later: Array = []       # [time, callable]
var _last_incoming := -9.0
var _poison_msg := 0.0
var _scenes := {}            # car id -> PackedScene
var _prop_scenes := {}
var _bullet_mm: MultiMeshInstance3D
var _rocket_pool: Array = []
var _zone_pool := {"toxic": [], "fire": []}
var _strike_pool: Array = []
var _sand: GPUParticles3D
var _stack_fx: Array = []


# ---------- setup ----------

## Loads everything a match needs. Call before start(); the menu shows a loading screen meanwhile.
func preload_assets(car_ids: Array) -> void:
	for id in car_ids:
		if not _scenes.has(id):
			_scenes[id] = load("res://assets/cars/%s.glb" % id)
	for p in ["crown", "medkit", "ammo", "dropcrate", "parachute"]:
		_prop_scenes[p] = load("res://assets/props/%s.glb" % p)


func start(opts: Dictionary) -> void:
	map = opts.map
	mode = opts.get("mode", "deathmatch")
	diff = opts.diff.duplicate()
	if mode == "survival":
		diff.focus = 0.45
		diff.enemies = 0
	cam_mode = Save.state.get("camera", "near")
	arena = Arena.new()
	add_child(arena)
	arena.build(map)
	fx = FX.new()
	add_child(fx)
	fx.setup()
	camera = Camera3D.new()
	camera.fov = 62
	camera.near = 0.3
	camera.far = 900.0
	add_child(camera)
	camera.make_current()
	var floor := GPUParticlesCollisionBox3D.new()
	floor.size = Vector3(map.size * 2, 2, map.size * 2)
	floor.position.y = -1.0
	add_child(floor)
	_build_bullets()
	for i in 24:
		_rocket_pool.append(_make_rocket())
	for i in 4:
		_strike_pool.append(_make_strike())
	for k in ["toxic", "fire"]:
		for i in 4:
			var e := fx.toxic_emitter(9.0) if k == "toxic" else fx.fire_zone_emitter(5.0)
			_zone_pool[k].append(e)
	for st in arena.stacks:
		var e := fx.tower_smoke_emitter(st.big)
		e.global_position = st.pos
		e.emitting = true
		_stack_fx.append(e)
	for b in arena.blazes:
		var e := fx.flame_emitter(3.2, 7)
		e.global_position = b
		e.emitting = true
		_stack_fx.append(e)
	if map.event == "sandstorm":
		_sand = fx.sand_emitter()

	spawns = arena.spawns.duplicate()
	spawns.shuffle()
	player = _add_car(opts.car, opts.upgrades, spawns[0], true)
	if mode == "deathmatch":
		var pool := Data.CARS.filter(func(c): return c.price <= diff.max_price and c.id != opts.car.id)
		pool.shuffle()
		for i in diff.enemies:
			_add_car(pool[i % pool.size()], _lvl(diff.level), spawns[i + 1], false)
	_build_pickups()
	drop_t = randf_range(18, 26)
	event_t = randf_range(22, 30)
	_snap_camera()
	Sfx.engine_start(opts.car.id)
	Sfx.music("match")
	running = true
	hud.on_start(self)


func _lvl(l: int) -> Dictionary:
	return {"gun": l, "rocket": l, "armor": l, "speed": l, "special": l}


func _add_car(d: Dictionary, upgrades: Dictionary, spawn: Dictionary, is_player: bool, hp_mul := 1.0) -> Car:
	if not _scenes.has(d.id):
		_scenes[d.id] = load("res://assets/cars/%s.glb" % d.id)
	var c := Car.new()
	add_child(c)
	c.setup(d, _scenes[d.id])
	c.attach_fx(fx)
	c.is_player = is_player
	c.stats = Data.car_stats(d, upgrades)
	if not is_player:
		c.stats.hp = round(c.stats.hp * diff.hp * hp_mul)
	c.hp = c.stats.hp
	c.max_hp = c.stats.hp
	c.x = spawn.x
	c.z = spawn.z
	c.heading = spawn.heading
	c.lives = 1 if (mode == "survival" and not is_player) else LIVES
	c.dmg_mul = 1.0 if is_player else diff.dmg
	if not is_player:
		c.ai = {"target": null, "retarget": 0.0, "stuck": 0.0, "reverse_t": 0.0, "rocket_t": randf_range(2, 4),
			"strafe": 1.0 if randf() < 0.5 else -1.0, "special_t": randf_range(3, 6)}
	c.position = Vector3(c.x, 0, c.z)
	c.rotation.y = c.heading
	cars.append(c)
	return c


func _build_bullets() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 2.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	box.material = m
	mm.mesh = box
	mm.instance_count = MAX_BULLETS
	mm.visible_instance_count = 0
	_bullet_mm = MultiMeshInstance3D.new()
	_bullet_mm.multimesh = mm
	_bullet_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bullet_mm.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 60, 400))
	add_child(_bullet_mm)


func _make_rocket() -> Dictionary:
	var node := Node3D.new()
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.16
	cyl.height = 1.1
	cyl.radial_segments = 8
	body.mesh = cyl
	body.rotation.x = PI / 2
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("d9d2c4")
	bm.metallic = 0.5
	body.material_override = bm
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 0.4
	cone.radial_segments = 8
	tip.mesh = cone
	tip.rotation.x = PI / 2
	tip.position.z = 0.7
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color("ff3d1f")
	tm.emission_enabled = true
	tm.emission = Color("ff2000")
	tm.emission_energy_multiplier = 2.0
	tip.material_override = tm
	node.add_child(body)
	node.add_child(tip)
	node.visible = false
	add_child(node)
	var trail := fx.trail_emitter(false)
	return {"node": node, "body": body, "tip": tip, "bm": bm, "tm": tm, "trail": trail, "busy": false}


func _make_strike() -> Dictionary:
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.92
	t.outer_radius = 1.0
	t.rings = 48
	t.ring_segments = 4
	ring.mesh = t
	ring.scale = Vector3(1, 0.05, 1)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(1, 0.16, 0.1, 0.7)
	ring.material_override = rm
	var fill := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 40
	fill.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(1, 0.16, 0.1, 0.14)
	fill.material_override = fm
	for n in [ring, fill]:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.visible = false
		add_child(n)
	return {"ring": ring, "fill": fill, "rm": rm, "busy": false}


## A copy of a prop model scaled so its longest side is `size`, centred on its pivot (or standing on it).
func prop_model(id: String, size: float, stand := false) -> Node3D:
	var inst: Node3D = _prop_scenes[id].instantiate()
	var box := Car.new()._aabb(inst)
	var k: float = size / max(box.size.x, box.size.y, box.size.z)
	inst.scale = Vector3.ONE * k
	var c := box.get_center()
	inst.position = Vector3(-c.x * k, (-box.position.y if stand else -c.y) * k, -c.z * k)
	var g := Node3D.new()
	g.add_child(inst)
	g.set_meta("h", box.size.y * k)
	return g


func _build_pickups() -> void:
	for s in arena.pickup_spots:
		_nudge_clear(s, 3)
		var g := prop_model("medkit" if s.type == "health" else "ammo", 2.1)
		g.position = Vector3(s.x, 1.4, s.z)
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 1.52
		t.outer_radius = 1.68
		ring.mesh = t
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color("5dff7a") if s.type == "health" else Color("ffb347")
		ring.material_override = m
		ring.position.y = -1.2
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(ring)
		add_child(g)
		pickups.append({"x": s.x, "z": s.z, "type": s.type, "node": g, "respawn": 0.0})


func _nudge_clear(s: Dictionary, pad: float) -> Dictionary:
	for o in arena.obstacles:
		var d := Vector2(s.x - o.x, s.z - o.z).length()
		var r: float = o.get("r", Vector2(o.get("hw", 0), o.get("hd", 0)).length()) + pad
		if d < r:
			var k: float = r / max(d, 0.1)
			s.x = o.x + (s.x - o.x) * k
			s.z = o.z + (s.z - o.z) * k
	var h := arena.half - 5
	s.x = clamp(s.x, -h, h)
	s.z = clamp(s.z, -h, h)
	return s


func later(delay: float, fn: Callable) -> void:
	_later.append([time + delay, fn])


# ---------- input ----------

func set_input(t: float, s: float, f: bool) -> void:
	if player:
		player.throttle = t
		player.steer = s
		player.firing = f


func player_rocket() -> void:
	if state == "fight" and player.alive:
		fire_rocket(player)


func player_special() -> void:
	if state == "fight" and player.alive:
		use_special(player)


func cycle_camera() -> String:
	var order := ["near", "far", "hood"]
	cam_mode = order[(order.find(cam_mode) + 1) % order.size()]
	_cam_mode_t = 0.4
	Save.state.camera = cam_mode
	Save.write()
	return cam_mode


# ---------- main loop ----------

func _process(dt_real: float) -> void:
	if not running:
		return
	var dt: float = min(dt_real, 0.05)
	time += dt
	Quality.sample(dt_real)
	if not _later.is_empty():
		var due := _later.filter(func(e): return e[0] <= time)
		_later = _later.filter(func(e): return e[0] > time)
		for e in due:
			e[1].call()
	if state == "countdown":
		var before := ceili(countdown)
		countdown -= dt
		var now := ceili(countdown)
		if now != before and now >= 0:
			hud.countdown(str(now) if now > 0 else I18n.t("FIGHT"))
			Sfx.play("count_go" if now == 0 else "count")
		if countdown <= 0:
			state = "fight"
			if mode == "survival":
				_next_wave()
	var active := state == "fight" or state == "ending"
	for c in cars:
		if not c.alive:
			_update_wreck(c, dt)
			c.update_fx(map.id == "dustbowl")
			if c.respawn_t > 0 and state == "fight":
				c.respawn_t -= dt
				if c.respawn_t <= 0:
					_respawn(c)
			continue
		if c.invuln > 0:
			c.invuln -= dt
			c.visible = c.invuln <= 0 or int(c.invuln * 10) % 2 == 0
		if active and not c.is_player:
			_think(c, dt)
		if not active:
			c.throttle = 0
			c.steer = 0
			c.firing = false
		_drive(c, dt)
		_weapons(c, dt)
		c.update_fx(map.id == "dustbowl")
		if c.crown:
			c.crown.rotation.y += dt * 2
	_collide_cars()
	wrecks = wrecks.filter(func(w):
		w.t += dt
		if w.t > 7:
			w.node.position.y -= dt * 0.8
		if w.t > 10:
			w.node.queue_free()
			return false
		return true)
	_update_bullets(dt)
	_update_rockets(dt)
	_update_pickups(dt)
	_update_zones(dt)
	_update_strikes(dt)
	if state == "fight":
		_update_drops(dt)
		_update_events(dt)
		if mode == "survival":
			_update_waves(dt)
	_update_camera(dt)
	Sfx.engine_set(abs(player.throttle), clamp(abs(player.speed) / player.stats.max_speed, 0.0, 1.0))
	if state == "fight":
		_check_end()
	if state == "ending":
		end_t -= dt
		if end_t <= 0:
			_finish()
	hud.update_hud(self, dt)


# ---------- survival waves ----------

func _next_wave() -> void:
	wave += 1
	stats.wave = wave
	var n: int = min(1 + int(wave * 0.7), 7)
	var tiers := [1500, 2500, 3500, 4500, 99999]
	var cap: int = tiers[min(tiers.size() - 1, (wave - 1) / 2)]
	var pool := Data.CARS.filter(func(c): return c.price <= cap)
	var lvl: int = min(5, (wave - 1) / 2)
	diff.dmg = min(1.05, 0.38 + wave * 0.055)
	var far := spawns.duplicate()
	far.sort_custom(func(a, b): return Vector2(a.x - player.x, a.z - player.z).length() > Vector2(b.x - player.x, b.z - player.z).length())
	cars = cars.filter(func(c):
		if not c.alive and not c.is_player:
			c.queue_free()
			return false
		return true)
	for i in n:
		var s: Dictionary = far[i % far.size()]
		var c := _add_car(pool.pick_random(), _lvl(lvl), {"x": s.x + randf_range(-3, 3), "z": s.z + randf_range(-3, 3), "heading": s.heading}, false, 0.68 + wave * 0.05)
		c.dmg_mul = diff.dmg
	if wave % 3 == 0:
		var alive := cars.filter(func(c): return c.alive and not c.is_player)
		if alive.size():
			set_bounty(alive.pick_random(), false)
	hud.ensure_enemy_bars(self)
	hud.announce(I18n.t("WAVE {n}", {"n": wave}), I18n.t("{n} hostiles inbound", {"n": n}), "red")
	Sfx.play("alarm")


func _update_waves(dt: float) -> void:
	var left := cars.filter(func(c): return not c.is_player and _in_play(c)).size()
	if left > 0 or not player.alive:
		return
	if break_t <= 0:
		break_t = 5
		player.hp = min(player.max_hp, player.hp + player.max_hp * 0.35)
		player.rockets = min(12, player.rockets + 4)
		fx.heal(Vector3(player.x, 0, player.z))
		Sfx.play("pickup")
		var pts := 40 + wave * 15
		stats.bonus.append({"label": "Wave {n} cleared", "n": wave, "pts": pts})
		hud.announce(I18n.t("WAVE {n} CLEARED", {"n": wave}), I18n.t("+{n} · armor patched", {"n": pts}), "green")
	break_t -= dt
	if break_t <= 0:
		_next_wave()


func _in_play(c: Car) -> bool:
	return c.alive or c.respawn_t > 0


# ---------- driving ----------

func _drive(c: Car, dt: float) -> void:
	var s := c.stats
	var nitro := c.special_on == "nitro"
	var ram := c.special_on == "ram"
	var dash := c.special_on == "dash"
	var slow := 0.5 if c.slow_t > 0 else 1.0
	var max_s: float = s.max_speed * (1.75 if nitro else 1.0) * (2.1 if ram else 1.0) * (2.0 if dash else 1.0) * slow
	var acc: float = s.accel * (2.0 if nitro else 1.0) * (4.0 if dash else 1.0) * slow
	if c.skid_t > 0:
		c.throttle = 0
		c.steer = 0
	if ram:
		c.speed = min(max_s, c.speed + acc * 4 * dt)
	elif c.throttle > 0.05:
		c.speed += acc * c.throttle * dt * (2.0 if c.speed < 0 else 1.0)
	elif c.throttle < -0.05:
		c.speed += acc * c.throttle * dt * (1.8 if c.speed > 0 else 0.7)
	else:
		c.speed -= c.speed * min(1.0, 2.2 * dt)  # let go of the stick: the car settles quickly
	c.speed = clamp(c.speed, -s.max_speed * 0.45, max_s)
	if not ram and not dash and c.speed > s.max_speed * (1.75 if nitro else 1.0) * slow:
		c.speed -= (c.speed - s.max_speed * slow) * 2 * dt
	# steering eases in and out instead of snapping, which keeps the car stable on a touch stick
	c.steer_s += (c.steer - c.steer_s) * min(1.0, dt * (20.0 if c.is_player else 12.0))
	var turn_scale: float = clamp(c.speed / 4.0, -1.0, 1.0) * (1.0 - 0.3 * clamp(abs(c.speed) / max_s, 0.0, 1.0))
	c.heading = wrapf(c.heading + c.steer_s * s.turn * 1.15 * turn_scale * dt + (c.skid_spin * min(1.0, c.skid_t) * dt if c.skid_t > 0 else 0.0), -PI, PI)
	var f := c.forward()
	c.x += (f.x * c.speed + c.kx) * dt
	c.z += (f.z * c.speed + c.kz) * dt
	var kd := exp(-4 * dt)
	c.kx *= kd
	c.kz *= kd
	_collide_world(c)
	c.position = Vector3(c.x, 0, c.z)
	c.rotation = Vector3(lerp(c.rotation.x, -clamp(c.throttle * 0.04 - (0.02 if c.speed < 0 else 0.0), -0.05, 0.05), 0.1), c.heading,
		lerp(c.rotation.z, c.steer_s * clamp(c.speed / 30.0, -1.0, 1.0) * 0.06, 0.1))
	if nitro or ram:
		pass


## The body is three circles along its length; on contact only the motion into the obstacle is lost,
## so the car slides along walls instead of sticking.
func _collide_world(c: Car) -> void:
	var f := c.forward()
	var r := c.rad
	var L := c.half_len
	var nx := 0.0
	var nz := 0.0
	var hit: Dictionary = {}
	var any := false
	var lim := arena.half - 1.0
	for off in [L, 0.0, -L]:
		var cx: float = c.x + f.x * off
		var cz: float = c.z + f.z * off
		if cx > lim - r:
			c.x -= cx - (lim - r); nx -= 1; any = true
		elif cx < -lim + r:
			c.x += -lim + r - cx; nx += 1; any = true
		if cz > lim - r:
			c.z -= cz - (lim - r); nz -= 1; any = true
		elif cz < -lim + r:
			c.z += -lim + r - cz; nz += 1; any = true
	if c.y <= 2:
		for o in arena.obstacles:
			if o.get("dead", false):
				continue
			var bound: float = o.get("r", Vector2(o.get("hw", 0), o.get("hd", 0)).length()) + r + L
			if abs(c.x - o.x) > bound or abs(c.z - o.z) > bound:
				continue
			for off in [L, 0.0, -L]:
				var push := _push_out(o, c.x + f.x * off, c.z + f.z * off, r)
				if push == Vector2.ZERO:
					continue
				c.x += push.x
				c.z += push.y
				nx += push.x
				nz += push.y
				any = true
				hit = o
	if not any:
		return
	var nl := Vector2(nx, nz).length()
	if nl < 0.0001:
		return
	nx /= nl
	nz /= nl
	var into: float = -(f.x * nx + f.z * nz) * sign(c.speed if c.speed != 0 else 1.0)
	var impact: float = abs(c.speed) * max(0.0, into)
	if into > 0:
		c.speed *= 1 - 0.85 * into
	var kn := c.kx * nx + c.kz * nz
	if kn < 0:
		c.kx -= kn * nx * 1.4
		c.kz -= kn * nz * 1.4
	if impact > 12:
		_bump(c)
		if c.alive:
			fx.spark(Vector3(c.x - nx * r, 1, c.z - nz * r), true)
		if hit.get("barrel", false):
			damage_obstacle(hit, impact, c)


static func _push_out(o: Dictionary, x: float, z: float, r: float) -> Vector2:
	if o.kind == "circle":
		var d := Vector2(x - o.x, z - o.z)
		var dl := d.length()
		if dl >= o.r + r:
			return Vector2.ZERO
		return d * ((o.r + r - dl) / max(dl, 0.01))
	var rot: float = o.get("rot", 0.0)
	var cs := cos(rot)
	var sn := sin(rot)
	var dx: float = x - o.x
	var dz: float = z - o.z
	var lx := dx * cs - dz * sn
	var lz := dx * sn + dz * cs
	var px: float = clamp(lx, -o.hw, o.hw)
	var pz: float = clamp(lz, -o.hd, o.hd)
	var ex := lx - px
	var ez := lz - pz
	var d := Vector2(ex, ez).length()
	var mx := 0.0
	var mz := 0.0
	if d >= r:
		return Vector2.ZERO
	if d < 0.0001:  # centre inside the box: leave by the shallowest side
		var ox: float = o.hw - abs(lx)
		var oz: float = o.hd - abs(lz)
		if ox < oz:
			mx = sign(lx if lx != 0 else 1.0) * (ox + r)
		else:
			mz = sign(lz if lz != 0 else 1.0) * (oz + r)
	else:
		var k := (r - d) / d
		mx = ex * k
		mz = ez * k
	return Vector2(mx * cs + mz * sn, -mx * sn + mz * cs)


static func inside_obstacle(o: Dictionary, x: float, z: float) -> bool:
	if o.kind == "circle":
		return Vector2(x - o.x, z - o.z).length() < o.r
	var rot: float = o.get("rot", 0.0)
	var cs := cos(rot)
	var sn := sin(rot)
	var dx: float = x - o.x
	var dz: float = z - o.z
	return abs(dx * cs - dz * sn) < o.hw and abs(dx * sn + dz * cs) < o.hd


func _bump(c: Car) -> void:
	if c.is_player and abs(c.speed) > 6:
		shake = max(shake, 0.25)
		Sfx.play("crunch")


func _collide_cars() -> void:
	for i in cars.size():
		for j in range(i + 1, cars.size()):
			var a := cars[i]
			var b := cars[j]
			if not a.alive and not b.alive:
				continue
			if a.y > 2 or b.y > 2:
				continue
			var dx := b.x - a.x
			var dz := b.z - a.z
			var d := Vector2(dx, dz).length()
			var mn := (a.rad + b.rad) * 1.45
			if d >= mn or d < 0.001:
				continue
			var nx := dx / d
			var nz := dz / d
			var push := mn - d
			var ma: float = a.stats.mass if a.alive else 50.0
			var mb: float = b.stats.mass if b.alive else 50.0
			var tot := ma + mb
			a.x -= nx * push * (mb / tot)
			a.z -= nz * push * (mb / tot)
			b.x += nx * push * (ma / tot)
			b.z += nz * push * (ma / tot)
			var rel: float = abs(a.speed) + abs(b.speed)
			for pair in [[a, b, 1.0], [b, a, -1.0]]:
				var p: Car = pair[0]
				var q: Car = pair[1]
				if not p.alive or not q.alive:
					continue
				if p.special_on == "ram" and not p.rammed.has(q):
					p.rammed[q] = true
					damage(q, 48 * p.stats.special_power * p.dmg_mul, p, false, "ram")
					q.kx += nx * pair[2] * 30
					q.kz += nz * pair[2] * 30
					fx.explosion(Vector3((a.x + b.x) / 2, 0, (a.z + b.z) / 2), 0.45)
					Sfx.explosion(q.position, 0.5)
					shake = max(shake, 0.5)
			if rel > 22:
				if a.alive:
					damage(a, rel * 0.08, b, false, "crash")
				if b.alive:
					damage(b, rel * 0.08, a, false, "crash")
				fx.spark(Vector3((a.x + b.x) / 2, 1.2, (a.z + b.z) / 2), true)
				if a.is_player or b.is_player:
					Sfx.play("crunch")
					shake = max(shake, 0.35)
			a.speed *= 0.7
			b.speed *= 0.7


# ---------- weapons ----------

func _weapons(c: Car, dt: float) -> void:
	var was_cooling := c.special_cd > 0
	c.gun_cd -= dt
	c.rocket_cd -= dt
	c.special_cd -= dt
	if c.is_player and was_cooling and c.special_cd <= 0 and state == "fight":
		Sfx.play("ready", 0.8)
	c.slow_t = max(0.0, c.slow_t - dt)
	c.jam_t = max(0.0, c.jam_t - dt)
	c.skid_t = max(0.0, c.skid_t - dt)
	c.hide_t = max(0.0, c.hide_t - dt)
	c.spin_t = max(0.0, c.spin_t - dt)
	if c.special_on != "":
		c.special_t -= dt
		if c.special_on == "smoke":
			c.trail_fx.global_position = c.position - c.forward() * 5 + Vector3.UP
		if c.special_on == "shield" and c.bubble:
			(c.bubble.material_override as StandardMaterial3D).albedo_color.a = 0.18 + 0.08 * sin(time * 12)
		if c.special_t <= 0:
			if c.bubble:
				c.bubble.visible = false
			if c.trail_fx:
				c.trail_fx.emitting = false
			if c.is_player:
				Sfx.play("ability_end", 0.7)
			c.special_on = ""
			c.rammed.clear()
	if c.jam_t > 0 and randf() < dt * 6:
		fx.zap(c.position + Vector3.UP * 2.2)
	if c.model:
		c.model.rotation.y = PI / 2 + ((1 - c.spin_t / 0.55) * TAU if c.spin_t > 0 else 0.0)  # Rex's tail whip spin
	if c.firing and c.gun_cd <= 0 and state == "fight" and c.jam_t <= 0:
		_fire_gun(c)
		c.gun_cd = 0.09


func aim_at(c: Car, rng: float, cone: float) -> Car:
	var best: Car = null
	var best_score := INF
	for o in cars:
		if o == c or not o.alive or o.hide_t > 0:
			continue
		var dx := o.x - c.x
		var dz := o.z - c.z
		var d := Vector2(dx, dz).length()
		if d > rng:
			continue
		var ang: float = abs(wrapf(atan2(dx, dz) - c.heading, -PI, PI))
		if ang > cone:
			continue
		var score := d * (1 + ang * 2)
		if score < best_score:
			best_score = score
			best = o
	return best


func _fire_gun(c: Car) -> void:
	var local: Vector3 = c.muzzles[c.muzzle_i % c.muzzles.size()]
	c.muzzle_i += 1
	var m := c.world_point(local)
	var dir := c.heading
	var t: Car = aim_at(c, 55, 0.32) if c.is_player else c.ai.target
	if t and t.alive:
		var dist := Vector2(t.x - c.x, t.z - c.z).length()
		var lead := dist / BULLET_SPEED
		var tx := t.x + sin(t.heading) * t.speed * lead
		var tz := t.z + cos(t.heading) * t.speed * lead
		var want := atan2(tx - m.x, tz - m.z)
		if abs(wrapf(want - c.heading, -PI, PI)) < 0.45:
			dir = want
	var spread: float = 0.03 if c.is_player else 0.03 + (1 - diff.accuracy) * 0.16
	dir += randf_range(-spread, spread)
	if bullets.size() < MAX_BULLETS:
		bullets.append({"x": m.x, "y": m.y, "z": m.z, "dx": sin(dir), "dz": cos(dir), "life": 0.5, "owner": c, "dmg": c.stats.gun_dmg * c.dmg_mul})
	c.show_flash(local)
	if c.is_player and randf() < 0.5:
		fx.light(m + Vector3.UP * 0.3, 1.2, Color(1, 0.7, 0.4))
	Sfx.gun(m, float(c.data.sound.gun), 1.0 if c.is_player else 0.75)


func fire_rocket(c: Car, opts := {}) -> void:
	if not c.power.is_empty() and not opts.get("free", false):
		_fire_power(c)
		return
	if not opts.get("free", false):
		if c.rocket_cd > 0 or c.rockets <= 0:
			if c.is_player and c.rockets <= 0:
				Sfx.play("denied")
			return
		c.rockets -= 1
		c.rocket_cd = 0.55
	var m := c.world_point(c.rocket_muzzle)
	var dir: float = c.heading + opts.get("offset", 0.0)
	if not opts.has("offset"):
		var t: Car = aim_at(c, 70, 0.4) if c.is_player else c.ai.target
		if t and t.alive:
			var want := atan2(t.x - m.x, t.z - m.z)
			if abs(wrapf(want - c.heading, -PI, PI)) < 0.5:
				dir = want
		if not c.is_player:
			dir += randf_range(-1, 1) * (1 - diff.accuracy) * 0.2
	var kind: String = opts.get("kind", "rocket")
	var big := kind == "nuke" or kind == "shell"
	var r: Dictionary = {}
	for item in _rocket_pool:
		if not item.busy:
			r = item
			break
	if r.is_empty():
		return
	r.busy = true
	var sc := 2.5 if big else 1.0
	r.node.scale = Vector3.ONE * sc
	r.bm.albedo_color = Color("2a0c0a") if kind == "shell" else (Color("3d4a2a") if big else (Color("8a3a12") if kind == "napalm" else Color("d9d2c4")))
	r.tm.albedo_color = Color("ff2a1a") if kind == "shell" else (Color("ffd23a") if big else Color("ff3d1f"))
	r.node.visible = true
	r.trail.emitting = true
	r.merge({"x": m.x, "y": max(1.2, m.y), "z": m.z, "dir": dir, "speed": opts.get("speed", 34.0 if big else 52.0), "life": 3.5 if big else 2.4,
		"owner": c, "kind": kind, "dmg": opts.get("dmg", c.stats.rocket_dmg * c.dmg_mul * opts.get("dmg_mul", 1.0)),
		"radius": opts.get("radius", c.stats.rocket_radius), "homing": opts.get("homing", null), "warned": false, "hit_sound": false}, true)
	rockets.append(r)
	Sfx.rocket(m, big, 1.0 if c.is_player else 0.8)


func _fire_power(c: Car) -> void:
	if c.rocket_cd > 0:
		return
	var p := c.power
	c.rocket_cd = 0.7 if p.type == "railgun" else 0.6
	if p.type == "railgun":
		_railgun(c)
	elif p.type == "napalm":
		fire_rocket(c, {"free": true, "kind": "napalm", "dmg_mul": 0.8})
	else:
		fire_rocket(c, {"free": true, "kind": "nuke", "dmg": 170.0 * (1.0 if c.is_player else c.dmg_mul), "radius": 18.0})
	p.ammo -= 1
	if p.ammo <= 0:
		c.power = {}
		if c.is_player:
			hud.toast(I18n.t("{p} EMPTY", {"p": I18n.t(Data.POWERS[p.type].name).to_upper()}))


func _railgun(c: Car) -> void:
	var m := c.world_point(c.rocket_muzzle)
	var t: Car = aim_at(c, 95, 0.35) if c.is_player else c.ai.target
	var dir := c.heading
	if t and t.alive:
		var want := atan2(t.x - m.x, t.z - m.z)
		if abs(wrapf(want - c.heading, -PI, PI)) < 0.5:
			dir = want
	var dx := sin(dir)
	var dz := cos(dir)
	var end := 95.0
	var hit: Car = null
	var s := 2.0
	while s < 95:
		var px := m.x + dx * s
		var pz := m.z + dz * s
		if abs(px) > arena.half or abs(pz) > arena.half:
			end = s
			break
		var o := hit_obstacle(px, 1.5, pz)
		if not o.is_empty():
			end = s
			if o.get("barrel", false):
				damage_obstacle(o, 99, c)
			break
		for q in cars:
			if q != c and q.alive and Vector2(q.x - px, q.z - pz).length() < q.hit_r:
				hit = q
				break
		if hit:
			end = s
			break
		s += 0.8
	var e := Vector3(m.x + dx * end, 1.5, m.z + dz * end)
	fx.line(m, e, 0.35, Color(0.4, 0.75, 1.6), 0.22, 1.0)
	fx.light(e + Vector3.UP * 0.5, 4.0, Color(0.4, 0.7, 1))
	fx.spark(e, true)
	if hit:
		damage(hit, 68.0 * (1.0 if c.is_player else c.dmg_mul), c, false, "railgun")
		hit.kx += dx * 18
		hit.kz += dz * 18
	Sfx.play_at("railgun", m)
	if c.is_player:
		shake = max(shake, 0.3)


func _near(c: Car, r: float, cone := PI) -> Array:
	return cars.filter(func(o):
		if o == c or not o.alive:
			return false
		var d := Vector2(o.x - c.x, o.z - c.z).length()
		return d < r + o.hit_r and abs(wrapf(atan2(o.x - c.x, o.z - c.z) - c.heading, -PI, PI)) <= cone)


func use_special(c: Car) -> bool:
	if c.special_cd > 0 or c.special_on != "" or c.skid_t > 0:
		if c.is_player:
			Sfx.play("denied")
		return false
	var spec: Dictionary = c.data.special
	var pw: float = c.stats.special_power
	c.special_cd = c.stats.special_cooldown
	var f := c.forward()
	var dur: float = spec.get("duration", 1.0)
	var rad: float = spec.get("radius", 10.0)
	Sfx.play_at("ab_" + str(c.data.sound.ability), c.position, 1.0 if c.is_player else 0.8)
	match spec.id:
		"smoke":  # Ghost: smoke cover, enemies lose track, short speed burst
			c.special_on = "smoke"
			c.special_t = dur
			c.hide_t = dur * min(1.4, pw)
			c.speed = max(c.speed, c.stats.max_speed * 1.25)
			fx.smoke_burst(c.position - f * 3)
			_ensure_trail(c, "smoke")
			for o in cars:
				if not o.ai.is_empty() and o.ai.target == c:
					o.ai.target = null
					o.ai.retarget = c.hide_t
		"dash":  # Venom: double speed, half damage taken
			c.special_on = "dash"
			c.special_t = dur * min(1.4, pw)
			c.speed = max(c.speed, c.stats.max_speed * 1.6)
			_ensure_trail(c, "dash")
		"toxic":  # Toxic Viper: a poison cloud lobbed ahead
			var zx: float = clamp(c.x + f.x * 9, -arena.half + 2, arena.half - 2)
			var zz: float = clamp(c.z + f.z * 9, -arena.half + 2, arena.half - 2)
			_add_zone(zx, zz, rad, dur, 14 * pw * c.dmg_mul, c, "toxic", c)
			fx.ring(Vector3(zx, 0, zz), rad, Color(0.5, 1, 0.25))
		"riptide":  # Megalodon: surge plus a wave that shoves and spins out cars in front
			c.speed = max(c.speed, c.stats.max_speed * 1.4)
			fx.ring(c.position + f * 6, rad * 0.8, Color(0.37, 0.72, 1))
			fx.wave(c.position, c.heading)
			for o in _near(c, rad, 0.75):
				var d: float = max(0.5, Vector2(o.x - c.x, o.z - c.z).length())
				var k: float = 1 - min(1.0, d / (rad + 2)) * 0.6
				damage(o, 18 * pw * c.dmg_mul * k, c, false, "special")
				o.kx += (o.x - c.x) / d * 30 * k
				o.kz += (o.z - c.z) / d * 30 * k
				o.skid_t = dur
				o.skid_spin = (1.0 if randf() < 0.5 else -1.0) * randf_range(3, 4.5)
				o.speed *= 0.5
				if o.is_player:
					hud.toast(I18n.t("SKIDDING"))
			if c.is_player:
				shake = max(shake, 0.4)
		"pulse":  # Blue Siren: electric pulse, slows and jams guns
			fx.ring(c.position, rad, Color(0.35, 0.65, 1))
			fx.light(c.position + Vector3.UP * 3, 6.0, Color(0.35, 0.65, 1))
			for o in _near(c, rad):
				o.slow_t = dur * min(1.4, pw)
				o.jam_t = dur * min(1.4, pw)
				damage(o, 8 * pw * c.dmg_mul, c, false, "special")
				fx.line(c.position + Vector3.UP * 2.6, o.position + Vector3.UP * 1.6, 0.18, Color(0.5, 0.8, 1.6), 0.25, 1.0)
				if o.is_player:
					hud.toast(I18n.t("JAMMED"))
		"whip":  # Rex: tail spin, damage and knockback all around
			c.spin_t = 0.55
			fx.ring(c.position, rad, Color(1, 0.42, 0.23))
			fx.light(c.position + Vector3.UP * 2, 5.0)
			for o in _near(c, rad):
				var d: float = max(0.5, Vector2(o.x - c.x, o.z - c.z).length())
				var k: float = 1 - min(1.0, d / (rad + 2)) * 0.5
				damage(o, 30 * pw * c.dmg_mul * k, c, false, "special")
				o.kx += (o.x - c.x) / d * 34 * k
				o.kz += (o.z - c.z) / d * 34 * k
				o.speed *= 0.4
				fx.spark(o.position + Vector3.UP * 1.4, true)
			if c.is_player:
				shake = max(shake, 0.5)
		"shell":  # Blood Titan: slow heavy shell, its path drawn in red so it can be dodged
			var dir := c.heading
			var t: Car = aim_at(c, 80, 0.3) if c.is_player else c.ai.target
			if t and t.alive:
				var want := atan2(t.x - c.x, t.z - c.z)
				if abs(wrapf(want - c.heading, -PI, PI)) < 0.35:
					dir = want
			fire_rocket(c, {"free": true, "kind": "shell", "offset": wrapf(dir - c.heading, -PI, PI), "speed": 30.0,
				"dmg": 85 * pw * (1.0 if c.is_player else c.dmg_mul), "radius": rad})
			var a := Vector3(c.x, 0.08, c.z)
			fx.line(a, a + Vector3(sin(dir), 0, cos(dir)) * 70, 0.7, Color(1, 0.16, 0.1), 1.6, 0.55)
			fx.light(c.position + f * 3 + Vector3.UP * 2.5, 6.0)
			c.kx -= f.x * 8
			c.kz -= f.z * 8
			if c.is_player:
				shake = max(shake, 0.45)
		"ram":
			c.special_on = "ram"
			c.special_t = spec.get("duration", 1.3)
			c.rammed.clear()
			c.speed = max(c.speed, c.stats.max_speed)
		"shield":
			c.special_on = "shield"
			c.special_t = dur * min(1.4, pw)
			if c.bubble:
				c.bubble.visible = true
	if c.is_player:
		hud.flash_special()
	return true


func _ensure_trail(c: Car, kind: String) -> void:
	if c.trail_fx == null:
		c.trail_fx = fx.smoke_trail_emitter() if kind == "smoke" else fx.color_trail_emitter(Color(1, 0.25, 0.7))
		if kind == "dash":
			c.trail_fx.get_parent().remove_child(c.trail_fx)
			c.add_child(c.trail_fx)
			c.trail_fx.position = Vector3(0, 0.8, -c.dims.z * 0.45)
	c.trail_fx.emitting = true


# ---------- projectiles ----------

func hit_obstacle(px: float, py: float, pz: float) -> Dictionary:
	for o in arena.obstacles:
		if o.get("dead", false) or py > o.h + 0.3:
			continue
		if inside_obstacle(o, px, pz):
			return o
	return {}


func _update_bullets(dt: float) -> void:
	var steps := 3
	var keep: Array = []
	for b in bullets:
		b.life -= dt
		var hit := false
		for s in steps:
			b.x += b.dx * BULLET_SPEED * dt / steps
			b.z += b.dz * BULLET_SPEED * dt / steps
			for c in cars:
				if c == b.owner or not c.alive:
					continue
				if Vector2(c.x - b.x, c.z - b.z).length() < c.hit_r:
					damage(c, b.dmg, b.owner, false, "gun")
					fx.spark(Vector3(b.x, b.y, b.z))
					if b.owner.is_player:
						Sfx.play("hit", 0.6)
					hit = true
					break
			if not hit:
				var o := hit_obstacle(b.x, b.y, b.z)
				if not o.is_empty():
					fx.spark(Vector3(b.x, b.y, b.z))
					if o.get("barrel", false):
						damage_obstacle(o, b.dmg, b.owner)
					hit = true
			if abs(b.x) > arena.half or abs(b.z) > arena.half:
				hit = true
			if hit:
				break
		if not hit and b.life <= 0:
			fx.dust(Vector3(b.x, 0, b.z))
		if not hit and b.life > 0:
			keep.append(b)
	bullets = keep
	var mm := _bullet_mm.multimesh
	mm.visible_instance_count = bullets.size()
	for i in bullets.size():
		var b: Dictionary = bullets[i]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(b.dx, b.dz)), Vector3(b.x, b.y, b.z)))
		mm.set_instance_color(i, Color(2.0, 1.7, 1.0) if b.owner.is_player else Color(2.0, 1.1, 0.7))


func _update_rockets(dt: float) -> void:
	var keep: Array = []
	for r in rockets:
		r.life -= dt
		var hm = r.homing
		if hm and hm.alive and hm.hide_t <= 0 and r.life < 2.2:
			var want := atan2(hm.x - r.x, hm.z - r.z)
			r.dir += clamp(wrapf(want - r.dir, -PI, PI), -3 * dt, 3 * dt)
		var step: float = r.speed * dt
		r.x += sin(r.dir) * step
		r.z += cos(r.dir) * step
		r.y = max(1.0, r.y - dt * 0.4)
		r.node.position = Vector3(r.x, r.y, r.z)
		r.node.rotation.y = r.dir
		r.trail.global_position = Vector3(r.x - sin(r.dir) * 0.8, r.y, r.z - cos(r.dir) * 0.8)
		if not r.warned:
			_warn_incoming(r)
		var boom: bool = r.life <= 0 or abs(r.x) > arena.half - 0.8 or abs(r.z) > arena.half - 0.8
		if not boom:
			for c in cars:
				if c != r.owner and c.alive and Vector2(c.x - r.x, c.z - r.z).length() < c.hit_r + 0.4:
					boom = true
					break
		if not boom and not hit_obstacle(r.x, r.y, r.z).is_empty():
			boom = true
		if boom:
			r.node.visible = false
			r.trail.emitting = false
			r.busy = false
			if r.kind == "nuke":
				_nuke_blast(r.x, r.z, r.radius, r.dmg, r.owner)
			else:
				explode(r.x, r.z, r.radius, r.dmg, r.owner, 1.5 if r.kind == "shell" else 0.8, "special" if (r.homing or r.kind == "shell") else "rocket", r.get("hit_sound", false))
				if r.kind == "napalm":
					_add_zone(r.x, r.z, 7, 6, 20 * r.owner.dmg_mul, r.owner, "fire")
		else:
			keep.append(r)
	rockets = keep


## "Wheeeew... boom": an enemy rocket on course to hit the player whistles in, timed to land with the impact.
func _warn_incoming(r: Dictionary) -> void:
	var p := player
	if not p.alive or r.owner == p:
		return
	var dx: float = p.x - r.x
	var dz: float = p.z - r.z
	if Vector2(dx, dz).length() > 38:
		return
	var fx_ := sin(r.dir)
	var fz := cos(r.dir)
	var ahead := dx * fx_ + dz * fz
	if ahead <= 0:
		r.warned = true
		return
	if abs(dx * fz - dz * fx_) > p.hit_r + 3:
		return
	r.warned = true
	if time - _last_incoming < 0.6:
		return
	_last_incoming = time
	r.hit_sound = true
	var secs: float = ahead / r.speed
	later(max(0.0, secs - Sfx.INCOMING_HIT_AT), func(): Sfx.incoming_hit(Vector3(player.x, 1, player.z)))


func _nuke_blast(x: float, z: float, radius: float, dmg: float, owner: Car) -> void:
	fx.explosion(Vector3(x, 0, z), 2.6, "car")
	later(0.15, func(): fx.explosion(Vector3(x + randf_range(-4, 4), 0, z + randf_range(-4, 4)), 1.6))
	later(0.32, func(): fx.explosion(Vector3(x + randf_range(-5, 5), 0, z + randf_range(-5, 5)), 1.0))
	fx.ring(Vector3(x, 0, z), radius * 1.3, Color(1, 0.88, 0.63))
	fx.light(Vector3(x, 8, z), 30.0, Color(1, 0.94, 0.75))
	Sfx.nuke_blast(Vector3(x, 1, z))
	hud.whiteout()
	shake = 1.2
	explode(x, z, radius, dmg, owner, 0, "rocket")
	_add_zone(x, z, 10, 5, 15, owner, "fire")


func explode(x: float, z: float, radius: float, dmg: float, owner: Car, size := 1.0, cause := "rocket", silent := false) -> void:
	if size > 0:
		fx.explosion(Vector3(x, 0, z), size, "car" if cause == "barrel" else "rocket")
		if not silent:
			Sfx.explosion(Vector3(x, 1, z), size)
		var pd := Vector2(player.x - x, player.z - z).length()
		shake = max(shake, clamp(1 - pd / 45, 0.0, 1.0) * 0.7 * size)
	for c in cars:
		if not c.alive:
			continue
		var d := Vector2(c.x - x, c.z - z).length()
		if d > radius + c.hit_r:
			continue
		var k: float = clamp(1 - max(0.0, d - c.hit_r) / radius, 0.3, 1.0)
		damage(c, dmg * k * (0.25 if c == owner else 1.0), owner, false, cause)
		var nx: float = (c.x - x) / max(d, 0.5)
		var nz: float = (c.z - z) / max(d, 0.5)
		c.kx += nx * 14 * k
		c.kz += nz * 14 * k
	for o in arena.obstacles:
		if o.get("barrel", false) and not o.get("dead", false) and Vector2(o.x - x, o.z - z).length() < radius + 1:
			later(0.09 + randf() * 0.12, func(): damage_obstacle(o, 99, owner))


func damage_obstacle(o: Dictionary, dmg: float, by: Car) -> void:
	if o.get("dead", false) or not running:
		return
	o.hp -= dmg
	if o.hp > 0:
		return
	o.dead = true
	arena.hide_barrel(o)
	if by and by.is_player:
		stats.barrels += 1
	explode(o.x, o.z, 9, 55, by, 1.25, "barrel")
	_add_zone(o.x, o.z, 3.5, 4, 12, by, "fire")


func _add_zone(x: float, z: float, r: float, t: float, dps: float, owner: Car, kind: String, safe: Car = null) -> void:
	var e: GPUParticles3D = null
	for item in _zone_pool[kind]:
		if not item.emitting:
			e = item
			break
	if e:
		e.global_position = Vector3(x, 0.4 if kind == "toxic" else 0.2, z)
		var pm: ParticleProcessMaterial = e.process_material
		pm.emission_sphere_radius = r * 0.8
		e.amount_ratio = clamp(r / 9.0, 0.35, 1.0)
		e.emitting = true
	zones.append({"x": x, "z": z, "r": r, "t": t, "dps": dps, "owner": owner, "kind": kind, "safe": safe, "fx": e})


func _update_zones(dt: float) -> void:
	_poison_msg -= dt
	var keep: Array = []
	for zn in zones:
		zn.t -= dt
		for c in cars:
			if c.alive and c != zn.safe and Vector2(c.x - zn.x, c.z - zn.z).length() < zn.r + c.hit_r * 0.5:
				damage(c, zn.dps * dt, zn.owner, true, "special" if zn.kind == "toxic" else "fire")
				if zn.kind == "toxic" and c.is_player and _poison_msg <= 0:
					_poison_msg = 2.5
					hud.toast(I18n.t("POISONED"))
		if zn.t > 0:
			keep.append(zn)
		elif zn.fx:
			zn.fx.emitting = false
	zones = keep


# ---------- pickups and airdrops ----------

func _update_pickups(dt: float) -> void:
	for p in pickups:
		if p.respawn > 0:
			p.respawn -= dt
			p.node.visible = p.respawn <= 0
			continue
		p.node.rotation.y += dt * 1.6
		p.node.position.y = 1.4 + sin(time * 3 + p.x) * 0.25
		for c in cars:
			if not c.alive or Vector2(c.x - p.x, c.z - p.z).length() > 3:
				continue
			if p.type == "health":
				if c.hp >= c.max_hp:
					continue
				c.hp = min(c.max_hp, c.hp + c.max_hp * 0.4)
				fx.heal(c.position)
			else:
				if c.rockets >= 12:
					continue
				c.rockets = min(12, c.rockets + 4)
			if c.is_player:
				Sfx.play("pickup")
				hud.toast(I18n.t("+ ARMOR REPAIRED" if p.type == "health" else "+4 ROCKETS"))
			p.respawn = 16.0
			p.node.visible = false
			break


func _spawn_drop() -> void:
	var s := _nudge_clear({"x": randf_range(-0.6, 0.6) * arena.half, "z": randf_range(-0.6, 0.6) * arena.half}, 4)
	var g := Node3D.new()
	g.position = Vector3(s.x, 40, s.z)
	var crate := prop_model("dropcrate", 2.5)
	var chute := prop_model("parachute", 6.5, true)
	var ch: float = crate.get_meta("h")
	chute.position.y = ch / 2 + 0.25  # the rigging lines meet on the crate lid
	g.add_child(crate)
	g.add_child(chute)
	add_child(g)
	var beacon := fx.beacon_emitter()
	beacon.global_position = Vector3(s.x, 1.2, s.z)
	beacon.emitting = true
	var type: String = Data.POWERS.keys().pick_random()
	drops.append({"x": s.x, "z": s.z, "y": 40.0, "ground": ch / 2 + 0.05, "node": g, "chute": chute, "landed": false, "type": type, "beacon": beacon})
	hud.announce(I18n.t("AIRDROP INCOMING"), I18n.t("Follow the blue smoke"), "blue")
	Sfx.play("alarm", 0.8)


func _update_drops(dt: float) -> void:
	drop_t -= dt
	if drop_t <= 0 and drops.size() < 2:
		drop_t = randf_range(30, 42)
		_spawn_drop()
	var keep: Array = []
	for d in drops:
		var taken := false
		if not d.landed:
			d.y -= dt * 7
			d.node.position.y = d.y
			d.node.rotation.y += dt * 0.6
			if d.y <= d.ground:
				d.landed = true
				d.y = d.ground
				d.node.position.y = d.ground
				d.chute.queue_free()
				fx.dust(Vector3(d.x, 0, d.z))
				fx.dust(Vector3(d.x + 1, 0, d.z - 1))
				Sfx.play_at("crunch", d.node.position)
		else:
			d.node.rotation.y += dt
			for c in cars:
				if not c.alive or Vector2(c.x - d.x, c.z - d.z).length() > 3.2:
					continue
				c.power = {"type": d.type, "ammo": Data.POWERS[d.type].ammo}
				if c.is_player:
					stats.airdrops += 1
					Sfx.play("powerup")
					hud.announce(I18n.t(Data.POWERS[d.type].name).to_upper(), I18n.t("{p} · rocket button", {"p": I18n.t(Data.POWERS[d.type].desc)}), "blue")
				elif Vector2(c.x - player.x, c.z - player.z).length() < 70:
					hud.feed_text(I18n.t("{car} grabbed the {p}", {"car": c.data.name, "p": I18n.t(Data.POWERS[d.type].name)}))
				d.node.queue_free()
				d.beacon.emitting = false
				taken = true
				break
		if not taken:
			keep.append(d)
	drops = keep


# ---------- map events ----------

func _update_events(dt: float) -> void:
	if storm > 0:
		storm -= dt
		if _sand:
			_sand.global_position = Vector3(player.x - 18, 2.5, player.z - 6)
			_sand.emitting = storm > 1.5
		var k: float = (14 - storm) / 2.0 if storm > 12 else (storm / 2.0 if storm < 2 else 1.0)
		arena.env.fog_enabled = storm > 0
		arena.env.fog_light_color = Color(0.78, 0.63, 0.45)
		arena.env.fog_density = 0.035 * k
	event_t -= dt
	if event_t > 0:
		return
	event_t = randf_range(28, 38)
	match map.event:
		"artillery":
			hud.announce(I18n.t("ARTILLERY STRIKE"), I18n.t("Get out of the red circles"), "red")
			Sfx.play("alarm")
			var alive := cars.filter(func(c): return c.alive)
			for i in 7:
				var c: Car = alive.pick_random() if i < 4 else null
				var sx: float = c.x + randf_range(-6, 6) if c else randf_range(-0.8, 0.8) * arena.half
				var sz: float = c.z + randf_range(-6, 6) if c else randf_range(-0.8, 0.8) * arena.half
				_add_strike(sx, sz, 6.5, 2.2 + i * 0.25, 48)
		"rupture":
			var tanks := arena.obstacles.filter(func(o): return o.get("tank", false) and not o.get("ruptured", false))
			if tanks.is_empty():
				return
			var t: Dictionary = tanks[0]
			for o in tanks:
				if Vector2(o.x - player.x, o.z - player.z).length() < Vector2(t.x - player.x, t.z - player.z).length():
					t = o
			t.ruptured = true
			hud.announce(I18n.t("TANK RUPTURE"), I18n.t("A fuel tank is about to blow"), "red")
			Sfx.play("alarm")
			_add_strike(t.x, t.z, t.r + 9, 2.6, 75, func():
				_add_zone(t.x, t.z, t.r + 4, 9, 16, null, "fire")
				fx.explosion(Vector3(t.x + t.r, 0, t.z), 1.4)
				fx.explosion(Vector3(t.x - t.r, 0, t.z + 1), 1.2), 2.2)
		_:
			storm = 14.0
			hud.announce(I18n.t("SANDSTORM"), I18n.t("Visibility dropping"), "gold")
			Sfx.play("wind")


func _add_strike(x: float, z: float, r: float, delay: float, dmg: float, after := Callable(), size := 1.0) -> void:
	var vis: Dictionary = {}
	for item in _strike_pool:
		if not item.busy:
			vis = item
			break
	if vis.is_empty():
		vis = _make_strike()
		_strike_pool.append(vis)
	vis.busy = true
	vis.ring.position = Vector3(x, 0.06, z)
	vis.ring.scale = Vector3(r, 0.05, r)
	vis.fill.position = Vector3(x, 0.05, z)
	vis.fill.scale = Vector3(0.01, 1, 0.01)
	vis.ring.visible = true
	vis.fill.visible = true
	strikes.append({"x": x, "z": z, "r": r, "t": delay, "total": delay, "dmg": dmg, "vis": vis, "after": after, "size": size, "whistled": false})


func _update_strikes(dt: float) -> void:
	var keep: Array = []
	for s in strikes:
		s.t -= dt
		var k: float = 1 - s.t / s.total
		s.vis.rm.albedo_color.a = 0.4 + 0.5 * abs(sin(time * (6 + k * 14)))
		s.vis.fill.scale = Vector3(max(0.01, k) * s.r, 1, max(0.01, k) * s.r)
		if not s.whistled and s.t <= min(s.total, 1.05):  # the shell's whistle is about a second long
			s.whistled = true
			Sfx.incoming(s.t, Vector3(s.x, 6, s.z))
		if s.t > 0:
			keep.append(s)
			continue
		s.vis.busy = false
		s.vis.ring.visible = false
		s.vis.fill.visible = false
		Sfx.nuke_blast(Vector3(s.x, 1, s.z), 1.0)
		explode(s.x, s.z, s.r, s.dmg, null, s.size * 1.1, "event", true)
		if s.after.is_valid():
			s.after.call()
	strikes = keep


# ---------- damage and death ----------

func damage(c: Car, amt: float, by: Car, quiet := false, cause := "gun") -> void:
	if not c.alive or amt <= 0 or state == "countdown" or c.invuln > 0:
		return
	if c.special_on == "shield":
		amt *= 0.3  # Bulwark: 70% less damage
	if c.special_on == "dash":
		amt *= 0.5
	c.hp -= amt
	c.last_hit = time
	if by and by != c:
		c.last_attacker = by
		c.last_cause = cause
	if c.is_player:
		hud.hurt(amt)
		if not quiet:
			Sfx.play("hurt", 0.7)
	if not c.ai.is_empty() and by and by != c and randf() < 0.5:
		c.ai.target = by
	if c.hp <= 0:
		_kill(c)


func _kill(c: Car) -> void:
	c.alive = false
	c.hp = 0
	c.death_t = 0
	c.visible = true
	c.lives = max(0, c.lives - 1)
	if c.lives > 0:
		c.respawn_t = 3.2
	c.special_on = ""
	if c.bubble:
		c.bubble.visible = false
	if c.trail_fx:
		c.trail_fx.emitting = false
	c.vy = randf_range(10, 15)
	c.srx = randf_range(-5, 5)
	c.srz = randf_range(-7, 7)
	c.y = 0.01
	c.kx += randf_range(-6, 6)
	c.kz += randf_range(-6, 6)
	var p := c.position
	fx.explosion(p, 1.8, "car")
	later(0.25, func(): fx.explosion(p + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), 0.6))
	Sfx.explosion(p, 1.6)
	c.wreck()
	var killer: Car = c.last_attacker if c.last_attacker and c.last_attacker != c else null
	if killer:
		killer.kills += 1
	hud.feed(killer, c)
	if c.is_player:
		shake = 1.0
	elif Vector2(c.x - player.x, c.z - player.z).length() < 40:
		shake = max(shake, 0.6)
	if killer and killer.is_player:
		stats.kills += 1
		if c.last_cause == "rocket":
			stats.rocket_kills += 1
		if not stats.first_blood:
			stats.first_blood = true
			stats.bonus.append({"label": "First blood", "pts": 25})
		streak = streak + 1 if time - last_kill_t < 7 else 1
		last_kill_t = time
		stats.streak_max = max(stats.streak_max, streak)
		var st = STREAKS.get(min(5, streak))
		if streak >= 2 and st:
			stats.bonus.append({"label": st[0].capitalize(), "pts": st[1]})
			hud.announce(I18n.t(st[0]), I18n.t("+{n} streak bonus", {"n": st[1]}), "gold")
			Sfx.play("streak")
		elif not c.bounty:
			hud.announce(I18n.t("WRECKED"), c.data.name, "kill")
	if c.bounty:
		if killer and killer.is_player:
			var pts := int(round(100 * diff.get("reward", 1.0)))
			stats.bounty += 1
			stats.bonus.append({"label": "Crown claimed", "pts": pts})
			hud.announce(I18n.t("CROWN CLAIMED"), "+%d" % pts, "gold")
			Sfx.play("streak")
		if mode == "survival" or c.lives == 0:
			set_bounty(null, false)
	if c.is_player and c.lives > 0:
		hud.announce(I18n.t("WRECKED"), I18n.t("Last life · back in 3s" if c.lives == 1 else "{n} lives left · back in 3s", {"n": c.lives}), "red")
	_update_leader()


func _update_wreck(c: Car, dt: float) -> void:
	c.death_t += dt
	if c.y > 0 or c.vy > 0:  # airborne tumble
		c.vy -= 30 * dt
		c.y += c.vy * dt
		c.rx += c.srx * dt
		c.rz += c.srz * dt
		if c.y <= 0:
			c.y = 0
			if c.vy < -4:
				c.vy *= -0.3
				c.srx *= 0.4
				c.srz *= 0.4
				fx.dust(c.position)
				fx.spark(c.position + Vector3.UP * 0.5, true)
				if Vector2(c.x - player.x, c.z - player.z).length() < 50:
					Sfx.play_at("crunch", c.position)
			else:
				c.vy = 0
				c.srx = 0
				c.srz = 0
	else:  # settle flat: right side up or on its roof
		c.rx += (round(c.rx / PI) * PI - c.rx) * min(1.0, dt * 6)
		c.rz += (round(c.rz / PI) * PI - c.rz) * min(1.0, dt * 6)
	c.speed *= exp(-3 * dt)
	var f := c.forward()
	c.x += (f.x * c.speed + c.kx) * dt
	c.z += (f.z * c.speed + c.kz) * dt
	c.kx *= exp(-2.5 * dt)
	c.kz *= exp(-2.5 * dt)
	_collide_world(c)
	var lift := (1 - cos(c.rx) * cos(c.rz)) * 0.8
	c.position = Vector3(c.x, c.y + lift, c.z)
	c.basis = Basis.from_euler(Vector3(c.rx, c.heading, c.rz), EULER_ORDER_YXZ)


## Brings a wrecked car back at the spawn point farthest from its enemies, briefly invulnerable.
## The old wreck stays behind, smoulders and sinks away.
func _respawn(c: Car) -> void:
	var husk := Node3D.new()
	add_child(husk)
	husk.global_transform = c.global_transform
	var old := c.swap_model(_scenes[c.data.id])
	husk.add_child(old)
	var smoke := fx.burn_emitter()
	smoke.get_parent().remove_child(smoke)
	husk.add_child(smoke)
	smoke.position.y = 1.4
	smoke.emitting = true
	wrecks.append({"node": husk, "t": 0.0})
	var foes := cars.filter(func(o): return o != c and o.alive)
	var best: Dictionary = spawns[0]
	var best_d := -1.0
	for sp in spawns:
		var d := 0.0
		if foes.size():
			d = INF
			for o in foes:
				d = min(d, Vector2(o.x - sp.x, o.z - sp.z).length())
		if d > best_d:
			best_d = d
			best = sp
	c.x = best.x
	c.z = best.z
	c.heading = best.heading
	c.speed = 0; c.kx = 0; c.kz = 0; c.y = 0; c.vy = 0; c.rx = 0; c.rz = 0; c.srx = 0; c.srz = 0; c.steer_s = 0
	c.hp = c.max_hp
	c.alive = true
	c.rockets = 6
	c.special_cd = 2
	c.special_on = ""
	c.special_t = 0
	c.power = {}
	c.last_attacker = null
	c.last_cause = ""
	c.invuln = 2.5
	c.respawn_t = 0
	c.slow_t = 0; c.jam_t = 0; c.skid_t = 0; c.hide_t = 0; c.spin_t = 0
	c.rammed.clear()
	c.position = Vector3(c.x, 0, c.z)
	c.basis = Basis(Vector3.UP, c.heading)
	if c.crown:
		c.crown.position = c.roof
	fx.heal(c.position)
	fx.ring(c.position, 6, Color(0.62, 0.83, 1))
	if c.is_player:
		hud.announce(I18n.t("BACK IN THE FIGHT"), I18n.t("Last life" if c.lives == 1 else "{n} lives left", {"n": c.lives}), "green")
		_snap_camera()
	if not c.ai.is_empty():
		c.ai.target = null
	hud.ensure_enemy_bars(self)


## The crown always sits on the car with the most kills (ties keep the current holder).
func _update_leader() -> void:
	if mode != "deathmatch":
		return
	var pool := cars.filter(func(o): return _in_play(o) and o.kills > 0)
	if pool.is_empty():
		return
	var top := 0
	for o in pool:
		top = max(top, o.kills)
	var holder: Car = null
	for o in cars:
		if o.bounty:
			holder = o
	if holder and _in_play(holder) and holder.kills == top:
		return
	for o in pool:
		if o.kills == top:
			if o != holder:
				set_bounty(o, true)
			return


func set_bounty(c: Car, announce := true) -> void:
	for o in cars:
		if o.crown:
			o.crown.queue_free()
			o.crown = null
		o.bounty = false
	if c == null or not c.alive:
		return
	c.bounty = true
	c.crown = prop_model("crown", 1.3, true)
	c.add_child(c.crown)
	c.crown.position = c.roof
	if announce:
		if c.is_player:
			hud.announce(I18n.t("YOU TAKE THE CROWN"), I18n.t("Every car is hunting you now"), "gold")
		else:
			hud.announce(I18n.t("NEW LEADER"), I18n.t("{car} has the most kills", {"car": c.data.name}), "gold")


# ---------- AI ----------

func _think(c: Car, dt: float) -> void:
	var ai := c.ai
	ai.retarget -= dt
	if ai.target and ai.target.hide_t > 0:
		ai.target = null  # lost in the smoke
	if ai.target == null or not ai.target.alive or ai.retarget <= 0:
		ai.retarget = randf_range(2, 4)
		var best: Car = null
		var bs := INF
		for o in cars:
			if o == c or not o.alive or o.hide_t > 0:
				continue
			if mode == "survival" and not o.is_player and randf() < 0.85:
				continue
			var sc: float = Vector2(o.x - c.x, o.z - c.z).length() * (diff.focus if o.is_player else 1.0) * (0.7 if o.hp / o.max_hp < 0.3 else 1.0) * (0.75 if o.bounty else 1.0)
			if sc < bs:
				bs = sc
				best = o
		ai.target = best if best else (player if player.alive and player.hide_t <= 0 else null)
	var t: Car = ai.target
	if t == null:
		c.throttle = 0.3
		c.steer = 0
		c.firing = false
		return
	var dx := t.x - c.x
	var dz := t.z - c.z
	var dist := Vector2(dx, dz).length()
	var to_t := atan2(dx, dz)
	var want := to_t
	if dist < 14:
		want = to_t + ai.strafe * 1.1
	# detours: repairs when hurt, airdrops when close, away from strike circles
	var drop: Dictionary = {}
	for d in drops:
		if d.landed and Vector2(d.x - c.x, d.z - c.z).length() < 40:
			drop = d
			break
	if not drop.is_empty() and c.power.is_empty() and dist > 12:
		want = atan2(drop.x - c.x, drop.z - c.z)
	elif c.hp < c.max_hp * 0.3:
		var hp_spot: Dictionary = {}
		var hd := INF
		for p in pickups:
			if p.type == "health" and p.respawn <= 0:
				var d := Vector2(p.x - c.x, p.z - c.z).length()
				if d < hd:
					hd = d
					hp_spot = p
		if not hp_spot.is_empty() and hd < 50:
			want = atan2(hp_spot.x - c.x, hp_spot.z - c.z)
	for s in strikes:
		if Vector2(s.x - c.x, s.z - c.z).length() < s.r + 3:
			want = atan2(c.x - s.x, c.z - s.z)
			break
	var probe := func(ang: float, d: float) -> bool:
		var px := c.x + sin(ang) * d
		var pz := c.z + cos(ang) * d
		return not hit_obstacle(px, 1, pz).is_empty() or abs(px) > arena.half - 4 or abs(pz) > arena.half - 4
	if probe.call(c.heading, 7.0) or probe.call(c.heading, 11.0):
		var l: bool = probe.call(c.heading - 0.6, 9.0)
		var r: bool = probe.call(c.heading + 0.6, 9.0)
		want = c.heading + (1.2 if l and not r else (-1.2 if r and not l else ai.strafe * 1.2))
	var steer: float = clamp(wrapf(want - c.heading, -PI, PI) * 2.2, -1.0, 1.0)
	var throttle := 0.55 if dist < 9 else 1.0
	if ai.reverse_t > 0:
		ai.reverse_t -= dt
		throttle = -1
		steer = -steer if steer != 0 else ai.strafe
	elif abs(c.speed) < 2 and state == "fight":
		ai.stuck += dt
		if ai.stuck > 0.9:
			ai.reverse_t = 1.1
			ai.stuck = 0
			ai.strafe *= -1
	else:
		ai.stuck = 0
	c.throttle = throttle * (0.75 + 0.25 * diff.get("aggression", 1.0))
	c.steer = steer
	var aim: float = abs(wrapf(to_t - c.heading, -PI, PI))
	c.firing = dist < 48 and aim < 0.3
	ai.rocket_t -= dt
	if ai.rocket_t <= 0 and dist < (70 if not c.power.is_empty() else 55) and aim < 0.2:
		fire_rocket(c)
		ai.rocket_t = randf_range(2.5, 5) / diff.get("aggression", 1.0)
	ai.special_t -= dt
	if ai.special_t <= 0 and c.special_cd <= 0:
		var sp: String = c.data.special.id
		var recent := time - c.last_hit < 1.2
		var go: bool = (sp == "smoke" and c.hp < c.max_hp * 0.5 and recent) or (sp == "dash" and (dist > 32 or (c.hp < c.max_hp * 0.4 and recent))) \
			or (sp == "toxic" and dist < 18 and aim < 0.5) or (sp == "riptide" and dist < 13 and aim < 0.6) or (sp == "pulse" and dist < 14) \
			or (sp == "whip" and dist < 9) or (sp == "shell" and dist < 55 and aim < 0.12) or (sp == "ram" and dist < 22 and aim < 0.25) \
			or (sp == "shield" and c.hp < c.max_hp * 0.55 and time - c.last_hit < 1)
		if go and randf() < diff.get("aggression", 1.0):
			use_special(c)
		ai.special_t = randf_range(0.8, 2)


# ---------- camera ----------

func _snap_camera() -> void:
	_update_camera(1.0, true)


func base_fov() -> float:
	var vp := get_viewport().get_visible_rect().size
	var a: float = vp.x / max(1.0, vp.y)
	return 78.0 if a < 1 else 62.0 + max(0.0, 1.75 - a) * 20.0


func _update_camera(dt: float, snap := false) -> void:
	var p := player
	var f := p.forward()
	var size: float = max(1.0, p.dims.z / 5.2)
	var mode_ := cam_mode
	if mode_ == "hood" and not p.alive:
		mode_ = "near"
	var speed_pull: float = clamp(abs(p.speed) / 40.0, 0.0, 1.0) * (2.5 if mode_ == "far" else 1.5)
	var want: Vector3
	var look: Vector3
	var k: float
	if mode_ == "hood":
		var h := p.dims.y * 0.95 + 0.3
		want = Vector3(p.x + f.x * p.dims.z * 0.02, h, p.z + f.z * p.dims.z * 0.02)
		look = Vector3(p.x + f.x * 30, h - 2.6, p.z + f.z * 30)
		k = 1.0 if snap else 1 - exp(-dt * 30)
	else:
		var back := (13.0 if mode_ == "far" else 8.5) * size
		var up := (7.5 if mode_ == "far" else 4.6) * sqrt(size)
		want = Vector3(p.x - f.x * (back + speed_pull), up + speed_pull * 0.3, p.z - f.z * (back + speed_pull))
		look = Vector3(p.x + f.x * (6 if mode_ == "far" else 8), 1.5 if mode_ == "far" else 1.8, p.z + f.z * (6 if mode_ == "far" else 8))
		k = 1.0 if snap else 1 - exp(-dt * (4.5 if mode_ == "far" else 6.0))
		# never behind the arena walls or inside tall cover: pull in and lift
		var lim := arena.half + 1.2
		var dx := want.x - p.x
		var dz := want.z - p.z
		var t := 1.0
		if abs(want.x) > lim and abs(dx) > 0.01:
			t = min(t, (sign(dx) * lim - p.x) / dx)
		if abs(want.z) > lim and abs(dz) > 0.01:
			t = min(t, (sign(dz) * lim - p.z) / dz)
		for i in range(1, 11):
			var u := float(i) / 10.0 * t
			var hh := 1.5 + (want.y - 1.5) * u
			var o := hit_obstacle(p.x + dx * u, hh, p.z + dz * u)
			if not o.is_empty() and o.h > 2.5:
				t = max(0.25, u - 0.12)
				break
		if t < 1:
			t = max(0.25, t)
			want = Vector3(p.x + dx * t, want.y * (0.35 + 0.65 * t) + (1 - t) * 2.5, p.z + dz * t)
			look = look - f * (1 - t) * 3
	if _cam_mode_t > 0:
		_cam_mode_t -= dt
		k = max(k, 0.25)
	_cam_pos = _cam_pos.lerp(want, k)
	_cam_look = _cam_look.lerp(look, max(k, 1 - exp(-dt * 20)) if (snap or mode_ == "hood") else 1 - exp(-dt * 7))
	var pos := _cam_pos
	if shake > 0:
		var s := shake * shake * 1.2
		pos += Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))
		shake = max(0.0, shake - dt * 1.8)
	camera.global_position = pos
	if pos.distance_to(_cam_look) > 0.01:
		camera.look_at(_cam_look, Vector3.UP)
	var fov := base_fov() + (8.0 if p.special_on == "ram" else 0.0)
	camera.fov += (fov - camera.fov) * min(1.0, dt * 5)


# ---------- end ----------

func _check_end() -> void:
	var p := player
	if not p.alive and p.lives == 0:
		result = "survival" if mode == "survival" else "loss"
		state = "ending"
		end_t = 3
		Sfx.play("lose")
		hud.banner(I18n.t("WAVE") + " %d" % wave if mode == "survival" else I18n.t("WRECKED"), false)
		return
	if mode != "deathmatch":
		return
	var left := cars.filter(func(c): return _in_play(c))
	if left.size() == 1 and left[0] == p:
		result = "win"
		state = "ending"
		end_t = 3
		Sfx.play("win")
		hud.banner(I18n.t("VICTORY"), true)
		return
	if time - 3.5 >= TIME_LIMIT:  # time up: most kills wins (a tie goes to the player)
		var top := 0
		for c in cars:
			top = max(top, c.kills)
		var win := p.kills >= top
		result = "win" if win else "loss"
		state = "ending"
		end_t = 3
		Sfx.play("win" if win else "lose")
		hud.banner(I18n.t("VICTORY") if win else I18n.t("TIME UP"), win)


func time_left() -> float:
	return max(0.0, TIME_LIMIT - max(0.0, time - 3.5)) if mode == "deathmatch" else -1.0


func _finish() -> void:
	if over:
		return
	over = true
	running = false
	Sfx.engine_stop()
	finished.emit({"result": result, "mode": mode, "kills": player.kills, "time": time, "stats": stats})


func quit() -> void:
	running = false
	over = true
	Sfx.engine_stop()
