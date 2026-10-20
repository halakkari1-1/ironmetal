extends Node
## Language: English text is the key, Arabic lives in data/ar.json.
## t("Wreck {n} cars", {"n": 5}) fills placeholders. Godot shapes Arabic and lays it out right-to-left by itself.

signal changed

var lang := "en"
var _ar := {}


func _ready() -> void:
	var f := FileAccess.open("res://data/ar.json", FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_ar = parsed


func set_lang(l: String) -> void:
	lang = "ar" if l == "ar" else "en"
	changed.emit()


func is_ar() -> bool:
	return lang == "ar"


func t(s: String, vars: Dictionary = {}) -> String:
	var out: String = _ar.get(s, s) if lang == "ar" else s
	for k in vars:
		out = out.replace("{%s}" % k, str(vars[k]))
	return out
