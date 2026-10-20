extends Node
## App flow: lobby → garage / workshop / settings → match setup → loading → match → results.
## Screens are plain Control trees built in code from the shared UI kit; only one is shown at a time.

var showroom: Showroom
var ui_layer: CanvasLayer
var screen_root: Control
var game: Match
var hud: HUD
var pause_layer: CanvasLayer
var _last_cfg := {}
var _garage_pick := ""
var _setup := {"mode": "deathmatch", "map": 0, "diff": 0}


func _ready() -> void:
	UI.init()
	I18n.changed.connect(_refresh)
	showroom = Showroom.new()
	add_child(showroom)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	screen_root = UI.full(Control.new())
	screen_root.theme = UI.theme
	ui_layer.add_child(screen_root)
	get_tree().set_auto_accept_quit(false)
	_lobby()
	Sfx.music("lobby")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test=") and ResourceLoader.exists("res://tests/autotest.gd"):
			var t: Node = load("res://tests/autotest.gd").new()
			t.set("main", self)
			add_child(t)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if game and game.running:
			_pause()
		elif _current != "lobby":
			_lobby()
		else:
			get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED and game and game.running:
		_pause()


var _current := ""
var _rebuild: Callable


func _show(name: String, build: Callable) -> void:
	_current = name
	_rebuild = build
	for c in screen_root.get_children():
		c.queue_free()
	var root := UI.full(Control.new())
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL if I18n.is_ar() else Control.LAYOUT_DIRECTION_LTR
	screen_root.add_child(root)
	build.call(root)


func _refresh() -> void:
	if _rebuild.is_valid() and game == null:
		_show(_current, _rebuild)


func _t(s: String, v := {}) -> String:
	return I18n.t(s, v)


func _top_bar(root: Control, title: String, back := true) -> void:
	var bar := UI.hbox(14)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_right = -24
	bar.offset_top = 16
	if back:
		bar.add_child(UI.button("‹  " + _t("Back"), _lobby))
	var h := UI.heading(title, 34)
	bar.add_child(h)
	bar.add_child(UI.spacer())
	var pts := UI.panel(0.55)
	pts.add_child(UI.label("⚙ %d  %s" % [Save.state.points, _t("Scrap")], 22, UI.ACCENT_2, UI.font_head))
	bar.add_child(pts)
	root.add_child(bar)


# ---------- lobby ----------

func _lobby() -> void:
	if game:
		_end_game()
	showroom.activate(true)
	showroom.show_car(Save.state.selected)
	Sfx.music("lobby")
	_show("lobby", func(root: Control):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/ui/logo.png")
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		logo.position = Vector2(24, 12)
		logo.size = Vector2(300, 110)
		root.add_child(logo)
		_top_bar_points(root)
		var c: Dictionary = Save.selected_car()
		var info := UI.panel(0.55)
		info.position = Vector2(24, 128)
		info.custom_minimum_size = Vector2(340, 0)
		var v := UI.vbox(4)
		v.add_child(UI.label(_t("Your ride"), 16, UI.DIM, UI.font_head))
		v.add_child(UI.heading(c.name, 30))
		v.add_child(UI.label(_t(c.special.name).to_upper() + " · " + _t(c.cls).to_upper(), 16, UI.ACCENT_2, UI.font_head))
		var st := Data.car_stats(c, Save.upgrades(c.id))
		for row in [["Speed", c.stats.speed], ["Armor", c.stats.armor], ["Guns", c.stats.gun], ["Rockets", c.stats.rocket], ["Handling", c.stats.handling]]:
			var h := UI.hbox(10)
			var l := UI.label(_t(row[0]), 16, UI.TEXT)
			l.custom_minimum_size.x = 100
			h.add_child(l)
			h.add_child(UI.bar(row[1] / 10.0, UI.ACCENT, 180, 8))
			v.add_child(h)
		info.add_child(v)
		root.add_child(info)
		var menu := UI.vbox(12)
		menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		menu.offset_left = 24
		menu.offset_top = -170
		menu.offset_bottom = -24
		menu.custom_minimum_size.x = 300
		var play := UI.button(_t("PLAY"), _setup_screen, true, 32)
		play.custom_minimum_size = Vector2(340, 66)
		menu.add_child(play)
		var row := UI.hbox(10)
		for b in [["Garage", _garage], ["Upgrade", _workshop], ["Settings", _settings]]:
			var btn := UI.button(_t(b[0]), b[1])
			btn.custom_minimum_size.y = 56
			row.add_child(btn)
		menu.add_child(row)
		root.add_child(menu)
		_contracts_panel(root))


func _top_bar_points(root: Control) -> void:
	var pts := UI.panel(0.55)
	pts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pts.offset_left = -260
	pts.offset_right = -24
	pts.offset_top = 18
	pts.add_child(UI.label("⚙ %d  %s" % [Save.state.points, _t("Scrap")], 22, UI.ACCENT_2, UI.font_head))
	root.add_child(pts)


func _contracts_panel(root: Control) -> void:
	var p := UI.panel(0.5)
	p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	p.offset_left = -360
	p.offset_right = -24
	p.offset_top = -210
	p.offset_bottom = -24
	var v := UI.vbox(6)
	v.add_child(UI.label(_t("Daily contracts"), 16, UI.DIM, UI.font_head))
	for c in Save.contracts():
		var h := UI.hbox(8)
		var txt := UI.label(_t(c.text, {"n": c.goal, "map": _t(c.map_name)}), 16, UI.GOOD if c.done else UI.TEXT)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(txt)
		h.add_child(UI.label("%d/%d" % [c.progress, c.goal] if not c.done else "✓", 16, UI.ACCENT_2, UI.font_head))
		v.add_child(h)
	p.add_child(v)
	root.add_child(p)


# ---------- garage ----------

func _garage() -> void:
	_garage_pick = Save.state.selected
	_garage_view()


func _garage_view() -> void:
	showroom.show_car(_garage_pick)
	_show("garage", func(root: Control):
		_top_bar(root, _t("Garage"))
		var list := UI.vbox(8)
		var scroll := ScrollContainer.new()
		scroll.position = Vector2(24, 90)
		scroll.size = Vector2(300, 600)
		scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		scroll.offset_left = 24
		scroll.offset_right = 324
		scroll.offset_top = 90
		scroll.offset_bottom = -20
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		for c in Data.CARS:
			var owned := Save.owns(c.id)
			var label: String = c.name + ("" if owned else "   ⚙%d" % c.price)
			var b := UI.button(label, func():
				_garage_pick = c.id
				_garage_view(), c.id == _garage_pick, 20)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(280, 52)
			if not owned:
				b.modulate = Color(1, 1, 1, 0.75)
			list.add_child(b)
		scroll.add_child(list)
		root.add_child(scroll)
		var c: Dictionary = Data.car(_garage_pick)
		var p := UI.panel(0.55)
		p.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		p.offset_left = -420
		p.offset_right = -24
		p.offset_top = 90
		p.offset_bottom = -20
		var v := UI.vbox(8)
		v.add_child(UI.heading(c.name, 32))
		v.add_child(UI.label(_t(c.cls).to_upper(), 16, UI.ACCENT_2, UI.font_head))
		var d := UI.label(c.desc_ar if I18n.is_ar() else c.desc, 17, UI.TEXT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 360
		v.add_child(d)
		var sp := UI.label(_t(c.special.name) + ": " + _t(c.special.desc), 16, UI.GOOD)
		sp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sp.custom_minimum_size.x = 360
		v.add_child(sp)
		v.add_child(UI.label("+ " + _t(c.strong), 16, UI.TEXT))
		v.add_child(UI.label("− " + _t(c.weak), 16, UI.DIM))
		v.add_child(UI.spacer())
		if Save.owns(c.id):
			var sel := UI.button(_t("Selected") if Save.state.selected == c.id else _t("Select"), func():
				Save.select(c.id)
				_garage_view(), true)
			sel.disabled = Save.state.selected == c.id
			v.add_child(sel)
		else:
			var can: bool = Save.state.points >= c.price
			var buy := UI.button((_t("Buy") + "  ⚙%d" % c.price) if can else _t("Need {n}", {"n": c.price}), func():
				if Save.buy(c):
					Sfx.play("purchase")
				_garage_view(), true)
			buy.disabled = not can
			v.add_child(buy)
		p.add_child(v)
		root.add_child(p))


# ---------- workshop ----------

func _workshop() -> void:
	var c: Dictionary = Save.selected_car()
	showroom.show_car(c.id)
	_show("workshop", func(root: Control):
		_top_bar(root, _t("Workshop") + " · " + c.name)
		var p := UI.panel(0.6)
		p.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		p.offset_left = 24
		p.offset_right = 560
		p.offset_top = 96
		p.offset_bottom = -24
		var v := UI.vbox(12)
		var ups := Save.upgrades(c.id)
		for u in Data.UPGRADES:
			var lvl: int = ups[u.id]
			var row := UI.hbox(12)
			var col := UI.vbox(2)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(UI.label(_t(u.name), 22, UI.TEXT, UI.font_head))
			col.add_child(UI.label(_t(u.desc), 15, UI.DIM))
			var pips := UI.hbox(4)
			for i in Data.MAX_UPGRADE:
				pips.add_child(UI.bar(1.0 if i < lvl else 0.0, UI.ACCENT, 28, 8))
			col.add_child(pips)
			row.add_child(col)
			if lvl >= Data.MAX_UPGRADE:
				row.add_child(UI.label(_t("Max"), 20, UI.ACCENT_2, UI.font_head))
			else:
				var cost := Data.upgrade_cost(c, lvl)
				var b := UI.button("⚙%d" % cost, func():
					if Save.spend(cost):
						ups[u.id] += 1
						Save.write()
						Sfx.play("purchase")
					_workshop(), true, 20)
				b.disabled = Save.state.points < cost
				row.add_child(b)
			v.add_child(row)
		p.add_child(v)
		root.add_child(p))


# ---------- settings ----------

func _settings() -> void:
	_show("settings", func(root: Control):
		_top_bar(root, _t("Settings"))
		var scroll := ScrollContainer.new()
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.offset_left = 24
		scroll.offset_right = -24
		scroll.offset_top = 90
		scroll.offset_bottom = -16
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var p := UI.panel(0.62)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UI.vbox(14)
		v.add_child(_seg(_t("Language"), [["en", "English"], ["ar", "العربية"]], Save.state.lang, func(x):
			Save.state.lang = x
			Save.write()
			I18n.set_lang(x)))
		v.add_child(_seg(_t("Sound effects"), [[true, _t("On")], [false, _t("Off")]], Save.state.sound, func(x):
			Save.state.sound = x
			Save.write()
			Sfx.apply_settings()))
		v.add_child(_seg(_t("Music"), [[true, _t("On")], [false, _t("Off")]], Save.state.music, func(x):
			Save.state.music = x
			Save.write()
			Sfx.apply_settings()))
		for vk in [["master", "Volume"], ["music", "Music volume"], ["sfx", "Effects volume"]]:
			var h := UI.hbox(12)
			var l := UI.label(_t(vk[1]), 20)
			l.custom_minimum_size.x = 240
			h.add_child(l)
			var s := HSlider.new()
			s.min_value = 0
			s.max_value = 1
			s.step = 0.05
			s.value = Save.state.volume[vk[0]]
			s.custom_minimum_size = Vector2(320, 32)
			s.value_changed.connect(func(val):
				Save.state.volume[vk[0]] = val
				Sfx.apply_settings())
			s.drag_ended.connect(func(_c): Save.write())
			h.add_child(s)
			v.add_child(h)
		v.add_child(_seg(_t("Graphics"), [["auto", _t("Auto")], ["high", _t("High")], ["medium", _t("Medium")], ["low", _t("Low")]], Save.state.graphics, func(x):
			Save.state.graphics = x
			Save.write()
			Quality.apply_setting()))
		v.add_child(_seg(_t("Frame rate"), [[60, "60 FPS"], [30, _t("30 FPS · battery saver")]], int(Save.state.fps), func(x):
			Save.state.fps = x
			Save.write()
			Quality.apply_setting()))
		v.add_child(_seg(_t("Steering"), [["classic", _t("Classic")], ["direction", _t("Direction")], ["autogas", _t("Auto gas")]], Save.state.scheme, func(x):
			Save.state.scheme = x
			Save.write()))
		var credits := UI.label(_t("Credits") + "\n" + _t("Game by") + " Hussain Al-Akari\n" + _t("Environment art") + ": Post Apocalypse Kitbash · Oleg Ushenok (Fab)\n" \
			+ _t("Music") + ": THE COST · Kill Dyll\n" + _t("Visual effects") + ": Free VFX Flipbooks · Unity Labs (CC0)\n" \
			+ _t("Sound effects") + ": Freesound · qubodup, kodack, tommccann, mikewest, morganpurkis, zapsplat (CC0)\n" \
			+ _t("Fonts") + ": Saira · Omnibus-Type, Cairo · Mohamed Gaber (SIL OFL)\n" + _t("Engine") + ": Godot Engine (MIT)", 15, UI.DIM)
		credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(credits)
		p.add_child(v)
		scroll.add_child(p)
		root.add_child(scroll))


func _seg(title: String, opts: Array, cur, cb: Callable) -> Control:
	var h := UI.hbox(10)
	var l := UI.label(title, 20)
	l.custom_minimum_size.x = 240
	h.add_child(l)
	for o in opts:
		var b := UI.button(o[1], func():
			cb.call(o[0])
			_refresh(), o[0] == cur, 19)
		h.add_child(b)
	return h


# ---------- match setup ----------

func _setup_screen() -> void:
	_show("setup", func(root: Control):
		_top_bar(root, _t("Enter the arena"))
		var p := UI.panel(0.62)
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.offset_left = 24
		p.offset_right = -24
		p.offset_top = 90
		p.offset_bottom = -24
		var v := UI.vbox(16)
		v.add_child(_seg(_t("Mode"), [["deathmatch", _t("Deathmatch")], ["survival", _t("Survival")]], _setup.mode, func(x): _setup.mode = x))
		var maps := UI.hbox(10)
		for i in Data.MAPS.size():
			var m: Dictionary = Data.MAPS[i]
			var card := UI.vbox(4)
			var tex := TextureRect.new()
			tex.texture = load("res://assets/ui/maps/%s.jpg" % m.id)
			tex.custom_minimum_size = Vector2(190, 106)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			card.add_child(tex)
			var b := UI.button(_t(m.name), func():
				_setup.map = i
				_refresh(), _setup.map == i, 18)
			card.add_child(b)
			maps.add_child(card)
		var ms := ScrollContainer.new()
		ms.custom_minimum_size.y = 170
		ms.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		ms.add_child(maps)
		v.add_child(ms)
		if _setup.mode == "deathmatch":
			var opts: Array = []
			for i in Data.DIFFICULTY.size():
				opts.append([i, _t(Data.DIFFICULTY[i].name)])
			v.add_child(_seg(_t("Difficulty"), opts, _setup.diff, func(x): _setup.diff = x))
		v.add_child(UI.spacer())
		var go := UI.button(_t("FIGHT"), func():
			_start_match({"car": Save.selected_car(), "upgrades": Save.upgrades(Save.state.selected), "map": Data.MAPS[_setup.map],
				"diff": Data.DIFFICULTY[_setup.diff], "mode": _setup.mode}), true, 34)
		go.custom_minimum_size = Vector2(300, 70)
		go.size_flags_horizontal = Control.SIZE_SHRINK_END
		v.add_child(go)
		p.add_child(v)
		root.add_child(p))


# ---------- match lifecycle ----------

func _start_match(cfg: Dictionary) -> void:
	_last_cfg = cfg
	_show("loading", func(root: Control):
		var bg := UI.full(ColorRect.new())
		bg.color = Color(0.05, 0.045, 0.04)
		root.add_child(bg)
		var l := UI.heading(_t("Loading the arena…"), 34)
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
		root.add_child(l))
	Sfx.music_stop()
	await get_tree().process_frame
	await get_tree().process_frame
	showroom.activate(false)
	game = Match.new()
	hud = HUD.new()
	game.hud = hud
	add_child(hud)
	var ids: Array = [cfg.car.id]
	for c in Data.CARS:
		if c.price <= cfg.diff.max_price:
			ids.append(c.id)
	game.preload_assets(ids)
	add_child(game)
	game.finished.connect(_on_finished)
	hud.pause_pressed.connect(_pause)
	game.start(cfg)
	for c in screen_root.get_children():
		c.queue_free()
	_current = "game"


func _end_game() -> void:
	if game:
		game.quit()
		game.queue_free()
		game = null
	if hud:
		hud.queue_free()
		hud = null
	if pause_layer:
		pause_layer.queue_free()
		pause_layer = null
	get_tree().paused = false


func _pause() -> void:
	if pause_layer or game == null:
		return
	get_tree().paused = true
	Sfx.engine_stop()
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 20
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)
	var root := UI.full(Control.new())
	root.theme = UI.theme
	pause_layer.add_child(root)
	var dim := UI.full(ColorRect.new())
	dim.color = Color(0, 0, 0, 0.55)
	root.add_child(dim)
	var p := UI.panel(0.8)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := UI.vbox(14)
	v.add_child(UI.heading(_t("Paused"), 44))
	var resume := UI.button(_t("Resume"), _resume, true, 28)
	resume.custom_minimum_size = Vector2(320, 64)
	v.add_child(resume)
	v.add_child(UI.button(_t("Quit match"), func():
		get_tree().paused = false
		_lobby(), false, 24))
	p.add_child(v)
	root.add_child(p)


func _resume() -> void:
	get_tree().paused = false
	if pause_layer:
		pause_layer.queue_free()
		pause_layer = null
	if game:
		Sfx.engine_start(game.player.data.id)


func _on_finished(r: Dictionary) -> void:
	var cfg := _last_cfg
	var d: Dictionary = cfg.diff
	var surv: bool = r.mode == "survival"
	var kill_pts := int(round(r.kills * Data.KILL_REWARD * (1.2 if surv else d.reward)))
	var win_pts: int = d.base if r.result == "win" else 0
	var show_pts := 10 if r.result == "loss" else 0
	var bonus := 0
	for b in r.stats.bonus:
		bonus += b.pts
	var total := win_pts + kill_pts + show_pts + bonus
	var prev_best: int = Save.state.best.wave
	Save.record({"date": Time.get_datetime_string_from_system(), "map": cfg.map.name, "diff": "Survival" if surv else d.name, "car": cfg.car.name,
		"result": r.result, "kills": r.kills, "points": total, "wave": r.stats.wave if surv else 0})
	var done := Save.apply_contracts({"result": r.result, "map": cfg.map.id, "diff": "survival" if surv else d.id, "stats": r.stats})
	_end_game()
	showroom.activate(true)
	Sfx.music("lobby")
	_show("results", func(root: Control):
		var p := UI.panel(0.7)
		p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		p.grow_horizontal = Control.GROW_DIRECTION_BOTH
		p.grow_vertical = Control.GROW_DIRECTION_BOTH
		p.custom_minimum_size.x = 560
		var v := UI.vbox(8)
		var good: bool = r.result == "win" or (surv and r.stats.wave > prev_best)
		var title := UI.heading(_t("Wave {n}", {"n": r.stats.wave}) if surv else _t("Victory" if r.result == "win" else "Wrecked"), 52)
		title.add_theme_color_override("font_color", Color("ffd25a") if good else UI.BAD)
		v.add_child(title)
		v.add_child(UI.label("%s · %s · %s" % [_t(cfg.map.name), _t("Survival" if surv else d.name), cfg.car.name], 17, UI.DIM))
		var lines := [[_t("Time in arena"), "%d:%02d" % [int(r.time) / 60, int(r.time) % 60]], [_t("Kills"), "%d" % r.kills]]
		if r.result == "win":
			lines.append([_t("Victory bonus"), "+%d" % win_pts])
		elif show_pts:
			lines.append([_t("Show-up pay"), "+%d" % show_pts])
		lines.append([_t("Kill pay"), "+%d" % kill_pts])
		for b in r.stats.bonus:
			lines.append([_t(b.label, {"n": b.get("n", "")}), "+%d" % b.pts])
		for ln in lines:
			var h := UI.hbox(10)
			var a := UI.label(ln[0], 19)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(a)
			h.add_child(UI.label(ln[1], 19, UI.TEXT, UI.font_head))
			v.add_child(h)
		var tot := UI.hbox(10)
		var tl := UI.label(_t("Scrap earned"), 24, UI.ACCENT_2, UI.font_head)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tot.add_child(tl)
		tot.add_child(UI.label("+%d" % total, 24, UI.ACCENT_2, UI.font_head))
		v.add_child(tot)
		for c in done:
			v.add_child(UI.label(_t("Contract complete") + ": " + _t(c.text, {"n": c.goal, "map": _t(c.map_name)}) + "  +%d" % c.reward, 17, UI.GOOD))
		var row := UI.hbox(10)
		row.add_child(UI.button(_t("Lobby"), _lobby))
		row.add_child(UI.button(_t("Rematch"), func(): _start_match(cfg), true))
		v.add_child(row)
		p.add_child(v)
		root.add_child(p))
