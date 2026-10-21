class_name VictoryScreen
extends Control
## The end of a match, drawn over the slow-motion orbit round the MVP car: the screen darkens at the edges,
## gold light rays turn behind a big title that punches in (VICTORY / DEFEAT / WAVE n), and then the MVP card
## slides up with the player's badge, their name, their car, kills and damage. In multiplayer every device shows
## the same MVP (the host picks it).

var title := ""
var win := true
var info := {}
var _t := 0.0
var _title: Label
var _sub: Label
var _card: PanelContainer
var _vig: ColorRect
var _gold := Color("ffd25a")

const VIGNETTE := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.6, 1.0);
	float v = smoothstep(0.25, 0.95, length(d));
	COLOR = vec4(tint.rgb, amount * (0.25 + 0.75 * v));
}
"""


func _ready() -> void:
	UI.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not win:
		_gold = Color("ff6a55")
	_vig = UI.full(ColorRect.new())
	var sh := Shader.new()
	sh.code = VIGNETTE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", Color(0.05, 0.03, 0.0) if win else Color(0.12, 0.0, 0.0))
	_vig.material = m
	_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vig)

	_title = UI.heading(title, 120)
	_title.add_theme_font_override("font", UI.font_title)
	_title.add_theme_color_override("font_color", _gold)
	_title.add_theme_constant_override("outline_size", 14)
	_title.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0, 0.95))
	_title.add_theme_constant_override("shadow_offset_y", 6)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_sub = UI.label("", 26, Color(1, 1, 1, 0.85), UI.font_head)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_constant_override("outline_size", 6)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_sub)

	_card = _make_card()
	add_child(_card)
	_place()
	resized.connect(_place)
	modulate.a = 1.0


func _make_card() -> PanelContainer:
	var card := PanelContainer.new()
	var box := UI._flat(Color(0.06, 0.05, 0.04, 0.86), 22, 3, Color(_gold, 0.9))
	box.content_margin_left = 22
	box.content_margin_right = 30
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	box.shadow_color = Color(_gold, 0.35)
	box.shadow_size = 18
	card.add_theme_stylebox_override("panel", box)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UI.hbox(20)
	card.add_child(row)

	var badge: AvatarBadge
	if info.get("me", false):
		badge = AvatarBadge.for_me(118)
	else:
		badge = AvatarBadge.new()
		badge.custom_minimum_size = Vector2(118, 118)
		badge.show_level = false
		var nm: String = str(info.get("name", "?"))
		badge.initial = nm.substr(0, 1).to_upper()
		var t: Dictionary = Profile.TIERS[0].duplicate()
		t.color = info.get("color", Color.WHITE) if info.get("human", false) else _gold
		t.fx = "sparks"
		badge.tier = t
	if info.get("me", false):   # the MVP gets the sparkle whatever their rank
		badge.tier = badge.tier.duplicate()
		if badge.tier.fx == "none":
			badge.tier.fx = "sparks"
			badge.tier.color = _gold
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var col := UI.vbox(2)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	var pill_row := UI.hbox(10)
	col.add_child(pill_row)
	var pill := PanelContainer.new()
	var pb := UI._flat(_gold, 10, 0)
	pb.content_margin_left = 12
	pb.content_margin_right = 12
	pb.content_margin_top = 1
	pb.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", pb)
	var mvp := UI.label("MVP", 22, Color(0.1, 0.06, 0.0), UI.font_title)
	pill.add_child(mvp)
	pill_row.add_child(pill)
	pill_row.add_child(UI.label(I18n.t("Most valuable player"), 18, Color(_gold, 0.9), UI.font_head))

	var name := UI.label(str(info.get("name", "")), 40, Color.WHITE, UI.font_head)
	if info.get("me", false):
		name.text = "%s  (%s)" % [Save.player_name(), I18n.t("YOU")] if Save.player_name() != "" else I18n.t("YOU")
	name.add_theme_constant_override("outline_size", 6)
	name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	col.add_child(name)
	var car := UI.label(str(info.get("car", "")), 22, Color("c690ff") if info.get("premium", false) else UI.DIM, UI.font_head)
	if str(info.get("car", "")) == str(info.get("name", "")):
		car.visible = false   # a bot's name is its car's name already
	col.add_child(car)
	var stats := UI.hbox(22)
	stats.add_child(UI.label("✖ %d  %s" % [int(info.get("kills", 0)), I18n.t("Kills")], 22, UI.ACCENT_2, UI.font_head))
	stats.add_child(UI.label("✹ %d  %s" % [int(info.get("dmg", 0)), I18n.t("Damage")], 22, Color("8fc4ff"), UI.font_head))
	col.add_child(stats)
	return card


func _place() -> void:
	var vp := size
	_title.size = Vector2(vp.x, 150)
	_title.pivot_offset = _title.size / 2
	_title.position = Vector2(0, vp.y * 0.07)
	_sub.size = Vector2(vp.x, 36)
	_sub.position = Vector2(0, vp.y * 0.07 + 140)
	_card.reset_size()
	_card.pivot_offset = _card.size / 2


func _process(dt: float) -> void:
	_t += dt
	(_vig.material as ShaderMaterial).set_shader_parameter("amount", clamp(_t / 0.8, 0.0, 1.0) * 0.85)
	# the title punches in from big and blurry-bright, then settles with a small bounce
	var k: float = clamp((_t - 0.15) / 0.45, 0.0, 1.0)
	var s: float = lerp(2.6, 1.0, _ease_back(k))
	_title.scale = Vector2(s, s)
	_title.modulate = Color(1 + (1 - k) * 1.5, 1 + (1 - k) * 1.5, 1 + (1 - k) * 1.5, k)
	if k >= 1.0:   # breathing glow afterwards
		var g := 1.0 + 0.12 * sin(_t * 4.0)
		_title.modulate = Color(g, g, g, 1)
	# the MVP card slides up from below the screen
	var c: float = clamp((_t - 0.9) / 0.55, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - c, 3)
	var home := Vector2((size.x - _card.size.x) / 2, size.y - _card.size.y - max(18.0, size.y * 0.045))
	_card.position = home + Vector2(0, (1 - e) * (size.y - home.y + 40))
	_card.modulate.a = c
	queue_redraw()


func _ease_back(x: float) -> float:
	var c1 := 1.7
	var c3 := c1 + 1
	return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)


## Light rays turning slowly behind the title, and a burst of sparks when it lands.
func _draw() -> void:
	var k: float = clamp((_t - 0.3) / 0.6, 0.0, 1.0)
	if k <= 0:
		return
	var c := Vector2(size.x / 2, size.y * 0.07 + 75)
	var R: float = size.x * 0.55
	var n := 14
	for i in n:
		var a := _t * 0.25 + i * TAU / n
		var w := 0.07
		var pts := PackedVector2Array([c, c + Vector2(cos(a - w), sin(a - w)) * R, c + Vector2(cos(a + w), sin(a + w)) * R])
		var cols := PackedColorArray([Color(_gold, (0.28 if win else 0.12) * k), Color(_gold, 0.0), Color(_gold, 0.0)])
		draw_polygon(pts, cols)
	# sparks thrown out once
	var st: float = _t - 0.45
	if st > 0 and st < 1.6:
		for i in 26:
			var a := i * 2.39996
			var sp := 260.0 + float((i * 37) % 11) * 40.0
			var p := c + Vector2(cos(a), sin(a) * 0.6) * sp * st + Vector2(0, 120 * st * st)
			var al: float = 1.0 - st / 1.6
			draw_circle(p, 3.0 + (i % 3), Color(1, 0.9, 0.55, al) if win else Color(1, 0.5, 0.35, al))
