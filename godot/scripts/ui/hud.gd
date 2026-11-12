class_name HUD
extends CanvasLayer
## In-match interface: health, lives, kills, timer, minimap, kill feed, announcements, floating enemy bars,
## and the touch controls (a floating stick on the left half, fire / rocket / ability buttons on the right).
## Touches are tracked by finger index, so steering, firing and a rocket all work at the same time.

signal pause_pressed

const MAP_PX := 150.0

var match_: Match
var _root: Control
var _name: Label
var _hp_back: Panel
var _hp_fill: Panel
var _hp_ghost: Panel
var _kills: Label
var _lives: HBoxContainer
var _timer: Label
var _rank: Label
var _minimap: Control
var _map_layer: ImageTexture
var _map_t := 0.0
var _feed: VBoxContainer
var _announce: VBoxContainer
var _ann_title: Label
var _ann_sub: Label
var _ann_t := 0.0
var _toast: Label
var _toast_t := 0.0
var _count: Label
var _count_t := 0.0
var _banner: Label
var _hurt: ColorRect
var _white: ColorRect
var _bars := {}           # Car -> {root, fill, name}
var _cam_label: Label
var _power_label: Label

# touch controls
var _stick_base: Control
var _stick_knob: Control
var _stick_id := -1
var _look_id := -1             # a finger dragging on the free right side turns the camera round the car
var _look_last := Vector2.ZERO
var _stick_origin := Vector2.ZERO
var _jx := 0.0
var _jy := 0.0
var _btn_fire: TouchButton
var _btn_rocket: TouchButton
var _btn_special: TouchButton
var _btn_boost: TouchButton
var _btn_cam: TouchButton
var _reticle: Control           # brackets round the enemy the guns are locked on
var _ret_car: Car
var _ret_t := 0.0
var _ret_hit := 0.0
var _numbers: Control           # floating damage numbers
var _btn_pause: TouchButton
var _touch_btn := {}      # finger index -> TouchButton
var _gun := false
var _keys := {}


func _ready() -> void:
	UI.init()
	layer = 5
	_root = UI.full(Control.new())
	_root.theme = UI.theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_vignette()
	_hurt = UI.full(ColorRect.new())
	_hurt.color = Color(0.8, 0.05, 0.02, 0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hurt)
	_white = UI.full(ColorRect.new())
	_white.color = Color(1, 0.97, 0.9, 0)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_white)
	_build_top_left()
	_build_top_center()
	_build_top_right()
	_build_center()
	_build_controls()


# ---------- layout ----------

## A soft darkening towards the corners of the picture, under every HUD element (the HUD itself stays at full
## brightness). Left out on the low tier, where one more full-screen blend is not worth its cost.
func _build_vignette() -> void:
	var v := UI.full(ColorRect.new())
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
render_mode unshaded;
uniform float strength = 0.5;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.82);
	float k = smoothstep(0.30, 0.72, length(d));
	COLOR = vec4(0.02, 0.015, 0.03, k * k * strength);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	v.material = m
	_root.add_child(v)
	v.visible = Quality.tier_id != "low"
	Quality.changed.connect(func() -> void: v.visible = Quality.tier_id != "low")


func _build_top_left() -> void:
	var box := UI.vbox(4)
	box.position = Vector2(24, 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	var row := UI.hbox(12)
	_name = UI.label("", 22, UI.TEXT, UI.font_head)
	row.add_child(_name)
	box.add_child(row)
	_hp_back = Panel.new()
	_hp_back.custom_minimum_size = Vector2(340, 14)
	_hp_back.add_theme_stylebox_override("panel", UI._flat(Color(0, 0, 0, 0.45), 7, 1))
	_hp_ghost = Panel.new()
	_hp_ghost.add_theme_stylebox_override("panel", UI._flat(Color(1, 0.9, 0.7, 0.55), 7, 0))
	_hp_fill = Panel.new()
	_hp_fill.add_theme_stylebox_override("panel", UI._flat(UI.GOOD, 7, 0))
	_hp_back.add_child(_hp_ghost)
	_hp_back.add_child(_hp_fill)
	box.add_child(_hp_back)
	var row2 := UI.hbox(14)
	_kills = UI.label("", 20, UI.ACCENT_2, UI.font_head)
	row2.add_child(_kills)
	_lives = UI.hbox(4)
	row2.add_child(_lives)
	box.add_child(row2)
	_timer = UI.label("", 22, UI.TEXT, UI.font_head)
	box.add_child(_timer)
	_power_label = UI.label("", 18, Color("8fc4ff"), UI.font_head)
	box.add_child(_power_label)


func _build_top_center() -> void:
	var p := UI.panel(0.5)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.offset_top = 14
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top = 4
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_bottom = 4
	_rank = UI.label("", 20, UI.TEXT, UI.font_head)
	p.add_child(_rank)
	_root.add_child(p)


func _build_top_right() -> void:
	_minimap = Control.new()
	_minimap.custom_minimum_size = Vector2(MAP_PX, MAP_PX)
	_minimap.size = Vector2(MAP_PX, MAP_PX)
	_minimap.anchor_left = 1.0
	_minimap.anchor_right = 1.0
	_minimap.offset_left = -MAP_PX - 96
	_minimap.offset_right = -96
	_minimap.offset_top = 14
	_minimap.offset_bottom = 14 + MAP_PX
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.draw.connect(_draw_minimap)
	_root.add_child(_minimap)
	_feed = UI.vbox(4)
	_feed.anchor_left = 1.0
	_feed.anchor_right = 1.0
	_feed.offset_left = -420
	_feed.offset_right = -96
	_feed.offset_top = 24 + MAP_PX
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)


func _build_center() -> void:
	_announce = UI.vbox(0)
	_announce.anchor_left = 0.5
	_announce.anchor_right = 0.5
	_announce.anchor_top = 0.22
	_announce.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_announce.alignment = BoxContainer.ALIGNMENT_CENTER
	_announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ann_title = UI.heading("", 46)
	_ann_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ann_sub = UI.label("", 20, UI.TEXT, UI.font_head)
	_ann_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ann_sub.add_theme_constant_override("outline_size", 4)
	_ann_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_announce.add_child(_ann_title)
	_announce.add_child(_ann_sub)
	_announce.modulate.a = 0
	_root.add_child(_announce)
	_toast = UI.heading("", 24)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.36
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Color("9dffb0"))
	_toast.modulate.a = 0
	_root.add_child(_toast)
	_count = UI.heading("", 110)
	_count.anchor_left = 0.5
	_count.anchor_right = 0.5
	_count.anchor_top = 0.32
	_count.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_font_override("font", UI.font_title)
	_count.modulate.a = 0
	_root.add_child(_count)
	_banner = UI.heading("", 84)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.36
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_override("font", UI.font_title)
	_banner.visible = false
	_root.add_child(_banner)


func _build_controls() -> void:
	var s: float = float(Save.state.get("stick_scale", 1.0))
	_stick_base = _circle(140 * s, Color(1, 1, 1, 0.1))
	_stick_knob = _circle(60 * s, Color(1, 1, 1, 0.35))
	_stick_base.visible = false
	_stick_base.add_child(_stick_knob)
	_root.add_child(_stick_base)
	_btn_fire = TouchButton.make(I18n.t("FIRE"), ControlsEditor.BASE.fire, UI.ACCENT)
	_btn_rocket = TouchButton.make(I18n.t("RKT"), ControlsEditor.BASE.rocket, Color("e8e0d0"))
	_btn_special = TouchButton.make("", ControlsEditor.BASE.special, UI.GOOD)
	_btn_boost = TouchButton.make(I18n.t("BOOST"), ControlsEditor.BASE.boost, ControlsEditor.BOOST_COLOR)
	_btn_cam = TouchButton.make("", 62, Color("e8e0d0"))
	_btn_pause = TouchButton.make("II", 62, Color("e8e0d0"))
	_reticle = Control.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reticle.draw.connect(_draw_reticle)
	_root.add_child(_reticle)
	_numbers = Control.new()
	_numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_numbers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_numbers)
	for b in [_btn_fire, _btn_rocket, _btn_special, _btn_boost, _btn_cam, _btn_pause]:
		_root.add_child(b)
	_root.resized.connect(_place_controls)
	_place_controls()


## Puts the touch buttons where the player arranged them in Settings (fractions of the screen and a size each).
func _place_controls() -> void:
	var w := _root.size.x
	var h := _root.size.y
	var L := ControlsEditor.current()
	for pair in [[_btn_fire, "fire"], [_btn_rocket, "rocket"], [_btn_special, "special"], [_btn_boost, "boost"]]:
		var b: TouchButton = pair[0]
		var p: Array = L[pair[1]]
		var d: float = ControlsEditor.BASE[pair[1]] * float(p[2])
		b.size = Vector2(d, d)
		b.custom_minimum_size = b.size
		b.position = Vector2(p[0] * w, p[1] * h) - b.size / 2
	_btn_pause.position = Vector2(w - 76, 14)
	_btn_cam.position = Vector2(w - 76, 88)


func _circle(d: float, c: Color) -> Control:
	var p := Panel.new()
	p.size = Vector2(d, d)
	p.add_theme_stylebox_override("panel", UI._flat(c, int(d / 2), 2, Color(1, 1, 1, 0.25)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# ---------- input ----------

func _input(e: InputEvent) -> void:
	if match_ == null:
		return
	if e is InputEventScreenTouch:
		_on_touch(e.index, e.position, e.pressed)
	elif e is InputEventScreenDrag:
		if e.index == _stick_id:
			_drag_stick(e.position)
		elif e.index == _look_id:
			var d: Vector2 = e.position - _look_last
			_look_last = e.position
			match_.look_drag(d.x / _root.size.x)
	elif e is InputEventKey and not e.echo:
		_keys[e.physical_keycode] = e.pressed
		if e.pressed:
			match e.physical_keycode:
				KEY_F: match_.player_rocket()
				KEY_E: match_.player_special()
				KEY_SHIFT: match_.player_boost()
				KEY_C: _cycle_cam()
				KEY_ESCAPE, KEY_P: pause_pressed.emit()


func _on_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		for b in [_btn_pause, _btn_cam, _btn_fire, _btn_rocket, _btn_special, _btn_boost]:
			if b.hit(pos):
				_touch_btn[idx] = b
				b.down = true
				if b == _btn_fire:
					_gun = true
				elif b == _btn_rocket:
					match_.player_rocket()
				elif b == _btn_special:
					match_.player_special()
				elif b == _btn_boost:
					match_.player_boost()
				elif b == _btn_cam:
					_cycle_cam()
				elif b == _btn_pause:
					pause_pressed.emit()
				return
		if pos.x < _root.size.x * 0.5 and _stick_id == -1:
			_stick_id = idx
			_stick_origin = pos
			_stick_base.visible = true
			_stick_base.position = pos - _stick_base.size / 2
			_stick_knob.position = (_stick_base.size - _stick_knob.size) / 2
		elif pos.x >= _root.size.x * 0.5 and _look_id == -1:
			_look_id = idx
			_look_last = pos
			match_.look_hold(true)
	else:
		if idx == _look_id:
			_look_id = -1
			match_.look_hold(false)
		if idx == _stick_id:
			_stick_id = -1
			_jx = 0
			_jy = 0
			_stick_base.visible = false
		if _touch_btn.has(idx):
			var b: TouchButton = _touch_btn[idx]
			b.down = false
			if b == _btn_fire:
				_gun = false
			_touch_btn.erase(idx)


func _drag_stick(pos: Vector2) -> void:
	var mx: float = 58.0 * float(Save.state.get("stick_scale", 1.0))
	var d := pos - _stick_origin
	if d.length() > mx:
		d = d.normalized() * mx
	_jx = d.x / mx
	_jy = d.y / mx
	if abs(_jx) < 0.12:
		_jx = 0
	_stick_knob.position = (_stick_base.size - _stick_knob.size) / 2 + d


func _cycle_cam() -> void:
	var m := match_.cycle_camera()
	_cam_label_set(m)


func _cam_label_set(m: String) -> void:
	_btn_cam.text = I18n.t({"near": "NEAR", "far": "FAR", "hood": "HOOD"}[m])
	_btn_cam.queue_redraw()


## Turns the stick (and keys on a computer) into throttle and steering for the chosen control scheme.
func _apply_input() -> void:
	var k := func(code) -> bool: return _keys.get(code, false)
	var th := (1.0 if k.call(KEY_W) or k.call(KEY_UP) else 0.0) - (1.0 if k.call(KEY_S) or k.call(KEY_DOWN) else 0.0)
	var st := (1.0 if k.call(KEY_A) or k.call(KEY_LEFT) else 0.0) - (1.0 if k.call(KEY_D) or k.call(KEY_RIGHT) else 0.0)
	var scheme: String = Save.state.get("scheme", "classic")
	var p := match_.player
	if _stick_id != -1:
		var mag: float = min(1.0, Vector2(_jx, _jy).length())
		if scheme == "direction":  # point where you want to go; the car turns there by itself
			if mag < 0.18:
				th = 0
				st = 0
			else:
				var ch := match_.camera.global_basis.get_euler().y + PI
				var fwd := Vector2(sin(ch), cos(ch))
				var right := Vector2(-cos(ch), sin(ch))
				var dv := fwd * -_jy + right * _jx
				var diff := wrapf(atan2(dv.x, dv.y) - p.heading, -PI, PI)
				st = clamp(diff * 2.6, -1.0, 1.0)
				th = mag * (1 - 0.4 * min(1.0, abs(diff) / 1.6))
				if abs(diff) > 2.6 and abs(p.speed) < 3:
					th = -0.8 * mag
					st = -st
		elif scheme == "autogas":
			st = -_jx
			th = -1.0 if _jy > 0.55 else 1.0
		else:  # classic: up drives, down reverses; a soft curve keeps small corrections gentle
			th = 0.0 if abs(_jy) < 0.2 else -_jy
			st = -sign(_jx) * pow(min(1.0, abs(_jx) * 1.2), 1.5)
	elif scheme == "autogas" and DisplayServer.is_touchscreen_available() and match_.state == "fight":
		th = 1.0
		st = 0.0
	# auto fire: the gun runs by itself while it is locked on an enemy in range (Settings), so the right thumb is
	# free for rockets, the ability and turbo; the fire button still works for spraying at will
	var auto := false
	if bool(Save.state.get("autofire", true)) and match_.state == "fight" and p.alive and p.lock:
		auto = Vector2(p.lock.x - p.x, p.lock.z - p.z).length() < Match.AUTO_FIRE_RANGE
	match_.set_input(th, st, _gun or auto or k.call(KEY_SPACE))


# ---------- called by the match ----------

func on_start(m: Match) -> void:
	match_ = m
	_name.text = m.player.label() if m.net_role != "" else m.player.data.name
	_cam_label_set(m.cam_mode)
	_build_map_layer()
	ensure_enemy_bars(m)
	_btn_special.text = I18n.t(m.player.data.special.name).to_upper()


func update_hud(m: Match, dt: float) -> void:
	_apply_input()
	var p := m.player
	var frac: float = clamp(p.hp / p.max_hp, 0.0, 1.0)
	_hp_fill.size = Vector2(340 * frac, 14)
	_hp_ghost.size = Vector2(lerp(_hp_ghost.size.x, 340 * frac, min(1.0, dt * 3)), 14)
	(_hp_fill.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = UI.GOOD if frac > 0.5 else (UI.ACCENT_2 if frac > 0.25 else UI.BAD)
	_kills.text = I18n.t("{n} KILLS", {"n": p.kills})
	if _lives.get_child_count() != 3:
		for c in _lives.get_children():
			c.queue_free()
		for i in 3:
			_lives.add_child(UI.label("♥", 22, UI.BAD))
	for i in 3:
		(_lives.get_child(i) as Label).modulate.a = 1.0 if i < p.lives else 0.2
	var tl := m.time_left()
	_timer.text = "%d:%02d" % [int(tl) / 60, int(tl) % 60] if tl >= 0 else I18n.t("WAVE") + " %d" % m.wave
	var alive := m.cars.filter(func(c): return m._in_play(c)).size()
	var rank := 1
	for c in m.cars:
		if c != p and c.kills > p.kills:
			rank += 1
	if m.state == "waiting":
		_rank.text = I18n.t("Waiting for players…")
	elif m.mode == "team":
		var tk := [0, 0, 0]
		for c in m.cars:
			tk[clamp(c.team, 0, 2)] += c.kills
		_rank.text = I18n.t("RED") + " %d  :  %d " % [tk[1], tk[2]] + I18n.t("BLUE")
	elif m.mode == "deathmatch":
		_rank.text = I18n.t("YOU") + " %d   #%d/%d" % [p.kills, rank, alive]
	else:
		_rank.text = I18n.t("WAVE") + " %d   ·   %d" % [m.wave, m.cars.filter(func(c): return not c.human and m._in_play(c)).size()]
	var watching := m.view_car()
	if watching != p and m.state == "fight":
		_rank.text += "   ·   " + I18n.t("Watching {a}", {"a": watching.label()})
	_power_label.text = (I18n.t(Data.POWERS[p.power.type].name).to_upper() + " ×%d" % p.power.ammo) if not p.power.is_empty() else ""
	# buttons
	_btn_rocket.badge = str(p.rockets) if p.power.is_empty() else Data.POWERS[p.power.type].short
	_btn_rocket.queue_redraw()
	var cd: float = clamp(p.special_cd / p.stats.special_cooldown, 0.0, 1.0)
	_btn_special.cooldown = cd
	_btn_special.badge = str(ceili(p.special_cd)) if p.special_cd > 0 else ""
	_btn_special.queue_redraw()
	_btn_boost.cooldown = clamp(p.boost_cd / Match.BOOST_CD, 0.0, 1.0)
	_btn_boost.down = p.boost_t > 0
	_btn_boost.queue_redraw()
	_btn_fire.badge = I18n.t("AUTO") if bool(Save.state.get("autofire", true)) else ""
	_btn_fire.down = _gun or p.firing
	_btn_fire.queue_redraw()
	_update_reticle(m, dt)
	_update_numbers(m, dt)
	# fades
	if _ann_t > 0:
		_ann_t -= dt
		_announce.modulate.a = min(1.0, _ann_t * 2.5)
	if _toast_t > 0:
		_toast_t -= dt
		_toast.modulate.a = min(1.0, _toast_t * 3)
	if _count_t > 0:
		_count_t -= dt
		_count.modulate.a = min(1.0, _count_t * 2)
		_count.scale = Vector2.ONE * (1.0 + (0.9 - min(0.9, _count_t)) * 0.2)
	_hurt.color.a = max(0.0, _hurt.color.a - dt * 1.4)
	_white.color.a = max(0.0, _white.color.a - dt * 0.9)
	for item in _feed.get_children():
		if Time.get_ticks_msec() > int(item.get_meta("until", 0)):
			item.queue_free()
	_map_t -= dt
	if _map_t <= 0:
		_map_t = 1.0 / 12.0
		_minimap.queue_redraw()
	_update_bars(m)


func countdown(text: String) -> void:
	_count.text = text
	_count.pivot_offset = _count.size / 2
	_count_t = 0.9


func announce(title: String, sub: String, kind := "") -> void:
	_ann_title.text = title
	_ann_sub.text = sub
	var col := {"red": UI.BAD, "gold": Color("ffd25a"), "blue": Color("8fc4ff"), "green": UI.GOOD, "kill": UI.ACCENT}
	_ann_title.add_theme_color_override("font_color", col.get(kind, UI.TEXT))
	_ann_t = 2.6


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 1.6


func feed(killer: Car, victim: Car) -> void:
	var t := I18n.t("{a} wrecked {b}", {"a": killer.label() if killer else I18n.t("The arena"), "b": victim.label()})
	if killer and killer.is_player:
		t = I18n.t("You wrecked {b}", {"b": victim.label()})
	elif victim.is_player:
		t = I18n.t("{a} wrecked you", {"a": killer.label() if killer else I18n.t("The arena")})
	feed_text(t, killer != null and killer.is_player)


func feed_text(t: String, mine := false) -> void:
	var p := UI.panel(0.5)
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top = 3
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_bottom = 3
	var l := UI.label(t, 16, UI.ACCENT_2 if mine else UI.TEXT, UI.font_head)
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	_feed.add_child(p)
	p.set_meta("until", Time.get_ticks_msec() + 5000)
	while _feed.get_child_count() > 4:
		_feed.get_child(0).free()


func hurt(amt: float) -> void:
	_hurt.color.a = min(0.45, _hurt.color.a + amt * 0.012)


func whiteout() -> void:
	_white.color.a = 0.85


func banner(text: String, win: bool) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", Color("ffd25a") if win else UI.BAD)
	_banner.visible = true


## The end of the match: the playing interface goes away and the victory / MVP screen comes up.
func victory(title: String, win: bool, info: Dictionary) -> void:
	_root.visible = false
	_banner.visible = false
	for b in _bars.values():
		b.root.visible = false
	var v := VictoryScreen.new()
	v.title = title
	v.win = win
	v.info = info
	add_child(v)


func flash_special() -> void:
	_btn_special.pulse = 0.4


# ---------- floating enemy bars ----------

func ensure_enemy_bars(m: Match) -> void:
	for c in m.cars:
		if c.is_player or _bars.has(c):
			continue
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mate: bool = c.team != 0 and c.team == m.player.team
		var name := UI.label(c.label(), 17 if c.human else 16, c.color if c.human else UI.TEXT, UI.font_head)
		name.add_theme_constant_override("outline_size", 5)
		name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		name.position = Vector2(-80, -26)
		name.size = Vector2(160, 20)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var back := Panel.new()
		back.add_theme_stylebox_override("panel", UI._flat(Color(0, 0, 0, 0.6), 4, 0))
		back.position = Vector2(-45, 0)
		back.size = Vector2(90, 9)
		var fill := Panel.new()
		fill.add_theme_stylebox_override("panel", UI._flat(UI.GOOD if mate else UI.BAD, 4, 0))
		fill.size = Vector2(90, 9)
		back.add_child(fill)
		var lives := Label.new()   # lives left, as hearts under the health bar
		lives.add_theme_font_size_override("font_size", 14)
		lives.add_theme_color_override("font_color", UI.BAD)
		lives.add_theme_constant_override("outline_size", 4)
		lives.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lives.position = Vector2(-45, 10)
		lives.size = Vector2(90, 16)
		lives.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(name)
		root.add_child(back)
		root.add_child(lives)
		_root.add_child(root)
		_bars[c] = {"root": root, "fill": fill, "lives": lives}


## Each enemy's name, health and lives float right above the car. Camera.unproject_position already gives
## canvas coordinates (the same space the HUD is laid out in), whatever the screen's pixel density.
func _update_bars(m: Match) -> void:
	if not _root.visible:   # the victory screen is up
		return
	var cam := m.camera
	for key in _bars.keys():
		var b: Dictionary = _bars[key]
		if not is_instance_valid(key) or not m.cars.has(key):   # a wreck cleared away between survival waves
			b.root.queue_free()
			_bars.erase(key)
			continue
		var c: Car = key
		if not c.alive:
			b.root.visible = false
			continue
		var wp := c.global_position + Vector3.UP * (c.dims.y + 0.8)
		if cam.is_position_behind(wp) or cam.global_position.distance_to(wp) > 110:
			b.root.visible = false
			continue
		b.root.visible = true
		b.root.position = cam.unproject_position(wp)
		b.fill.size.x = 90 * clamp(c.hp / c.max_hp, 0.0, 1.0)
		var hearts := "♥ ".repeat(c.lives).strip_edges() if m.is_dm() or c.human else ""
		if b.lives.text != hearts:
			b.lives.text = hearts


# ---------- minimap ----------

## The arena's cover is drawn once into a texture; each refresh only draws the moving dots on top.
func _build_map_layer() -> void:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var a := match_.arena
	var k := n / (a.half * 2)
	for o in a.obstacles:
		var r: float = o.get("r", max(o.get("hw", 1.0), o.get("hd", 1.0)))
		var cx := int((o.x + a.half) * k)
		var cz := int((o.z + a.half) * k)
		var rr: int = max(1, int(r * k))
		img.fill_rect(Rect2i(cx - rr, cz - rr, rr * 2, rr * 2), Color(1, 1, 1, 0.22))
	_map_layer = ImageTexture.create_from_image(img)


func _draw_minimap() -> void:
	if match_ == null:
		return
	var m := match_
	var c := _minimap
	c.draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_PX, MAP_PX)), Color(0.05, 0.045, 0.04, 0.55))
	c.draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_PX, MAP_PX)), Color(1, 0.85, 0.7, 0.2), false, 1.0)
	if _map_layer:
		c.draw_texture_rect(_map_layer, Rect2(Vector2.ZERO, Vector2(MAP_PX, MAP_PX)), false)
	var to := func(x: float, z: float) -> Vector2: return Vector2((x / (m.arena.half * 2) + 0.5) * MAP_PX, (z / (m.arena.half * 2) + 0.5) * MAP_PX)
	for s in m.strikes:
		c.draw_circle(to.call(s.x, s.z), s.r / (m.arena.half * 2) * MAP_PX, Color(1, 0.2, 0.1, 0.35))
	for p in m.pickups:
		if p.respawn <= 0:
			c.draw_rect(Rect2(to.call(p.x, p.z) - Vector2(2.5, 2.5), Vector2(5, 5)), UI.GOOD if p.type == "health" else UI.ACCENT_2)
	for d in m.drops:
		c.draw_circle(to.call(d.x, d.z), 4.0, Color("8fc4ff"))
	for car in m.cars:
		if not car.alive:
			continue
		var pos: Vector2 = to.call(car.x, car.z)
		if car.is_player:
			var f := Vector2(sin(car.heading), cos(car.heading))
			var r := Vector2(f.y, -f.x)
			c.draw_colored_polygon(PackedVector2Array([pos + f * 7, pos - f * 4 + r * 4.5, pos - f * 4 - r * 4.5]), Color("ffd25a"))
		else:
			var mate: bool = car.team != 0 and car.team == m.player.team
			c.draw_circle(pos, 3.5, Color("ffd25a") if car.bounty else (UI.GOOD if mate else (car.color if car.human else UI.BAD)))


# ---------- lock-on reticle and damage numbers ----------

func _update_reticle(m: Match, dt: float) -> void:
	var l: Car = m.player.lock if m.player.alive and m.state == "fight" else null
	if l != _ret_car:
		_ret_car = l
		_ret_t = 0.0
		if l:
			Sfx.play("click", 0.35)
	_ret_t += dt
	_ret_hit = max(0.0, _ret_hit - dt * 4.0)
	_reticle.queue_redraw()


## Four red corner brackets that snap in round the locked enemy, turning slowly; they tighten and flash white on a hit.
func _draw_reticle() -> void:
	if _ret_car == null or match_ == null or not is_instance_valid(_ret_car):
		return
	var cam := match_.camera
	var wp := _ret_car.global_position + Vector3.UP * 1.1
	if cam.is_position_behind(wp):
		return
	var sp := cam.unproject_position(wp) * (_root.size / Vector2(get_viewport().get_visible_rect().size))
	var dist := cam.global_position.distance_to(wp)
	var snap: float = 1.0 + 1.5 * pow(1.0 - min(1.0, _ret_t / 0.18), 2)   # pops in from wide
	var r: float = clamp(900.0 / max(dist, 1.0), 26.0, 70.0) * snap * (1.0 - 0.12 * _ret_hit)
	var col := Color(1, 0.25, 0.15).lerp(Color.WHITE, _ret_hit)
	var a := _ret_t * 0.8
	for k in 4:
		var ang := a + k * PI / 2
		var c := sp + Vector2(cos(ang), sin(ang)) * r
		var t1 := Vector2(cos(ang + PI * 0.75), sin(ang + PI * 0.75)) * r * 0.35
		var t2 := Vector2(cos(ang - PI * 0.75), sin(ang - PI * 0.75)) * r * 0.35
		_reticle.draw_polyline(PackedVector2Array([c + t1, c, c + t2]), Color(0, 0, 0, 0.5), 6.0, true)
		_reticle.draw_polyline(PackedVector2Array([c + t1, c, c + t2]), col, 3.0, true)
	_reticle.draw_circle(sp, 3.0, col)


## A number that pops out of the enemy you hit and floats up: orange for bullets, big gold for rockets and abilities.
func damage_number(v: Car, amt: float, cause: String) -> void:
	if _numbers == null or not is_instance_valid(v):
		return
	var big := cause != "gun"
	var l := Label.new()
	l.text = str(roundi(amt))
	l.add_theme_font_override("font", UI.font_head)
	l.add_theme_font_size_override("font_size", 46 if big else 34)
	l.add_theme_color_override("font_color", Color("ffd24a") if big else Color("ff8a3a"))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.0, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("car", v)
	l.set_meta("t", 0.0)
	l.set_meta("off", Vector2(randf_range(46, 96), randf_range(-14, 14)))   # beside the car, clear of its name bar
	_numbers.add_child(l)
	_ret_hit = 1.0
	if _numbers.get_child_count() > 14:
		_numbers.get_child(0).queue_free()


func _update_numbers(m: Match, dt: float) -> void:
	var cam := m.camera
	var k := _root.size / Vector2(get_viewport().get_visible_rect().size)
	for l in _numbers.get_children():
		var t: float = l.get_meta("t") + dt
		l.set_meta("t", t)
		var v = l.get_meta("car")
		if t > 0.9 or not is_instance_valid(v):
			l.queue_free()
			continue
		var wp: Vector3 = v.global_position + Vector3.UP * 1.2
		if cam.is_position_behind(wp):
			l.visible = false
			continue
		l.visible = true
		var pop: float = 1.0 + 0.6 * max(0.0, 1.0 - t / 0.12)
		l.scale = Vector2.ONE * pop
		l.pivot_offset = l.size / 2
		l.position = cam.unproject_position(wp) * k + l.get_meta("off") - l.size / 2 + Vector2(0, -t * 70)
		l.modulate.a = 1.0 - max(0.0, (t - 0.55) / 0.35)
