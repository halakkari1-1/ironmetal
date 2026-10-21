extends Node
## Player progress and settings, stored in user://save.json on this device.

const PATH := "user://save.json"
const UPGRADE_KEYS := ["gun", "rocket", "armor", "speed", "special"]

var state: Dictionary = {}
var _buying := false


func _fresh() -> Dictionary:
	return {
		"points": Data.START_POINTS,
		"owned": ["ghost"],
		"selected": "ghost",
		"upgrades": {},
		"history": [],
		"stats": {"matches": 0, "wins": 0, "kills": 0},
		"best": {"wave": 0},
		"contracts": null,
		"sound": true,
		"music": true,
		"graphics": "auto",   # auto | high | medium | low
		"fps": 60,            # 60 or 30 (battery saver)
		"scheme": "classic",
		"layout": null,
		"camera": "near",
		"volume": {"master": 0.8, "music": 0.6, "sfx": 0.9},
		"lang": "en",
		"player_id": "",      # random id made on first launch, used to recognise this player in multiplayer
		"player_name": "",
		"player_color": 0,
	}


func _ready() -> void:
	state = _fresh()
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text()) if f else null
		if parsed is Dictionary:
			for k in parsed:
				state[k] = parsed[k]
			var vol: Dictionary = _fresh().volume
			vol.merge(state.get("volume", {}), true)
			state.volume = vol
	_normalize()
	_validate()
	if str(state.player_id).length() < 16:
		state.player_id = _new_id()
		write()
	I18n.set_lang(state.lang)


static func _new_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hexs := ""
	for i in 16:
		hexs += "%02x" % rng.randi_range(0, 255)
	return hexs


## Shown above your car and in rooms; falls back to "Player" plus the start of the id until one is chosen.
func player_name() -> String:
	var n := str(state.get("player_name", "")).strip_edges()
	return n if n != "" else "Player-" + str(state.player_id).substr(0, 4).to_upper()


## JSON stores every number as a float; counters, prices and levels go back to whole numbers.
func _normalize() -> void:
	state.points = int(state.points)
	for id in state.upgrades:
		for k in state.upgrades[id]:
			state.upgrades[id][k] = int(state.upgrades[id][k])
	if state.contracts is Dictionary:
		for c in state.contracts.list:
			for k in ["goal", "progress", "reward"]:
				c[k] = int(c[k])
	for k in state.stats:
		state.stats[k] = int(state.stats[k])
	state.best.wave = int(state.best.wave)
	state.fps = int(state.fps)
	state.player_color = int(state.get("player_color", 0))


func _validate() -> void:
	var ids := {}
	for c in Data.CARS:
		ids[c.id] = true
	var owned: Array = []
	for id in state.owned:
		if ids.has(id) and not owned.has(id):
			owned.append(id)
	if not owned.has("ghost"):
		owned.push_front("ghost")
	state.owned = owned
	if not ids.has(state.selected) or not owned.has(state.selected):
		state.selected = "ghost"


func write() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state))


func selected_car() -> Dictionary:
	return Data.car(state.selected)


func owns(id: String) -> bool:
	return state.owned.has(id)


func upgrades(id: String) -> Dictionary:
	if not state.upgrades.has(id):
		state.upgrades[id] = {"gun": 0, "rocket": 0, "armor": 0, "speed": 0, "special": 0}
	return state.upgrades[id]


func spend(n: int) -> bool:
	if state.points < n:
		return false
	state.points -= n
	write()
	return true


## A second tap during a purchase never charges twice.
func buy(c: Dictionary) -> bool:
	if owns(c.id) or _buying:
		return false
	_buying = true
	var ok := spend(c.price)
	_buying = false
	if not ok:
		return false
	state.owned.append(c.id)
	state.selected = c.id
	write()
	return true


func select(id: String) -> void:
	if owns(id):
		state.selected = id
		write()


func record(entry: Dictionary) -> void:
	state.history.push_front(entry)
	state.history = state.history.slice(0, 30)
	state.points += entry.points
	state.stats.matches += 1
	if entry.result == "win":
		state.stats.wins += 1
	state.stats.kills += entry.kills
	if entry.get("wave", 0):
		state.best.wave = max(state.best.wave, entry.wave)
	write()


# ---------- daily contracts ----------

func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%d-%d-%d" % [d.year, d.month, d.day]


func contracts() -> Array:
	var day := _today()
	if state.contracts == null or state.contracts.day != day:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(day)
		var pool: Array = Data.CONTRACTS.duplicate()
		var list: Array = []
		while list.size() < 3:
			var tpl: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
			var goal: int = tpl.goals[rng.randi_range(0, tpl.goals.size() - 1)]
			var m: Dictionary = Data.MAPS[rng.randi_range(0, Data.MAPS.size() - 1)]
			var reward: float = (tpl.reward * (goal if tpl.goals.size() > 1 else 1) + 80) / 10.0
			list.append({"id": tpl.id, "goal": goal, "progress": 0, "done": false, "map": m.id,
				"text": tpl.text, "map_name": m.name, "reward": int(round(reward) * 10)})
		state.contracts = {"day": day, "list": list}
		write()
	return state.contracts.list


## Applies a finished match to today's contracts. Returns the contracts completed by it.
func apply_contracts(m: Dictionary) -> Array:
	var done: Array = []
	var s: Dictionary = m.stats
	for c in contracts():
		if c.done:
			continue
		var add := 0
		match c.id:
			"kills": add = s.kills
			"rocketKills": add = s.rocket_kills
			"barrels": add = s.barrels
			"airdrops": add = s.airdrops
			"bounty": add = s.bounty
			"streak": add = 1 if s.streak_max >= 2 else 0
			"winMap": add = 1 if m.result == "win" and m.map == c.map else 0
			"winVet": add = 1 if m.result == "win" and (m.diff == "normal" or m.diff == "hard") else 0
		if c.id == "wave":
			c.progress = max(c.progress, s.get("wave", 0))
		else:
			c.progress += add
		if c.progress >= c.goal:
			c.progress = c.goal
			c.done = true
			state.points += c.reward
			done.append(c)
	write()
	return done
