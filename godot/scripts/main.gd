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
var _mp_status := ""
var _intro: Intro
var _mp_ip := ""


func _ready() -> void:
	UI.init()
	I18n.changed.connect(_refresh)
	showroom = Showroom.new()
	showroom.blocks = _ui_at
	add_child(showroom)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	screen_root = UI.full(Control.new())
	screen_root.theme = UI.theme
	ui_layer.add_child(screen_root)
	get_tree().set_auto_accept_quit(false)
	Net.lobby_changed.connect(func():
		if _current == "mp_home" and Net.role == "client" and not Net.lobby.is_empty():
			_mp_status = ""
			_mp_room()
		elif _current == "mp_room":
			_mp_room())
	Net.rooms_changed.connect(func():
		if _current == "mp_home":
			_mp_home())
	Net.status.connect(func(t: String):
		_mp_status = t
		if _current == "mp_home" or _current == "mp_room":
			_mp_home())
	Net.start_match.connect(_start_net_match)
	Net.session_over.connect(_on_session_over)
	var test := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			test = a.substr(7)
	if test == "" or test == "intro":
		_intro = Intro.new()
		_intro.name = "Intro"
		add_child(_intro)
		_intro.done.connect(func():
			_intro = null
			Sfx.music("lobby"))
	_lobby()
	if test != "" and test != "intro":
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
		elif _current == "mp_room":
			Net.leave()
			_mp_home()
		elif _current != "lobby":
			_lobby()
		else:
			_confirm_exit()
	elif what == NOTIFICATION_APPLICATION_PAUSED and game and game.running and not Net.active():
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
func _top_bar(root: Control, title: String, back := true, back_cb := Callable()) -> void:
	var bar := UI.hbox(16)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_right = -24
	bar.offset_top = 14
	if back:
		var b := UI.button("‹  " + _t("Back"), back_cb if back_cb.is_valid() else _lobby, false, 28)
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
	if Net.active():
		Net.leave()
	Net.browse(false)
	showroom.activate(true)
	showroom.show_car(Save.state.selected)
	_focus_right_of(470)
	if _intro == null:
		Sfx.music("lobby")
	_show("lobby", func(root: Control):
		var card := _profile_card()
		card.position = Vector2(24, 12)
		root.add_child(card)
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
		var top_row := UI.hbox(12)
		var play := UI.button(_t("PLAY"), _setup_screen, true, 40)
		play.custom_minimum_size = Vector2(250, 84)
		top_row.add_child(play)
		var mp := UI.button(_t("MULTIPLAYER"), func(): _ask_name(_mp_home), true, 28)
		mp.custom_minimum_size = Vector2(208, 84)
		top_row.add_child(mp)
		menu.add_child(top_row)
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
		var nm := UI.hbox(12)
		var nl := UI.label(_t("Player name"), 26)
		nl.custom_minimum_size.x = 260
		nm.add_child(nl)
		var nb := UI.button(Save.player_name() + "   ✎", func(): _name_screen(_settings), false, 24)
		nb.custom_minimum_size.y = 60
		nm.add_child(nb)
		v.add_child(nm)
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
		if c.price <= cfg.diff.max_price or cfg.has("roster"):
			ids.append(c.id)
	game.preload_assets(ids)
	add_child(game)
	game.finished.connect(_on_finished)
	hud.pause_pressed.connect(_pause)
	game.start(cfg)
	for c in screen_root.get_children():
		c.queue_free()
	_current = "game"
	if cfg.has("roster"):
		Net.match_ready(game)


## Multiplayer: the host started a match; build it from the shared roster.
func _start_net_match(cfg: Dictionary) -> void:
	if game:
		_end_game(false)
	var me := Net.me()
	_start_match({"map": Data.MAPS[cfg.map], "diff": Data.DIFFICULTY[cfg.diff], "mode": cfg.mode, "roster": cfg.roster,
		"role": Net.role, "me": Net.my_peer(), "upgrades": cfg.upgrades, "car": Data.car(me.get("car", Save.state.selected))})


func _end_game(leave_room := true) -> void:
	if game and Net.active():
		Net.match_over()
		if leave_room and game.running:
			Net.leave()
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
	if not Net.active():   # a shared match keeps running for everyone else
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
	var resume := UI.button(_t("Back to the fight") if Net.active() else _t("Resume"), _resume, true, 34)
	resume.custom_minimum_size = Vector2(380, 80)
	v.add_child(resume)
	var quit := UI.button(_t("Leave the room") if Net.active() else _t("Quit match"), func():
		get_tree().paused = false
		_lobby(), false, 28)
	quit.custom_minimum_size = Vector2(380, 70)
	v.add_child(quit)
	p.add_child(v)
	root.add_child(p)


func _resume() -> void:
	var was_paused := get_tree().paused
	get_tree().paused = false
	if pause_layer:
		pause_layer.queue_free()
		pause_layer = null
	if game and was_paused:
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
	var net: bool = r.get("net", false) and Net.active()
	var lv := Profile.award(r.result, r.kills, r.stats.wave if surv else 0, r.get("net", false))
	_end_game(false)
	showroom.activate(true)
	_focus_right_of(24 + 620)
	Sfx.music("lobby")
	_show("results", func(root: Control):
		# a full-height column on the left: the car stays in view, the list scrolls, the buttons never fall off
		var p := UI.panel(0.72)
		p.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		p.offset_left = 24
		p.offset_right = 24 + 620
		p.offset_top = 16
		p.offset_bottom = -16
		if net:
			root.add_child(_standings(r.ranking))
		var outer := UI.vbox(10)
		var v := UI.vbox(6)
		var good: bool = r.result == "win" or (surv and r.stats.wave > prev_best)
		var title := UI.heading(_t("Wave {n}", {"n": r.stats.wave}) if surv else _t("Victory" if r.result == "win" else "Wrecked"), 60)
		title.add_theme_color_override("font_color", Color("ffd25a") if good else UI.BAD)
		outer.add_child(title)
		outer.add_child(UI.label("%s · %s · %s" % [_t(cfg.map.name), _t("Survival" if surv else d.name), cfg.car.name], 22, UI.DIM))
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.scroll_deadzone = 12
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(v)
		outer.add_child(sc)
		var lines := [[_t("Time in arena"), "%d:%02d" % [int(r.time) / 60, int(r.time) % 60]], [_t("Kills"), "%d" % r.kills]]
		if r.result == "win":
			lines.append([_t("Victory bonus"), "+%d" % win_pts])
		elif show_pts:
			lines.append([_t("Show-up pay"), "+%d" % show_pts])
		lines.append([_t("Kill pay"), "+%d" % kill_pts])
		var merged := {}   # the same bonus twice reads "Double Wreck ×2"
		var order: Array = []
		for b in r.stats.bonus:
			var key: String = _t(b.label, {"n": b.get("n", "")})
			if not merged.has(key):
				merged[key] = [0, 0]
				order.append(key)
			merged[key][0] += 1
			merged[key][1] += b.pts
		for key in order:
			lines.append([key + ("  ×%d" % merged[key][0] if merged[key][0] > 1 else ""), "+%d" % merged[key][1]])
		for ln in lines:
			var h := UI.hbox(10)
			var a := UI.label(ln[0], 22)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(a)
			h.add_child(UI.label(ln[1], 22, UI.TEXT, UI.font_head))
			v.add_child(h)
		var tot := UI.hbox(10)
		var tl := UI.label(_t("Scrap earned"), 30, UI.ACCENT_2, UI.font_head)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tot.add_child(tl)
		tot.add_child(UI.label("+%d" % total, 30, UI.ACCENT_2, UI.font_head))
		v.add_child(tot)
		for c in done:
			var cl := UI.label(_t("Contract complete") + ": " + _t(c.text, {"n": c.goal, "map": _t(c.map_name)}) + "  +%d" % c.reward, 21, UI.GOOD)
			cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(cl)
		var xp_row := UI.hbox(10)
		var xl := UI.label(_t("Experience"), 24)
		xl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xp_row.add_child(xl)
		xp_row.add_child(UI.label("+%d XP" % lv.xp, 24, Color("8fc4ff"), UI.font_head))
		v.add_child(xp_row)
		if lv.to > lv.from:
			var nt: Dictionary = Profile.tier_of(lv.to)
			var up := UI.label(_t("LEVEL UP!") + "  " + _t("Level {n}", {"n": lv.to}), 30, nt.color, UI.font_head)
			if Profile.tier_of(lv.from).id != nt.id:
				up.text += "  ·  " + _t("New rank") + ": " + _t(nt.name)
			up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(up)
		var row := UI.hbox(10)
		var again := UI.button(_t("Back to the room"), _mp_room, true, 28) if net else UI.button(_t("Rematch"), func(): _start_match(cfg), true, 28)
		for b in [UI.button(_t("Lobby"), _lobby, false, 28), again]:
			b.custom_minimum_size = Vector2(0, 70)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
		outer.add_child(row)
		p.add_child(outer)
		root.add_child(p))


# ---------- multiplayer ----------

func _ask_name(next: Callable) -> void:
	if str(Save.state.get("player_name", "")).strip_edges() == "":
		_name_screen(next)
	else:
		next.call()


## Your name and colour, shown above your car and in rooms.
func _name_screen(next: Callable) -> void:
	_show("name", func(root: Control):
		_top_bar(root, _t("Your player name"), true, next)
		var p := UI.panel(0.75)
		p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		p.grow_horizontal = Control.GROW_DIRECTION_BOTH
		p.grow_vertical = Control.GROW_DIRECTION_BOTH
		var v := UI.vbox(18)
		v.custom_minimum_size.x = 640
		v.add_child(UI.label(_t("Other players see this name above your car."), 24, UI.DIM))
		var edit := LineEdit.new()
		edit.text = str(Save.state.get("player_name", ""))
		edit.placeholder_text = Save.player_name()
		edit.max_length = 16
		edit.custom_minimum_size = Vector2(0, 72)
		edit.add_theme_font_size_override("font_size", 32)
		v.add_child(edit)
		v.add_child(UI.label(_t("Colour"), 24))
		var row := UI.hbox(10)
		for i in Net.COLORS.size():
			var b := UI.button("●" if i == int(Save.state.player_color) else "", func():
				Save.state.player_color = i
				Save.state.player_name = edit.text.strip_edges()
				_name_screen(next), false, 30)
			b.custom_minimum_size = Vector2(60, 60)
			var sb := UI._flat(Color(Net.COLORS[i]), 30, 3 if i == int(Save.state.player_color) else 0, Color.WHITE)
			for st in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(st, sb)
			row.add_child(b)
		v.add_child(row)
		var ok := UI.button(_t("Save"), func():
			var n := edit.text.strip_edges()
			if n.length() < 2:
				edit.placeholder_text = _t("At least 2 letters")
				return
			Save.state.player_name = n.substr(0, 16)
			Save.write()
			next.call(), true, 30)
		ok.custom_minimum_size = Vector2(0, 76)
		v.add_child(ok)
		p.add_child(v)
		root.add_child(p))


## Find a room on this network, open one, or type a room's address.
func _mp_home() -> void:
	if Net.role == "host" or (Net.role == "client" and not Net.lobby.is_empty()):
		Net.leave()
	Net.browse(true)
	showroom.show_car(Save.state.selected)
	_show("mp_home", func(root: Control):
		_top_bar(root, _t("Multiplayer"))
		var left := UI.panel(0.7)
		left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		left.offset_left = 24
		left.offset_right = 24 + 560
		left.offset_top = 96
		left.offset_bottom = -16
		var v := UI.vbox(16)
		var me := UI.hbox(12)
		var dot := UI.label("●", 30, Color(Net.COLORS[int(Save.state.player_color) % Net.COLORS.size()]))
		me.add_child(dot)
		var nm := UI.label(Save.player_name(), 30, UI.TEXT, UI.font_head)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		me.add_child(nm)
		var edit_b := UI.button(_t("Edit"), func(): _name_screen(_mp_home), false, 24)
		edit_b.custom_minimum_size = Vector2(120, 60)
		me.add_child(edit_b)
		v.add_child(me)
		var create := UI.button(_t("CREATE A ROOM"), func():
			Net.browse(false)
			if Net.host():
				_mp_room()
			else:
				_mp_home(), true, 34)
		create.custom_minimum_size = Vector2(0, 90)
		v.add_child(create)
		v.add_child(UI.label(_t("Join by address"), 24, UI.DIM))
		var row := UI.hbox(10)
		var ip := LineEdit.new()
		ip.text = _mp_ip
		ip.placeholder_text = "192.168.1.5"
		ip.custom_minimum_size = Vector2(0, 66)
		ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ip.add_theme_font_size_override("font_size", 28)
		ip.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
		ip.text_changed.connect(func(t): _mp_ip = t)
		row.add_child(ip)
		var jb := UI.button(_t("Join"), func():
			if _mp_ip.strip_edges() != "":
				Net.join(_mp_ip), false, 26)
		jb.custom_minimum_size = Vector2(130, 66)
		row.add_child(jb)
		v.add_child(row)
		var ips := Net.local_ips()
		v.add_child(UI.label(_t("This phone") + ": " + (", ".join(ips) if ips.size() else _t("not on a Wi-Fi network")), 21, UI.DIM))
		if _mp_status != "":
			var st := UI.label(_mp_status, 23, UI.ACCENT_2)
			st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(st)
		left.add_child(v)
		root.add_child(left)
		var right := UI.panel(0.62)
		right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		right.offset_left = 24 + 560 + 16
		right.offset_right = -24
		right.offset_top = 96
		right.offset_bottom = -16
		var col := UI.vbox(12)
		col.add_child(UI.heading(_t("Rooms nearby"), 32))
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.scroll_deadzone = 12
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var list := UI.vbox(10)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if Net.rooms.is_empty():
			var hint := UI.label(_t("Looking for rooms…") + "\n\n" + _t("Both phones need to be on the same Wi-Fi, or one phone on the other's hotspot. If a room doesn't show up, type the address shown in that room."), 22, UI.DIM)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(hint)
		for addr in Net.rooms:
			var r: Dictionary = Net.rooms[addr]
			var ok: bool = int(r.get("p", 0)) == Net.PROTO and r.get("open", true) and int(r.get("n", 0)) < int(r.get("max", 9))
			var mode_name: String = {"deathmatch": "Deathmatch", "team": "Team battle", "survival": "Co-op survival"}.get(r.get("mode", ""), "")
			var map_name: String = Data.MAPS[clamp(int(r.get("map", 0)), 0, Data.MAPS.size() - 1)].name
			var text := "%s\n%s · %s · %d/%d" % [str(r.get("name", "?")), _t(mode_name), _t(map_name), int(r.get("n", 0)), int(r.get("max", 9))]
			if int(r.get("p", 0)) != Net.PROTO:
				text += "  · " + _t("different version")
			elif not r.get("open", true):
				text += "  · " + _t("in a match")
			var b := UI.button(text, func(): Net.join(addr), ok, 24)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, 92)
			b.disabled = not ok
			list.add_child(b)
		sc.add_child(list)
		col.add_child(sc)
		right.add_child(col)
		root.add_child(right))


const MODES := [["deathmatch", "Deathmatch"], ["team", "Team battle"], ["survival", "Co-op survival"]]
const TEAM_NAMES := {0: "", 1: "RED", 2: "BLUE"}


## The room: who's in, which car each drives, and (for the host) the match settings and the start button.
func _mp_room() -> void:
	if Net.lobby.is_empty():
		_mp_home()
		return
	showroom.show_car(Net.me().get("car", Save.state.selected))
	_show("mp_room", func(root: Control):
		var L: Dictionary = Net.lobby
		var host := Net.is_host()
		var mine := Net.me()
		_top_bar(root, _t("Room"), true, func():
			Net.leave()
			_mp_home())
		# players
		var left := UI.panel(0.7)
		left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		left.offset_left = 24
		left.offset_right = 24 + 520
		left.offset_top = 96
		left.offset_bottom = -16
		var lc := UI.vbox(10)
		lc.add_child(UI.heading(_t("Players") + "  %d/%d" % [L.players.size(), Net.MAX_PLAYERS], 30))
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.scroll_deadzone = 12
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var pl := UI.vbox(8)
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for p in L.players:
			var row := UI.hbox(10)
			row.add_child(UI.label("●", 28, Color(p.color)))
			var nm := UI.vbox(0)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var tag := ("  · " + _t("HOST")) if p.peer == 1 else ""
			var top := UI.hbox(8)
			top.add_child(UI.label(str(p.name) + tag, 26, UI.TEXT, UI.font_head))
			var plv: int = int(p.get("lv", 1))
			top.add_child(UI.label(_t("LV") + " %d" % plv, 20, Profile.tier_of(plv).color, UI.font_head))
			nm.add_child(top)
			var sub: String = Data.car(p.car).name
			if L.mode == "team":
				sub += "  · " + _t(TEAM_NAMES[int(p.team)])
			nm.add_child(UI.label(sub, 20, UI.DIM))
			row.add_child(nm)
			row.add_child(UI.label("✓" if p.ready else "…", 30, UI.GOOD if p.ready else UI.DIM, UI.font_head))
			pl.add_child(row)
		if L.mode != "survival" and int(L.bots) > 0:
			pl.add_child(UI.label("+ %d " % min(int(L.bots), Net.max_bots()) + _t("bots"), 22, UI.DIM))
		sc.add_child(pl)
		lc.add_child(sc)
		if host:
			var ips := Net.local_ips()
			lc.add_child(UI.label(_t("Room address") + ": " + (", ".join(ips) if ips.size() else "?"), 22, UI.ACCENT_2))
		left.add_child(lc)
		root.add_child(left)
		# settings and your car
		var right := UI.panel(0.62)
		right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		right.offset_left = 24 + 520 + 16
		right.offset_right = -24
		right.offset_top = 96
		right.offset_bottom = -16
		var rc := UI.vbox(12)
		var rs := ScrollContainer.new()
		rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		rs.scroll_deadzone = 12
		rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var v := UI.vbox(12)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lw := 170.0
		if host:
			var modes := _seg("", MODES.map(func(m): return [m[0], _t(m[1])]), L.mode, func(x): Net.set_room("mode", x), 0.0)
			for b in modes.get_children():
				if b is Button:
					b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(modes)
			v.add_child(_stepper(_t("Map"), _t(Data.MAPS[int(L.map)].name), func(d): Net.set_room("map", posmod(int(L.map) + d, Data.MAPS.size())), lw))
			if L.mode != "survival":
				v.add_child(_stepper(_t("Bots"), str(min(int(L.bots), Net.max_bots())), func(d): Net.set_room("bots", clamp(int(L.bots) + d, 0, Net.max_bots())), lw))
				v.add_child(_seg(_t("Bot level"), [[0, _t("Easy")], [1, _t("Medium")], [2, _t("Hard")]], int(L.bot_diff), func(x): Net.set_room("bot_diff", x), lw))
			v.add_child(_seg(_t("Upgrades"), [[true, _t("Allowed")], [false, _t("Off · all equal")]], bool(L.upgrades), func(x): Net.set_room("upgrades", x), lw))
		else:
			var mode_name: String = ""
			for m in MODES:
				if m[0] == L.mode:
					mode_name = m[1]
			var info := "%s · %s" % [_t(mode_name), _t(Data.MAPS[int(L.map)].name)]
			if L.mode != "survival":
				info += "\n%s: %d · %s" % [_t("Bots"), min(int(L.bots), Net.max_bots()), _t(DIFF_INFO[int(L.bot_diff)].name)]
			info += "\n" + _t("Upgrades") + ": " + (_t("Allowed") if L.upgrades else _t("Off · all equal"))
			var il := UI.label(info, 24)
			il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(il)
		var owned: Array = Save.state.owned
		var car_id: String = mine.get("car", Save.state.selected)
		v.add_child(_stepper(_t("Your car"), Data.car(car_id).name, func(d):
			var i := owned.find(car_id)
			var nid: String = owned[posmod(i + d, owned.size())]
			Net.set_me({"car": nid, "ups": Save.upgrades(nid).duplicate(), "ready": host}), lw))
		if L.mode == "team":
			v.add_child(_seg(_t("Team"), [[1, _t("RED")], [2, _t("BLUE")]], int(mine.get("team", 1)), func(x): Net.set_me({"team": x}), lw))
		rs.add_child(v)
		rc.add_child(rs)
		var act: Button
		if host:
			var ready_all := Net.all_ready()
			act = UI.button(_t("START") if ready_all else _t("Waiting for everyone to be ready"), func(): Net.start(), true, 32 if ready_all else 22)
			act.disabled = not ready_all
		else:
			var r: bool = mine.get("ready", false)
			act = UI.button(_t("Not ready") if r else _t("READY"), func(): Net.set_me({"ready": not r}), not r, 32)
		act.custom_minimum_size = Vector2(0, 84)
		rc.add_child(act)
		right.add_child(rc)
		root.add_child(right))


## A setting with ‹ and › buttons around its current value.
func _stepper(title: String, value: String, cb: Callable, label_w := 260.0) -> Control:
	var h := UI.hbox(12)
	var l := UI.label(title, 26)
	l.custom_minimum_size.x = label_w
	h.add_child(l)
	var a := UI.button("‹", func(): cb.call(-1), false, 30)
	a.custom_minimum_size = Vector2(66, 60)
	h.add_child(a)
	var val := UI.label(value, 26, UI.TEXT, UI.font_head)
	val.custom_minimum_size.x = 190
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(val)
	var b := UI.button("›", func(): cb.call(1), false, 30)
	b.custom_minimum_size = Vector2(66, 60)
	h.add_child(b)
	return h


## Final standings of a multiplayer match.
func _standings(ranking: Array) -> Control:
	var p := UI.panel(0.7)
	p.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	p.offset_left = -520
	p.offset_right = -24
	p.offset_top = 24
	p.offset_bottom = -24
	var v := UI.vbox(8)
	v.add_child(UI.heading(_t("Standings"), 34))
	for i in ranking.size():
		var r: Dictionary = ranking[i]
		var h := UI.hbox(10)
		h.add_child(UI.label("%d" % (i + 1), 26, UI.ACCENT_2, UI.font_head))
		var n := UI.label(str(r.name) + ("" if r.human else "  (" + _t("bot") + ")"), 24, UI.ACCENT_2 if r.me else UI.TEXT, UI.font_head)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		if int(r.team) > 0:
			h.add_child(UI.label(_t(TEAM_NAMES[int(r.team)]), 20, UI.BAD if int(r.team) == 1 else Color("5cc8ff")))
		h.add_child(UI.label(_t("{n} KILLS", {"n": r.kills}), 22, UI.TEXT, UI.font_head))
		v.add_child(h)
	p.add_child(v)
	return p


func _on_session_over(reason: String) -> void:
	_mp_status = reason
	if game:
		_end_game(false)
		showroom.activate(true)
		Sfx.music("lobby")
	if _current != "lobby":
		_mp_home()


## "Are you sure?" before the game closes. A second back press while it is open closes it (keeps the game).
var _exit_layer: CanvasLayer


func _confirm_exit() -> void:
	if _intro:
		return
	if _exit_layer:
		_exit_layer.queue_free()
		_exit_layer = null
		return
	_exit_layer = CanvasLayer.new()
	_exit_layer.layer = 30
	add_child(_exit_layer)
	var root := UI.full(Control.new())
	root.theme = UI.theme
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL if I18n.is_ar() else Control.LAYOUT_DIRECTION_LTR
	_exit_layer.add_child(root)
	var dim := UI.full(ColorRect.new())
	dim.color = Color(0, 0, 0, 0.6)
	root.add_child(dim)
	var p := UI.panel(0.85)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := UI.vbox(18)
	v.custom_minimum_size.x = 560
	var h := UI.heading(_t("Leave the game?"), 46)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var sub := UI.label(_t("Your progress is saved on this phone."), 24, UI.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var row := UI.hbox(14)
	var stay := UI.button(_t("Stay"), func():
		_exit_layer.queue_free()
		_exit_layer = null, true, 30)
	var leave := UI.button(_t("Exit"), func(): get_tree().quit(), false, 30)
	for b in [stay, leave]:
		b.custom_minimum_size = Vector2(0, 80)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)
	p.add_child(v)
	root.add_child(p)


# ---------- profile ----------

## Top-left of the lobby: photo in its rank frame, name, rank and level, progress to the next level.
func _profile_card() -> Control:
	var b := UI.button("", _profile, false, 20)
	b.custom_minimum_size = Vector2(430, 126)
	b.size = b.custom_minimum_size
	var h := UI.hbox(14)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := AvatarBadge.for_me(108)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(badge)
	var v := UI.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: Dictionary = Profile.tier()
	var n := UI.label(Save.player_name(), 30, UI.TEXT, UI.font_head)
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var r := UI.label(_t(t.name).to_upper() + "  ·  " + _t("LV") + " %d" % Profile.level(), 22, t.color, UI.font_head)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(r)
	var bar := UI.bar(Profile.progress(), t.color, 250, 10)
	v.add_child(bar)
	h.add_child(v)
	b.add_child(h)
	return b


## The profile: photo, name, level and rank, the record, every rank and how to reach it, and the backup.
func _profile() -> void:
	_focus_right_of(1280)
	_show("profile", func(root: Control):
		_top_bar(root, _t("Profile"))
		var lv := Profile.level()
		var t: Dictionary = Profile.tier()
		var left := UI.panel(0.72)
		left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		left.offset_left = 24
		left.offset_right = 24 + 400
		left.offset_top = 96
		left.offset_bottom = -16
		var lc := UI.vbox(12)
		lc.alignment = BoxContainer.ALIGNMENT_CENTER
		var badge := AvatarBadge.for_me(200)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		lc.add_child(badge)
		var nm := UI.heading(Save.player_name(), 36)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lc.add_child(nm)
		var rk := UI.label(_t(t.name).to_upper() + "  ·  " + _t("LV") + " %d" % lv, 26, t.color, UI.font_head)
		rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lc.add_child(rk)
		var photo := UI.button(_t("Change photo"), _pick_avatar, true, 24)
		photo.custom_minimum_size.y = 62
		lc.add_child(photo)
		var row := UI.hbox(10)
		var ed := UI.button(_t("Edit name"), func(): _name_screen(_profile), false, 22)
		var rm := UI.button(_t("Remove photo"), func():
			Profile.clear_avatar()
			_profile(), false, 22)
		rm.disabled = Profile.avatar() == null
		for b in [ed, rm]:
			b.custom_minimum_size.y = 58
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
		lc.add_child(row)
		if _mp_status != "" and _current == "profile":
			var st := UI.label(_mp_status, 21, UI.ACCENT_2)
			st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lc.add_child(st)
		left.add_child(lc)
		root.add_child(left)
		var right := UI.panel(0.62)
		right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		right.offset_left = 24 + 400 + 16
		right.offset_right = -24
		right.offset_top = 96
		right.offset_bottom = -16
		var sc := _scroll(right, 0, 0, 0, 0)
		var v := UI.vbox(16)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# level progress
		var x0 := Profile.xp() - Profile.xp_at(lv)
		var need := Profile.step(lv)
		v.add_child(UI.label(_t("Level {n}", {"n": lv}) + "   ·   \u2066%d / %d XP\u2069" % [x0, need], 26, UI.TEXT, UI.font_head))
		var bar := UI.bar(Profile.progress(), t.color, 600, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(bar)
		var hint := UI.label(_t("Every match gives experience: more for kills and wins, and a bit more with friends."), 20, UI.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(hint)
		# record
		var s: Dictionary = Save.state.stats
		var rec := UI.hbox(10)
		for it in [["Matches", s.matches], ["Wins", s.wins], ["Kills", s.kills], ["Best wave", Save.state.best.wave]]:
			var p := UI.panel(0.5)
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var pv := UI.vbox(0)
			var num := UI.label(str(it[1]), 32, UI.ACCENT_2, UI.font_head)
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var lab := UI.label(_t(it[0]), 19, UI.DIM)
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pv.add_child(num)
			pv.add_child(lab)
			p.add_child(pv)
			rec.add_child(p)
		v.add_child(rec)
		# ranks
		v.add_child(UI.heading(_t("Ranks"), 28))
		var ranks := UI.hbox(8)
		for tt in Profile.TIERS:
			var col := UI.vbox(4)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var bd := AvatarBadge.new()
			bd.custom_minimum_size = Vector2(84, 84)
			bd.tier = tt
			bd.lvl = int(tt.from)
			bd.initial = ""
			bd.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var got: bool = lv >= int(tt.from)
			bd.modulate = Color(1, 1, 1, 1.0 if got else 0.35)
			col.add_child(bd)
			var nl := UI.label(_t(tt.name), 21, tt.color if got else UI.DIM, UI.font_head)
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(nl)
			var fl := UI.label(_t("LV") + " %d+" % tt.from, 18, UI.DIM)
			fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(fl)
			ranks.add_child(col)
		v.add_child(ranks)
		# backup
		v.add_child(UI.heading(_t("Your data"), 28))
		var bh := UI.label(_t("Your progress lives on this phone. Back it up to a file (Google Drive, Downloads…) to move to a new phone, then restore it there."), 20, UI.DIM)
		bh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(bh)
		var brow := UI.hbox(12)
		var bk := UI.button(_t("Back up my data"), _backup, true, 24)
		var rs := UI.button(_t("Restore from a backup"), _restore, false, 24)
		for b in [bk, rs]:
			b.custom_minimum_size.y = 66
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			brow.add_child(b)
		v.add_child(brow)
		sc.add_child(v)
		root.add_child(right))


## Opens the phone's own file picker (or Godot's on a computer) and hands back the chosen path.
func _pick_file(title: String, filters: PackedStringArray, save_name: String, cb: Callable) -> void:
	var saving := save_name != ""
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var mode := DisplayServer.FILE_DIALOG_MODE_SAVE_FILE if saving else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
		DisplayServer.file_dialog_show(title, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), save_name, false, mode, filters,
			func(ok: bool, paths: PackedStringArray, _filter: int):
				if ok and paths.size() > 0:
					cb.call_deferred(paths[0]))
		return
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = filters
	fd.current_file = save_name
	fd.title = title
	fd.file_selected.connect(func(p):
		fd.queue_free()
		cb.call(p))
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.8)


func _pick_avatar() -> void:
	_pick_file(_t("Choose a photo"), PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; " + _t("Pictures")]), "", func(path: String):
		var err := Profile.set_avatar_from(path)
		_mp_status = _t(err) if err != "" else ""
		_profile())


func _backup() -> void:
	var d := Time.get_date_dict_from_system()
	var fname := "IronMetal-backup-%s-%04d%02d%02d.json" % [Save.player_name().validate_filename(), d.year, d.month, d.day]
	_pick_file(_t("Save the backup"), PackedStringArray(["*.json"]), fname, func(path: String):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_mp_status = _t("Couldn't save there. Try another place.")
		else:
			f.store_string(Profile.backup_text())
			f.close()
			_mp_status = _t("Backup saved. Keep that file safe.")
		_profile())


func _restore() -> void:
	_pick_file(_t("Choose a backup file"), PackedStringArray(), "", func(path: String):
		var text := FileAccess.get_file_as_string(path)
		var info := Profile.inspect_backup(text)
		if not info.ok:
			_mp_status = _t(info.error)
			_profile()
			return
		_confirm(_t("Restore this backup?"), _t("{name} · level {lv} · {pts} scrap. This replaces everything on this phone.", {"name": info.name, "lv": info.level, "pts": info.points}), _t("Restore"), func():
			Profile.restore(info.data)
			_mp_status = _t("Backup restored.")
			showroom.show_car(Save.state.selected)
			_profile()))


## A yes/no box over the current screen.
func _confirm(title: String, text: String, yes: String, cb: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var root := UI.full(Control.new())
	root.theme = UI.theme
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL if I18n.is_ar() else Control.LAYOUT_DIRECTION_LTR
	layer.add_child(root)
	var dim := UI.full(ColorRect.new())
	dim.color = Color(0, 0, 0, 0.6)
	root.add_child(dim)
	var p := UI.panel(0.88)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := UI.vbox(16)
	v.custom_minimum_size.x = 620
	v.add_child(UI.heading(title, 38))
	var l := UI.label(text, 24, UI.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var row := UI.hbox(12)
	var no := UI.button(_t("Cancel"), layer.queue_free, false, 28)
	var ok := UI.button(yes, func():
		layer.queue_free()
		cb.call(), true, 28)
	for b in [no, ok]:
		b.custom_minimum_size = Vector2(0, 74)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)
	p.add_child(v)
	root.add_child(p)


## For the lobby camera: is a button, panel, list or text box under this screen point? Drags that start on
## the menus belong to the menus; everywhere else they turn the view.
func _ui_at(pos: Vector2) -> bool:
	if _intro or _exit_layer or pause_layer or game:
		return true
	var stack: Array = [screen_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			if ch is Control and (ch as Control).is_visible_in_tree():
				var c := ch as Control
				if (c is BaseButton or c is PanelContainer or c is Panel or c is ScrollContainer or c is LineEdit or c is Range) \
						and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(pos):
					return true
				stack.append(c)
	return false
