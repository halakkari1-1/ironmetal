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
	get_tree().quit()


func _shot(name: String) -> void:
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
		for f in 20:
			await get_tree().process_frame
		await _shot("match_" + g.map.id)
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
