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


## Screen title bar: back button, title, scrap counter. Sized for reading at arm's length on a phone.
func _top_bar(root: Control, title: String, back := true) -> void:
	var bar := UI.hbox(16)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_right = -24
	bar.offset_top = 14
	if back:
		var b := UI.button("‹  " + _t("Back"), _lobby, false, 28)
		b.custom_minimum_size = Vector2(150, 66)
		bar.add_child(b)
	bar.add_child(UI.heading(title, 44))
	bar.add_child(UI.spacer())
	bar.add_child(_points_pill())
	root.add_child(bar)


func _points_pill() -> Control:
	var pts := UI.panel(0.6)
	pts.add_child(UI.label("⚙ %d  %s" % [Save.state.points, _t("Scrap")], 28, UI.ACCENT_2, UI.font_head))
	return pts


## A row of choices with a label in front; the chosen one is highlighted.
func _seg(title: String, opts: Array, cur, cb: Callable, label_w := 260.0) -> Control:
	var h := UI.hbox(12)
	var l := UI.label(title, 26)
	l.custom_minimum_size.x = label_w
	h.add_child(l)
	for o in opts:
		var b := UI.button(o[1], func():
			cb.call(o[0])
			_refresh(), o[0] == cur, 24)
		b.custom_minimum_size.y = 60
		h.add_child(b)
	return h


func _scroll(root: Control, left: float, top: float, right: float, bottom: float) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = left
	sc.offset_top = top
	sc.offset_right = right
	sc.offset_bottom = bottom
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 12   # a finger drag anywhere scrolls; a tap still presses buttons
	root.add_child(sc)
	return sc


# ---------- lobby ----------

func _lobby() -> void:
	if game:
		_end_game()
	showroom.activate(true)
	showroom.show_car(Save.state.selected)
	_focus_right_of(470)
	Sfx.music("lobby")
	_show("lobby", func(root: Control):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/ui/logo.png")
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		logo.position = Vector2(20, 10)
		logo.size = Vector2(130, 130)
		root.add_child(logo)
		var top := UI.vbox(10)
		top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		top.offset_left = -430
		top.offset_right = -24
		top.offset_top = 16
		var pill := _points_pill()
		pill.size_flags_horizontal = Control.SIZE_SHRINK_END
		top.add_child(pill)
		top.add_child(_contracts_panel())
		root.add_child(top)
		var c: Dictionary = Save.selected_car()
		var info := UI.panel(0.6)
		info.position = Vector2(24, 150)
		info.custom_minimum_size = Vector2(400, 0)
		var v := UI.vbox(6)
		v.add_child(UI.heading(c.name, 38))
		v.add_child(UI.label(_t(c.special.name).to_upper() + " · " + _t(c.cls).to_upper(), 22, UI.ACCENT_2, UI.font_head))
		for row in [["Speed", c.stats.speed], ["Armor", c.stats.armor], ["Guns", c.stats.gun], ["Rockets", c.stats.rocket], ["Handling", c.stats.handling]]:
			var h := UI.hbox(12)
			var l := UI.label(_t(row[0]), 22)
			l.custom_minimum_size.x = 130
			h.add_child(l)
			h.add_child(UI.bar(row[1] / 10.0, UI.ACCENT, 220, 12))
			v.add_child(h)
		info.add_child(v)
		root.add_child(info)
		var menu := UI.vbox(12)
		menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		menu.offset_left = 24
		menu.offset_top = -176
		menu.offset_bottom = -20
		var play := UI.button(_t("PLAY"), _setup_screen, true, 40)
		play.custom_minimum_size = Vector2(470, 84)
		menu.add_child(play)
		var row := UI.hbox(12)
		for b in [["Garage", _garage], ["Upgrade", _workshop], ["Settings", _settings]]:
			var btn := UI.button(_t(b[0]), b[1], false, 26)
			btn.custom_minimum_size = Vector2(148, 68)
			row.add_child(btn)
		menu.add_child(row)
		root.add_child(menu))


## Centres the car in the free space to the right of a panel that ends at `px`.
func _focus_right_of(px: float) -> void:
	var w := get_viewport().get_visible_rect().size.x
	# Arabic mirrors the screens, so the panels sit on the right and the car goes to the left
	showroom.set_focus((w - px) / 2.0 if I18n.is_ar() else (px + w) / 2.0)


func _contracts_panel() -> Control:
	var p := UI.panel(0.55)
	var v := UI.vbox(6)
	v.add_child(UI.label(_t("Daily contracts"), 22, UI.DIM, UI.font_head))
	for c in Save.contracts():
		var h := UI.hbox(8)
		var txt := UI.label(_t(c.text, {"n": c.goal, "map": _t(c.map_name)}), 21, UI.GOOD if c.done else UI.TEXT)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(txt)
		h.add_child(UI.label("%d/%d" % [c.progress, c.goal] if not c.done else "✓", 21, UI.ACCENT_2, UI.font_head))
		v.add_child(h)
	p.add_child(v)
	return p


# ---------- garage ----------
# Everything sits on the left half, so the car on the painted ring (right half) is never covered.

func _garage() -> void:
	_garage_pick = Save.state.selected
	_garage_view()


func _garage_view() -> void:
	showroom.show_car(_garage_pick)
	_focus_right_of(336 + 430)
	_show("garage", func(root: Control):
		_top_bar(root, _t("Garage"))
		var sc := _scroll(root, 24, 96, 0, -16)
		sc.anchor_right = 0.0
		sc.offset_right = 24 + 300
		var list := UI.vbox(10)
		for c in Data.CARS:
			var owned := Save.owns(c.id)
			var b := UI.button(c.name, func():
				_garage_pick = c.id
				_garage_view(), c.id == _garage_pick, 24)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(290, 66)
			if not owned:
				b.text = c.name + "\n⚙ %d" % c.price
				b.add_theme_font_size_override("font_size", 21)
				b.modulate = Color(1, 1, 1, 0.8)
			list.add_child(b)
		sc.add_child(list)
		var c: Dictionary = Data.car(_garage_pick)
		var p := UI.panel(0.68)
		p.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		p.offset_left = 336
		p.offset_right = 336 + 430
		p.offset_top = 96
		p.offset_bottom = -16
		var col := UI.vbox(10)
		var info := ScrollContainer.new()
		info.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		info.scroll_deadzone = 12
		info.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(info)
		var v := UI.vbox(10)
		v.custom_minimum_size.x = 390
		v.add_child(UI.heading(c.name, 36))
		v.add_child(UI.label(_t(c.cls).to_upper() + " · " + _t(c.special.name).to_upper(), 22, UI.ACCENT_2, UI.font_head))
		for row in [["Speed", c.stats.speed], ["Armor", c.stats.armor], ["Guns", c.stats.gun], ["Rockets", c.stats.rocket], ["Handling", c.stats.handling]]:
			var h := UI.hbox(12)
			var l := UI.label(_t(row[0]), 21)
			l.custom_minimum_size.x = 120
			h.add_child(l)
			h.add_child(UI.bar(row[1] / 10.0, UI.ACCENT, 230, 12))
			v.add_child(h)
		var sp := UI.label(_t(c.special.desc), 21, UI.GOOD)
		sp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sp)
		var d := UI.label(c.desc_ar if I18n.is_ar() else c.desc, 21, UI.TEXT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		v.add_child(UI.label("+ " + _t(c.strong), 21, UI.TEXT))
		v.add_child(UI.label("− " + _t(c.weak), 21, UI.DIM))
		info.add_child(v)
		var act: Button
		if Save.owns(c.id):
			act = UI.button(_t("Selected") if Save.state.selected == c.id else _t("Select"), func():
				Save.select(c.id)
				_garage_view(), true, 30)
			act.disabled = Save.state.selected == c.id
		else:
			var can: bool = Save.state.points >= c.price
			act = UI.button((_t("Buy") + "  ⚙ %d" % c.price) if can else _t("Need {n}", {"n": c.price}), func():
				if Save.buy(c):
					Sfx.play("purchase")
				_garage_view(), true, 30)
			act.disabled = not can
		act.custom_minimum_size = Vector2(0, 74)
		col.add_child(act)
		p.add_child(col)
		root.add_child(p))


# ---------- workshop ----------

func _workshop() -> void:
	var c: Dictionary = Save.selected_car()
	showroom.show_car(c.id)
	_focus_right_of(24 + 560)
	_show("workshop", func(root: Control):
		_top_bar(root, _t("Workshop"))
		var p := UI.panel(0.68)
		p.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		p.offset_left = 24
		p.offset_right = 24 + 560
		p.offset_top = 96
		p.offset_bottom = -16
		var sc := _scroll(p, 0, 0, 0, 0)
		var v := UI.vbox(14)
		v.custom_minimum_size.x = 520
		v.add_child(UI.heading(c.name, 34))
		var ups := Save.upgrades(c.id)
		for u in Data.UPGRADES:
			var lvl: int = ups[u.id]
			var row := UI.hbox(14)
			var col := UI.vbox(4)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(UI.label(_t(u.name), 28, UI.TEXT, UI.font_head))
			col.add_child(UI.label(_t(u.desc), 20, UI.DIM))
			var pips := UI.hbox(6)
			for i in Data.MAX_UPGRADE:
				pips.add_child(UI.bar(1.0 if i < lvl else 0.0, UI.ACCENT, 46, 12))
			col.add_child(pips)
			row.add_child(col)
			if lvl >= Data.MAX_UPGRADE:
				row.add_child(UI.label(_t("Max"), 28, UI.ACCENT_2, UI.font_head))
			else:
				var cost := Data.upgrade_cost(c, lvl)
				var b := UI.button("⚙ %d" % cost, func():
					if Save.spend(cost):
						ups[u.id] += 1
						Save.write()
						Sfx.play("purchase")
					_workshop(), true, 26)
				b.custom_minimum_size = Vector2(150, 66)
				b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				b.disabled = Save.state.points < cost
				row.add_child(b)
			v.add_child(row)
		sc.add_child(v)
		root.add_child(p))


# ---------- settings ----------

func _settings() -> void:
	_show("settings", func(root: Control):
		_top_bar(root, _t("Settings"))
		var p := UI.panel(0.7)
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.offset_left = 24
		p.offset_right = -24
		p.offset_top = 96
		p.offset_bottom = -16
		var sc := _scroll(p, 0, 0, 0, 0)
		var v := UI.vbox(18)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
			var h := UI.hbox(16)
			var l := UI.label(_t(vk[1]), 26)
			l.custom_minimum_size.x = 260
			h.add_child(l)
			var s := UI.slider(Save.state.volume[vk[0]], 0.0, 1.0, func(val):
				Save.state.volume[vk[0]] = val
				Sfx.apply_settings(), func(): Save.write())
			h.add_child(s)
			var pct := UI.label("%d%%" % roundi(Save.state.volume[vk[0]] * 100), 24, UI.ACCENT_2, UI.font_head)
			pct.custom_minimum_size.x = 70
			s.value_changed.connect(func(val): pct.text = "%d%%" % roundi(val * 100))
			h.add_child(pct)
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
		var ctl := UI.hbox(12)
		var cl := UI.label(_t("Controls"), 26)
		cl.custom_minimum_size.x = 260
		ctl.add_child(cl)
		var edit := UI.button(_t("Edit button size and position"), _controls_editor, true, 24)
		edit.custom_minimum_size.y = 60
		ctl.add_child(edit)
		v.add_child(ctl)
		var credits := UI.label(_t("Credits") + "\n" + _t("Game by") + " Hussain Al-Akari\n" \
			+ _t("Environment art") + ": Post Apocalypse Kitbash · Oleg Ushenok (Fab)\n" \
			+ _t("Music") + ": THE COST · Kill Dyll\n" \
			+ _t("Visual effects") + ": CGHeven (CC0) · Unity Labs (CC0)\n" \
			+ _t("Sound effects") + ": Freesound · CGEffex, EvanBoyerman, Iwiploppenisse, Zagge28, Henaway, kyles, qubodup, kodack, tommccann, mikewest, zapsplat\n" \
			+ _t("Fonts") + ": Saira · Omnibus-Type, Cairo · Mohamed Gaber (SIL OFL)\n" + _t("Engine") + ": Godot Engine (MIT)", 19, UI.DIM)
		credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(credits)
		sc.add_child(v)
		root.add_child(p))


## Drag the buttons where you want them, pick one and size it with the slider; saved for every match.
func _controls_editor() -> void:
	var editor := ControlsEditor.new()
	editor.done.connect(func():
		editor.queue_free()
		_settings())
	_show("controls", func(root: Control): root.add_child(editor))


# ---------- match setup ----------

const DIFF_INFO := [
	{"name": "Easy", "cars": "Cheapest cars only", "aim": "Weak aim"},
	{"name": "Medium", "cars": "Cars up to Rex", "aim": "Good aim"},
	{"name": "Hard", "cars": "Every car", "aim": "Sharp aim"},
]


func _setup_screen() -> void:
	_show("setup", func(root: Control):
		_top_bar(root, _t("Enter the arena"))
		var col := UI.vbox(16)
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 24
		col.offset_right = -24
		col.offset_top = 96
		col.offset_bottom = -16
		# mode
		var modes := UI.hbox(14)
		for m in [["deathmatch", "Deathmatch", "Last car running wins"], ["survival", "Survival", "Endless waves hunt you"]]:
			modes.add_child(_card(_t(m[1]), _t(m[2]), _setup.mode == m[0], func():
				_setup.mode = m[0]
				_refresh()))
		col.add_child(modes)
		# maps
		var maps := UI.hbox(12)
		for i in Data.MAPS.size():
			var m: Dictionary = Data.MAPS[i]
			var card := _map_card(m, _setup.map == i, func():
				_setup.map = i
				_refresh())
			maps.add_child(card)
		col.add_child(maps)
		# difficulty and fight
		var bottom := UI.hbox(14)
		bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if _setup.mode == "deathmatch":
			for i in Data.DIFFICULTY.size():
				var d: Dictionary = Data.DIFFICULTY[i]
				var info: Dictionary = DIFF_INFO[i]
				var lines := "%s\n%s\n%s" % [_t("{n} enemy cars", {"n": d.enemies}), _t(info.cars), _t(info.aim)]
				bottom.add_child(_card(_t(info.name), lines, _setup.diff == i, func():
					_setup.diff = i
					_refresh()))
		else:
			bottom.add_child(_card(_t("Survival"), _t("Waves get bigger and tougher. How long can you last?"), true, func(): pass))
		var go := UI.button(_t("FIGHT"), func():
			_start_match({"car": Save.selected_car(), "upgrades": Save.upgrades(Save.state.selected), "map": Data.MAPS[_setup.map],
				"diff": Data.DIFFICULTY[_setup.diff], "mode": _setup.mode}), true, 44)
		go.custom_minimum_size = Vector2(260, 0)
		go.size_flags_vertical = Control.SIZE_EXPAND_FILL
		go.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
		bottom.add_child(go)
		col.add_child(bottom)
		root.add_child(col))


## A large selectable card: title and a few lines of detail.
func _card(title: String, detail: String, on: bool, cb: Callable) -> Control:
	var b := UI.button("", cb, on, 24)
	b.custom_minimum_size = Vector2(0, 110)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_right = -18
	v.offset_top = 10
	v.offset_bottom = -10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UI.label(title, 32, Color.WHITE, UI.font_head)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := UI.label(detail, 20, Color(1, 1, 1, 0.9) if on else UI.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	b.add_child(v)
	return b


func _map_card(m: Dictionary, on: bool, cb: Callable) -> Control:
	var b := UI.button("", cb, on, 22)
	b.custom_minimum_size = Vector2(0, 190)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(6)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_right = -8
	v.offset_top = 8
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := TextureRect.new()
	tex.texture = load("res://assets/ui/maps/%s.jpg" % m.id)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tex)
	var l := UI.label(_t(m.name), 24, Color.WHITE, UI.font_head)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	b.add_child(v)
	return b


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
	v.add_child(UI.heading(_t("Paused"), 52))
	var resume := UI.button(_t("Resume"), _resume, true, 34)
	resume.custom_minimum_size = Vector2(380, 80)
	v.add_child(resume)
	var quit := UI.button(_t("Quit match"), func():
		get_tree().paused = false
		_lobby(), false, 28)
	quit.custom_minimum_size = Vector2(380, 70)
	v.add_child(quit)
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
		p.custom_minimum_size.x = 660
		var v := UI.vbox(8)
		var good: bool = r.result == "win" or (surv and r.stats.wave > prev_best)
		var title := UI.heading(_t("Wave {n}", {"n": r.stats.wave}) if surv else _t("Victory" if r.result == "win" else "Wrecked"), 60)
		title.add_theme_color_override("font_color", Color("ffd25a") if good else UI.BAD)
		v.add_child(title)
		v.add_child(UI.label("%s · %s · %s" % [_t(cfg.map.name), _t("Survival" if surv else d.name), cfg.car.name], 22, UI.DIM))
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
			var a := UI.label(ln[0], 24)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(a)
			h.add_child(UI.label(ln[1], 24, UI.TEXT, UI.font_head))
			v.add_child(h)
		var tot := UI.hbox(10)
		var tl := UI.label(_t("Scrap earned"), 30, UI.ACCENT_2, UI.font_head)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tot.add_child(tl)
		tot.add_child(UI.label("+%d" % total, 30, UI.ACCENT_2, UI.font_head))
		v.add_child(tot)
		for c in done:
			v.add_child(UI.label(_t("Contract complete") + ": " + _t(c.text, {"n": c.goal, "map": _t(c.map_name)}) + "  +%d" % c.reward, 22, UI.GOOD))
		var row := UI.hbox(10)
		for b in [UI.button(_t("Lobby"), _lobby, false, 28), UI.button(_t("Rematch"), func(): _start_match(cfg), true, 28)]:
			b.custom_minimum_size = Vector2(220, 70)
			row.add_child(b)
		v.add_child(row)
		p.add_child(v)
		root.add_child(p))
