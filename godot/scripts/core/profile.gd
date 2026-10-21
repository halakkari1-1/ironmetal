class_name Profile
extends RefCounted
## The player's profile: experience and level, the rank that comes with the level, the photo, and backing the
## whole save up to a file (to move to another phone) and restoring it. Everything lives in Save.state and
## user://avatar.png on this device; nothing is sent anywhere.

## Ranks climb by level; each has its own colour and frame effect. The player can't pick one: they are earned.
const TIERS := [
	{"id": "rookie", "name": "Rookie", "from": 1, "color": Color("8d8780"), "fx": "none"},
	{"id": "rust", "name": "Rust", "from": 5, "color": Color("c9773d"), "fx": "glow"},
	{"id": "steel", "name": "Steel", "from": 12, "color": Color("cfd9e3"), "fx": "shine"},
	{"id": "gold", "name": "Gold", "from": 22, "color": Color("ffc83a"), "fx": "sparks"},
	{"id": "platinum", "name": "Platinum", "from": 35, "color": Color("8fe9ff"), "fx": "aura"},
	{"id": "diamond", "name": "Diamond", "from": 50, "color": Color("c690ff"), "fx": "prism"},
]
const AVATAR := "user://avatar.png"
const AVATAR_PX := 256
const BACKUP_SALT := "ironmetal-wasteland-backup-1"

static var _avatar: Texture2D
static var _avatar_loaded := false


# ---------- levels ----------

## Experience needed to go from `level` to the next one: a little more each level.
static func step(level: int) -> int:
	return 200 + 60 * level


## Total experience at which `level` begins.
static func xp_at(level: int) -> int:
	var t := 0
	for l in range(1, level):
		t += step(l)
	return t


static func xp() -> int:
	return int(Save.state.get("xp", 0))


static func level() -> int:
	var x := xp()
	var l := 1
	while x >= xp_at(l + 1) and l < 99:
		l += 1
	return l


static func tier_of(lvl: int) -> Dictionary:
	var out: Dictionary = TIERS[0]
	for t in TIERS:
		if lvl >= int(t.from):
			out = t
	return out


static func tier() -> Dictionary:
	return tier_of(level())


## 0..1 progress through the current level.
static func progress() -> float:
	var l := level()
	return clamp(float(xp() - xp_at(l)) / step(l), 0.0, 1.0)


## Experience for one match. Returns {xp, from_level, to_level}.
static func award(result: String, kills: int, wave: int, net: bool) -> Dictionary:
	var gain := 40 + kills * 30 + (120 if result == "win" else 0) + wave * 25
	if net:
		gain = int(gain * 1.25)   # playing with people pays a little more
	var before := level()
	Save.state.xp = xp() + gain
	Save.write()
	return {"xp": gain, "from": before, "to": level()}


## Players who played before levels existed start with the experience their record has earned.
static func ensure_started() -> void:
	if Save.state.has("xp"):
		Save.state.xp = int(Save.state.xp)
		return
	var s: Dictionary = Save.state.stats
	Save.state.xp = int(s.get("matches", 0)) * 40 + int(s.get("wins", 0)) * 120 + int(s.get("kills", 0)) * 30
	Save.write()


# ---------- photo ----------

static func avatar() -> Texture2D:
	if not _avatar_loaded:
		_avatar_loaded = true
		if FileAccess.file_exists(AVATAR):
			var img := Image.load_from_file(AVATAR)
			if img:
				_avatar = ImageTexture.create_from_image(img)
	return _avatar


## Reads a picked picture (a path, or a content:// address from the phone's picker), crops it square around
## the centre, and keeps a small copy. Returns "" or an error message key.
static func set_avatar_from(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return "Couldn't open that picture"
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() > 8 and bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes.size() > 3 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.size() > 12 and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		for f in [img.load_jpg_from_buffer, img.load_png_from_buffer, img.load_webp_from_buffer]:
			if f.call(bytes) == OK:
				err = OK
				break
	if err != OK:
		return "That picture format isn't supported"
	var side: int = min(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.resize(AVATAR_PX, AVATAR_PX, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	img.save_png(AVATAR)
	_avatar = ImageTexture.create_from_image(img)
	_avatar_loaded = true
	return ""


static func clear_avatar() -> void:
	if FileAccess.file_exists(AVATAR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AVATAR))
	_avatar = null


# ---------- backup ----------

static func _sig(save_json: String, avatar_b64: String) -> String:
	return (BACKUP_SALT + save_json + avatar_b64).sha256_text()


## The whole profile in one file: progress, cars, upgrades, settings and the photo.
static func backup_text() -> String:
	var save_json := JSON.stringify(Save.state)
	var av := ""
	if FileAccess.file_exists(AVATAR):
		av = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(AVATAR))
	return JSON.stringify({"game": "ironmetal", "format": 1, "made": Time.get_datetime_string_from_system(),
		"name": Save.player_name(), "level": level(), "save": save_json, "avatar": av, "sig": _sig(save_json, av)})


## Checks a backup file's text. Returns {ok, error, name, level, points} without changing anything.
static func inspect_backup(text: String) -> Dictionary:
	var d = JSON.parse_string(text)
	if not (d is Dictionary) or d.get("game") != "ironmetal":
		return {"ok": false, "error": "That isn't an IronMetal backup file"}
	if _sig(str(d.get("save", "")), str(d.get("avatar", ""))) != d.get("sig"):
		return {"ok": false, "error": "That backup file is damaged or was changed"}
	var s = JSON.parse_string(str(d.save))
	if not (s is Dictionary):
		return {"ok": false, "error": "That backup file is damaged or was changed"}
	return {"ok": true, "name": str(d.get("name", "")), "level": int(d.get("level", 1)), "points": int(s.get("points", 0)), "data": d}


## Replaces this phone's progress with the backup's (after inspect_backup said ok).
static func restore(d: Dictionary) -> void:
	var s: Dictionary = JSON.parse_string(str(d.save))
	var keep_ver = Save.state.get("granted_version", "")
	Save.state = Save._fresh()
	for k in s:
		Save.state[k] = s[k]
	Save.state.granted_version = keep_ver   # a restore doesn't hand out the test-build scrap again
	Save.reload_state()
	if str(d.get("avatar", "")) != "":
		var f := FileAccess.open(AVATAR, FileAccess.WRITE)
		if f:
			f.store_buffer(Marshalls.base64_to_raw(d.avatar))
			f.close()
	else:
		clear_avatar()
	_avatar_loaded = false
	_avatar = null
	Save.write()
