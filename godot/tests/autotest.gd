extends Node
## Automated playthrough for development: started by main.gd when the app is run with `-- --test=<name>`.
## Plays matches with the player's car driven by the AI, fast-forwarded, takes screenshots and reports errors.
##   --test=match   one deathmatch on each map, a screenshot per map, stats printed
##   --test=shots   lobby, garage, settings (Arabic), setup, a fight, a strike and an airdrop
##   --out=<dir>    where screenshots go

var main: Node
var out := "/tmp"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var test := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			test = a.substr(7)
	await get_tree().process_frame
	match test:
		"match": await _matches()
		"shots": await _shots()
		"bench": await _bench()
		"fx": await _fx()
		"coords": await _coords()
		"mpshots": await _mpshots()
		"intro": await _intro()
		"profile": await _profile_shots()
		"lobby3d": await _lobby3d()
		"net_host": await _net_host()
		"net_join": await _net_join()
	get_tree().quit()


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("TEST shot ", name)


func _start(map_i: int, car := "ghost", diff := 1, mode := "deathmatch") -> Match:
	main._start_match({"car": Data.car(car), "upgrades": {}, "map": Data.MAPS[map_i], "diff": Data.DIFFICULTY[diff], "mode": mode})
	while main.game == null or not main.game.running:
		await get_tree().process_frame
	return main.game


## Runs the match logic quickly: the player is driven by the same AI as everyone else.
func _simulate(g: Match, seconds: float) -> void:
	if g.player.ai.is_empty():
		g.player.ai = {"target": null, "retarget": 0.0, "stuck": 0.0, "reverse_t": 0.0, "rocket_t": 2.0, "strafe": 1.0, "special_t": 3.0}
	var steps := int(seconds * 30)
	for i in steps:
		if not g.running:
			break
		g._think(g.player, 1.0 / 30)
		g._process(1.0 / 30)
		if g.player.respawn_t <= 0 and not g.player.alive and g.player.lives == 0:
			break


func _matches() -> void:
	for i in Data.MAPS.size():
		var g := await _start(i, Data.CARS[(i * 2) % Data.CARS.size()].id, i % 3)
		var t0 := Time.get_ticks_msec()
		_simulate(g, 70)
		print("TEST map=%s cars=%d alive=%d kills=%s state=%s bullets=%d rockets=%d sim_ms=%d" % [g.map.id, g.cars.size(),
			g.cars.filter(func(c): return c.alive).size(), str(g.cars.map(func(c): return c.kills)), g.state, g.bullets.size(), g.rockets.size(), Time.get_ticks_msec() - t0])
		var mid: String = g.map.id
		for f in 20:
			await get_tree().process_frame
		await _shot("match_" + mid)
		main._lobby()
		await get_tree().process_frame
	var sv := await _start(1, "titan", 1, "survival")
	_simulate(sv, 90)
	print("TEST survival wave=%d cars=%d state=%s" % [sv.wave, sv.cars.size(), sv.state])
	main._lobby()
	await get_tree().process_frame


func _shots() -> void:
	await get_tree().create_timer(0.5).timeout
	await _shot("1_lobby")
	main._garage()
	await get_tree().process_frame
	await _shot("2_garage")
	Save.state.lang = "ar"
	I18n.set_lang("ar")
	main._settings()
	await get_tree().process_frame
	await _shot("3_settings_ar")
	main._lobby()
	await get_tree().process_frame
	await _shot("4_lobby_ar")
	main._controls_editor()
	await get_tree().process_frame
	await _shot("4b_controls_ar")
	main._workshop()
	await get_tree().process_frame
	await _shot("4c_workshop_ar")
	Save.state.lang = "en"
	I18n.set_lang("en")
	main._setup_screen()
	await get_tree().process_frame
	await _shot("5_setup")
	var g := await _start(0, "toxic", 1)
	for f in 10:
		await get_tree().process_frame
	await _shot("6_countdown")
	_simulate(g, 8)
	for f in 30:
		await get_tree().process_frame
	await _shot("7_fight")
	g._add_strike(g.player.x + 4, g.player.z + 6, 6.5, 0.4, 0)
	g._spawn_drop()
	for f in 40:
		await get_tree().process_frame
	await _shot("8_strike_drop")
	g.explode(g.player.x + 10 * sin(g.player.heading), g.player.z + 10 * cos(g.player.heading), 6, 0, null, 1.6)
	for f in 12:
		await get_tree().process_frame
	await _shot("9_explosion")
	g.cam_mode = "far"
	for f in 30:
		await get_tree().process_frame
	await _shot("10_far")
	g.camera.global_position = Vector3(0, 30, g.arena.half * 0.95)
	g.camera.look_at(Vector3(0, 25, -g.arena.half - 60))
	g.running = false
	for f in 3:
		await get_tree().process_frame
	await _shot("11_skyline")


## Frame time with the full scene, no simulation shortcuts.
func _bench() -> void:
	var g := await _start(1, "colossus", 2)
	_simulate(g, 5)
	var t0 := Time.get_ticks_usec()
	var frames := 0
	while frames < 120:
		await get_tree().process_frame
		frames += 1
	print("TEST bench avg frame ms=%.1f draw_calls=%d prims=%d" % [(Time.get_ticks_usec() - t0) / 1000.0 / frames,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


## Close-ups of the explosions and fire, frozen at a few moments.
func _fx() -> void:
	var g := await _start(2, "ghost", 0)
	g.running = false
	for c in g.cars:
		c.visible = false
	var p := Vector3(g.player.x, 0, g.player.z)       # spawn points are kept clear of cover
	var right := g.player.forward().cross(Vector3.UP)
	g.camera.global_position = p + g.player.forward() * 26 + Vector3.UP * 6
	g.camera.look_at(p + Vector3.UP * 5)
	var fire := g.fx.flame_emitter(1.6, 4)
	fire.global_position = p - right * 9
	fire.emitting = true
	g.fx.explosion(p, 0.8, "rocket")
	g.fx.explosion(p + right * 10, 1.8, "car")
	for t in [0.25, 0.6, 1.2, 2.5]:
		await get_tree().create_timer(t - (0.0 if t == 0.25 else [0.25, 0.6, 1.2, 2.5][[0.25, 0.6, 1.2, 2.5].find(t) - 1])).timeout
		await _shot("fx_%.2f" % t)


func _coords() -> void:
	var g := await _start(0, "ghost", 0)
	await get_tree().create_timer(0.3).timeout
	var vp := get_viewport()
	var wp := Vector3(g.player.x, 1, g.player.z)
	print("TEST window=", DisplayServer.window_get_size(), " visible_rect=", vp.get_visible_rect().size, " hud_root=", main.hud._root.size,
		" final=", vp.get_final_transform(), " unproject=", g.camera.unproject_position(wp))


# ---------- multiplayer: run one host and one client on this machine ----------

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.substr(k.length() + 3)
	return d


## Both sides drive with the bot brain. Clients must not fire abilities directly: they go through the host.
func _autodrive(g: Match) -> void:
	var p := g.player
	if p.ai.is_empty():
		p.ai = {"target": null, "retarget": 0.0, "stuck": 0.0, "reverse_t": 0.0, "rocket_t": 2.0, "strafe": 1.0, "special_t": 999.0}
	var t := 0.0
	var sp_t := 6.0
	while is_instance_valid(g) and g.running:
		await get_tree().process_frame
		if not is_instance_valid(g):
			return
		var dt := get_process_delta_time()
		t += dt
		if g.state == "fight" and p.alive:
			p.ai.special_t = 999.0
			p.ai.rocket_t = 999.0
			g._think(p, dt)
			sp_t -= dt
			if sp_t <= 0:
				sp_t = 5.0
				g.player_special()
				g.player_rocket()


func _wait(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while not cond.call() and t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


func _net_host() -> void:
	Engine.max_fps = 60
	Save.state.player_name = "Host"
	Net.host()
	Net.set_room("mode", _arg("mode", "deathmatch"))
	Net.set_room("bots", int(_arg("bots", "2")))
	Net.set_room("map", int(_arg("map", "0")))
	var n := int(_arg("players", "2"))
	print("TEST host open, ips=", Net.local_ips())
	if not await _wait(func(): return Net.lobby.players.size() >= n and Net.all_ready(), 40.0):
		print("TEST FAIL nobody joined: ", Net.lobby.players.size())
		return
	print("TEST host starting with ", Net.lobby.players.map(func(p): return p.name))
	Net.start()
	await _wait(func(): return main.game != null and is_instance_valid(main.game) and main.game.state == "fight", 30.0)
	var g: Match = main.game
	print("TEST host fight started, cars=", g.cars.size())
	g.finished.connect(func(r): print("TEST host finished t=%.1f fs=%.1f " % [g.time, g.fight_start], r.result, " ", r.get("ranking", []), " alive=", g.cars.map(func(c): return [c.alive, c.lives, c.respawn_t])))
	_autodrive(g)
	await get_tree().create_timer(float(_arg("secs", "40"))).timeout
	if is_instance_valid(g) and g.running and g.state == "fight":
		g.fight_start -= Match.TIME_LIMIT   # call time
	await _wait(func(): return not is_instance_valid(g) or not g.running, 15.0)
	print("TEST host done result=", main._current)
	await get_tree().create_timer(2.0).timeout


func _net_join() -> void:
	Engine.max_fps = 60
	Save.state.player_name = "Guest"
	main._mp_home()
	var found := await _wait(func(): return not Net.rooms.is_empty(), 6.0)
	print("TEST rooms found by discovery: ", Net.rooms.keys() if found else "none")
	Net.join(_arg("ip", "127.0.0.1"))
	if not await _wait(func(): return not Net.lobby.is_empty(), 10.0):
		print("TEST FAIL could not join")
		return
	print("TEST joined room with ", Net.lobby.players.map(func(p): return p.name))
	await get_tree().create_timer(1.0).timeout
	await _shot("n1_room")
	Net.set_me({"car": "venom", "ready": true})
	if not await _wait(func(): return main.game != null, 20.0):
		print("TEST FAIL match never started")
		return
	var g: Match = main.game
	await _wait(func(): return not is_instance_valid(g) or g.state == "fight", 20.0)
	print("TEST client fight, cars=", g.cars.size(), " me=", g.player.label(), " nid=", g.player.nid)
	var f0 := Engine.get_process_frames()
	var t0 := Time.get_ticks_msec()
	get_tree().create_timer(1.0).timeout.connect(func(): print("TEST client fps≈", (Engine.get_process_frames() - f0) * 1000.0 / max(1, Time.get_ticks_msec() - t0)))
	_autodrive(g)
	if DisplayServer.get_name() != "headless" and _arg("quickshots", "") != "":
		for i in 3:   # software rendering here is very slow: grab a few frames and stop
			for f in 4:
				await get_tree().process_frame
			await _shot("n_live_%d" % i)
		return
	var errs: Array = []
	Net.session_over.connect(func(r): print("TEST session over: ", r))
	g.finished.connect(func(r): print("TEST client finished: ", r.result, " ", r.get("ranking", [])))
	for i in 6:
		await get_tree().create_timer(5.0).timeout
		print("TEST client tick valid=", is_instance_valid(g), " running=", g.running if is_instance_valid(g) else "-", " state=", g.state if is_instance_valid(g) else "-", " game=", main.game)
		if not is_instance_valid(g) or not g.running:
			break
		await _shot("n%d_fight" % (i + 2))
		if not g._snaps.is_empty():
			var v: PackedFloat32Array = g._snaps[-1][1].get(g.player.nid, PackedFloat32Array())
			if not v.is_empty() and g.player.alive:
				errs.append(Vector2(v[1] - g.player.x, v[2] - g.player.z).length())
		print("TEST client t=%.0f snaps=%d rockets=%d kills=%s rtt=%.0fms" % [g.time, g._snaps.size(), g.rockets.size(), str(g.cars.map(func(c): return c.kills)), Net.rtt * 1000])
	print("TEST own-car gap to host snapshot (m): ", errs)
	print("TEST client events: ", Net.event_counts)
	await _wait(func(): return not is_instance_valid(g) or not g.running, 60.0)
	await get_tree().create_timer(1.0).timeout
	await _shot("n9_results")
	print("TEST client done screen=", main._current)


## The multiplayer screens, filled with made-up rooms and players.
func _mpshots() -> void:
	await get_tree().create_timer(0.5).timeout
	Save.state.player_name = ""
	main._ask_name(main._mp_home)
	await get_tree().process_frame
	await _shot("m1_name")
	Save.state.player_name = "Hussain"
	main._mp_home()
	Net.rooms = {"192.168.1.20": {"g": "ironmetal", "p": Net.PROTO, "name": "Abood", "mode": "team", "map": 2, "n": 3, "max": 9, "open": true, "seen": Time.get_ticks_msec() + 99999},
		"192.168.1.31": {"g": "ironmetal", "p": Net.PROTO, "name": "Sami", "mode": "deathmatch", "map": 0, "n": 9, "max": 9, "open": true, "seen": Time.get_ticks_msec() + 99999},
		"192.168.1.40": {"g": "ironmetal", "p": 0, "name": "Old phone", "mode": "survival", "map": 1, "n": 1, "max": 9, "open": true, "seen": Time.get_ticks_msec() + 99999}}
	main._mp_home()
	await get_tree().process_frame
	await _shot("m2_home")
	Net.host()
	Net.lobby.players.append({"peer": 5, "id": "x", "name": "Abood", "color": "62e07a", "team": 2, "car": "rex", "ups": {}, "ready": true})
	Net.lobby.players.append({"peer": 6, "id": "y", "name": "سامي", "color": "5cc8ff", "team": 1, "car": "titan", "ups": {}, "ready": false})
	Net.set_room("mode", "team")
	main._mp_room()
	await get_tree().process_frame
	await _shot("m3_room_host")
	Save.state.lang = "ar"
	I18n.set_lang("ar")
	main._mp_room()
	await get_tree().process_frame
	await _shot("m4_room_ar")
	Save.state.lang = "en"
	I18n.set_lang("en")
	main._last_cfg = {"map": Data.MAPS[2], "diff": Data.DIFFICULTY[1], "mode": "team", "car": Data.car("ghost")}
	var rk := [{"name": "Hussain", "kills": 6, "team": 1, "human": true, "me": true, "car": "WASTELAND GHOST"},
		{"name": "Abood", "kills": 4, "team": 2, "human": true, "me": false, "car": "REX"},
		{"name": "TITAN", "kills": 2, "team": 1, "human": false, "me": false, "car": "TITAN"},
		{"name": "سامي", "kills": 1, "team": 2, "human": true, "me": false, "car": "TITAN"}]
	main._on_finished({"result": "win", "mode": "team", "kills": 6, "time": 140.0, "stats": {"bonus": [], "wave": 0, "kills": 6, "rocket_kills": 2, "barrels": 0, "airdrops": 0, "bounty": 0, "streak_max": 2}, "ranking": rk, "net": true})
	await get_tree().process_frame
	await _shot("m5_results")
	Net.leave()


## Frames of the opening, stepped by hand so slow rendering here doesn't skip moments.
func _intro() -> void:
	await get_tree().process_frame
	var it: Intro = main.get_node("Intro")
	it.set_process(false)
	var t := 0.0
	for at in [0.6, 1.0, 1.75, 2.4, 2.9, 3.6, 4.6, 5.6, 6.3]:
		while t < at:
			it._process(1.0 / 30.0)
			t += 1.0 / 30.0
		await get_tree().process_frame
		await _shot("intro_%.1f" % at)


func _profile_shots() -> void:
	await get_tree().create_timer(0.5).timeout
	Save.state.player_name = "Hussain"
	Profile.set_avatar_from(ProjectSettings.globalize_path("res://assets/ui/icon.png"))
	for lv in [3, 14, 27, 52]:
		Save.state.xp = Profile.xp_at(lv) + Profile.step(lv) / 3
		main._lobby()
		for f in 6:
			await get_tree().process_frame
		await _shot("p_lobby_%d" % lv)
	main._profile()
	for f in 6:
		await get_tree().process_frame
	await _shot("p_profile")
	Save.state.lang = "ar"
	I18n.set_lang("ar")
	main._profile()
	for f in 6:
		await get_tree().process_frame
	await _shot("p_profile_ar")
	Save.state.lang = "en"
	I18n.set_lang("en")
	main._confirm_exit()
	await get_tree().process_frame
	await _shot("p_exit")


func _lobby3d() -> void:
	await get_tree().create_timer(0.5).timeout
	var sr: Showroom = main.showroom
	for i in 4:
		sr._yaw = 0.55 + i * PI / 2
		sr._idle = 0.0
		sr._place_cam()
		for f in 30:
			await get_tree().process_frame
		await _shot("l3d_%d" % i)
	sr._pitch = 0.5
	sr._place_cam()
	for f in 10:
		await get_tree().process_frame
	await _shot("l3d_high")
	main._garage()
	for f in 10:
		await get_tree().process_frame
	await _shot("l3d_garage")
