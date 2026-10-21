extends Node
## Multiplayer on the local network: the same Wi-Fi, or one phone's hotspot. No server and no internet needed.
## One device hosts the room. In a match the host runs everything that decides the game; the other devices send
## their controls and show what the host tells them (see Match: snapshots for movement, events for decisions).
## Rooms are found three ways: the host's broadcast beacon, asking every address on the local network directly
## (many Android phones drop broadcasts), or typing the host's address shown in its room.

signal rooms_changed
signal lobby_changed
signal status(text: String)            # connection progress and errors, already translated
signal start_match(cfg: Dictionary)
signal session_over(reason: String)    # the room closed under us (host left, kicked, connection lost)

const PORT := 24680
const DISCO_PORT := 24681
const PROTO := 1                       # bump whenever the messages change: older builds are refused politely
const MAX_PLAYERS := 9
const SNAP_HZ := 20.0
const INPUT_HZ := 30.0
const COLORS := ["ffb347", "62e07a", "5cc8ff", "ff5a4a", "c58bff", "ffe45c", "ff8fd0", "7ef0e0", "e8e0d0"]

var role := ""                         # "", "host", "client"
var rooms := {}                        # address -> beacon info plus "seen" (msec)
var lobby := {}                        # room settings and players; the host owns it, clients get copies
var rtt := 0.03                        # round trip to the host, seconds
var game: Match = null
var browsing := false
var _udp: PacketPeerUDP
var _beacon_t := 0.0
var _scan_t := 0.0
var _scan_list: Array = []
var _snap_t := 0.0
var _in_t := 0.0
var _ping_t := 0.0
var _loaded := {}
var _wait_t := 0.0
var _connect_t := 0.0
var event_counts := {}                 # for tests: how many of each event this client received


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(func(_id): pass)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func():
		status.emit(I18n.t("Couldn't reach that room"))
		leave())
	multiplayer.server_disconnected.connect(func():
		leave()
		session_over.emit(I18n.t("The host closed the room")))


func active() -> bool:
	return role != ""


func is_host() -> bool:
	return role == "host"


func my_peer() -> int:
	return multiplayer.get_unique_id() if role != "" else 1


func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


# ---------- addresses and discovery ----------

## This device's addresses on local networks (Wi-Fi, hotspot), most likely first.
func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		var p := a.split(".")
		if p.size() != 4:
			continue
		var b := int(p[1])
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and b >= 16 and b <= 31):
			out.append(a)
	out.sort_custom(func(x, y): return x.begins_with("192.168.") and not y.begins_with("192.168."))
	return out


func _open_udp() -> void:
	if _udp:
		return
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	if _udp.bind(DISCO_PORT) != OK:
		_udp.bind(0)          # port taken (another copy on this device): still able to ask and hear answers


func _close_udp() -> void:
	if _udp:
		_udp.close()
		_udp = null


func browse(on: bool) -> void:
	browsing = on
	if on:
		_open_udp()
		_scan_t = 0.0
	elif role != "host":
		_close_udp()


func _beacon() -> PackedByteArray:
	var host_name := ""
	for p in lobby.get("players", []):
		if p.peer == 1:
			host_name = p.name
	return JSON.stringify({"g": "ironmetal", "p": PROTO, "v": version(), "name": host_name, "mode": lobby.get("mode", ""),
		"map": lobby.get("map", 0), "n": lobby.get("players", []).size(), "max": MAX_PLAYERS, "open": game == null}).to_utf8_buffer()


func _send_udp(ip: String, data: PackedByteArray) -> void:
	_udp.set_dest_address(ip, DISCO_PORT)
	_udp.put_packet(data)


func _discovery(dt: float) -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var port := _udp.get_packet_port()
		var txt := pkt.get_string_from_utf8()
		if txt == "IMQ?":
			if role == "host":
				_udp.set_dest_address(ip, port)
				_udp.put_packet(_beacon())
			continue
		if role == "host" or not browsing:
			continue
		var info = JSON.parse_string(txt)
		if info is Dictionary and info.get("g") == "ironmetal":
			info.seen = Time.get_ticks_msec()
			var fresh := not rooms.has(ip)
			rooms[ip] = info
			if fresh:
				rooms_changed.emit()
	if role == "host":
		_beacon_t -= dt
		if _beacon_t <= 0:
			_beacon_t = 1.0
			_send_udp("255.255.255.255", _beacon())
	elif browsing:
		_scan_t -= dt
		if _scan_t <= 0:
			_scan_t = 2.5
			_scan_list = ["255.255.255.255"]
			for a in local_ips():
				var base: String = a.substr(0, a.rfind(".") + 1)
				for i in range(1, 255):
					if base + str(i) != a:
						_scan_list.append(base + str(i))
		for i in min(40, _scan_list.size()):   # a few dozen per frame: the whole network every ~2.5 s
			_send_udp(_scan_list.pop_back(), "IMQ?".to_utf8_buffer())
		var now := Time.get_ticks_msec()
		for ip in rooms.keys():
			if now - int(rooms[ip].seen) > 6000:
				rooms.erase(ip)
				rooms_changed.emit()


# ---------- room ----------

func _me(peer: int) -> Dictionary:
	var car: String = Save.state.selected
	return {"peer": peer, "id": Save.state.player_id, "name": Save.player_name(), "color": COLORS[int(Save.state.player_color) % COLORS.size()],
		"team": 1, "car": car, "ups": Save.upgrades(car).duplicate(), "ready": peer == 1}


func host() -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		status.emit(I18n.t("Couldn't open a room on this network"))
		return false
	multiplayer.multiplayer_peer = peer
	role = "host"
	lobby = {"mode": "deathmatch", "map": 0, "bots": 2, "bot_diff": 1, "upgrades": true, "players": [_me(1)]}
	_open_udp()
	lobby_changed.emit()
	return true


func join(ip: String) -> void:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip.strip_edges(), PORT) != OK:
		status.emit(I18n.t("Couldn't reach that room"))
		return
	multiplayer.multiplayer_peer = peer
	role = "client"
	_connect_t = 7.0
	status.emit(I18n.t("Connecting…"))


func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = ""
	lobby = {}
	_loaded = {}
	_connect_t = 0.0
	if not browsing:
		_close_udp()


func _on_connected() -> void:
	_connect_t = 0.0
	var me := _me(0)
	_hello.rpc_id(1, PROTO, me.id, me.name, me.color, me.car, me.ups)


@rpc("any_peer", "call_remote", "reliable")
func _hello(proto: int, pid: String, pname: String, color: String, car: String, ups: Dictionary) -> void:
	if role != "host":
		return
	var from := multiplayer.get_remote_sender_id()
	var why := ""
	if proto != PROTO:
		why = "version"
	elif lobby.players.size() >= MAX_PLAYERS:
		why = "full"
	elif game != null:
		why = "busy"
	if why != "":
		_rejected.rpc_id(from, why)
		get_tree().create_timer(0.5).timeout.connect(func():
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(from))
		return
	var used: Array = lobby.players.map(func(p): return p.color)
	if used.has(color):
		for c in COLORS:
			if not used.has(c):
				color = c
				break
	var t1: int = lobby.players.filter(func(p): return p.team == 1).size()
	var t2: int = lobby.players.size() - t1
	lobby.players.append({"peer": from, "id": pid, "name": pname.substr(0, 16), "color": color, "team": 2 if t2 < t1 else 1,
		"car": Data.car(car).id, "ups": ups, "ready": false})
	_sync()


@rpc("authority", "call_remote", "reliable")
func _rejected(why: String) -> void:
	var msg := {"version": "That room runs a different version of the game. Update both phones.",
		"full": "That room is full", "busy": "That room is already in a match"}
	status.emit(I18n.t(msg.get(why, "Couldn't join")))
	leave()


@rpc("authority", "call_remote", "reliable")
func _lobby(l: Dictionary) -> void:
	lobby = l
	lobby_changed.emit()


func _sync() -> void:
	lobby_changed.emit()
	if role == "host":
		_lobby.rpc(lobby)


func me() -> Dictionary:
	for p in lobby.get("players", []):
		if p.peer == my_peer():
			return p
	return {}


## Changes this player's own entry: car, team, colour, ready.
func set_me(d: Dictionary) -> void:
	if role == "host":
		_apply_me(1, d)
	elif role == "client":
		_set_me.rpc_id(1, d)


@rpc("any_peer", "call_remote", "reliable")
func _set_me(d: Dictionary) -> void:
	if role == "host":
		_apply_me(multiplayer.get_remote_sender_id(), d)


func _apply_me(peer: int, d: Dictionary) -> void:
	for p in lobby.players:
		if p.peer == peer:
			for k in ["car", "ups", "ready", "team", "color", "name"]:
				if d.has(k):
					p[k] = d[k]
	_sync()


## Host: a room setting (mode, map, bots, bot_diff, upgrades).
func set_room(k: String, v) -> void:
	if role != "host":
		return
	lobby[k] = v
	_sync()


func all_ready() -> bool:
	for p in lobby.get("players", []):
		if not p.ready and p.peer != 1:
			return false
	return true


func max_bots() -> int:
	return max(0, MAX_PLAYERS - lobby.get("players", []).size())


func _on_peer_gone(id: int) -> void:
	if role != "host":
		return
	lobby.players = lobby.players.filter(func(p): return p.peer != id)
	_loaded.erase(id)
	if game:
		game.peer_left(id)
	_sync()


# ---------- starting a match ----------

## Host: builds the same list of cars for every device and starts the match everywhere.
func start() -> void:
	if role != "host":
		return
	var mode: String = lobby.mode
	var diff: Dictionary = Data.DIFFICULTY[int(lobby.bot_diff)]
	var order := range(10)
	order.shuffle()
	var roster: Array = []
	var counts := {1: 0, 2: 0}
	for p in lobby.players:
		var team := 0
		if mode == "team":
			team = int(p.team)
		elif mode == "survival":
			team = 1
		counts[team] = counts.get(team, 0) + 1
		roster.append({"nid": roster.size() + 1, "peer": p.peer, "bot": false, "name": p.name, "color": "#" + p.color, "team": team,
			"car": p.car, "ups": p.ups, "spawn": order[roster.size() % order.size()]})
	if mode != "survival":
		var pool := Data.CARS.filter(func(c): return c.price <= diff.max_price)
		pool.shuffle()
		for i in min(int(lobby.bots), max_bots()):
			var team := 0
			if mode == "team":
				team = 1 if counts.get(1, 0) <= counts.get(2, 0) else 2
				counts[team] += 1
			roster.append({"nid": roster.size() + 1, "peer": 0, "bot": true, "name": "", "color": "#ffffff", "team": team,
				"car": pool[i % pool.size()].id, "ups": {}, "spawn": order[roster.size() % order.size()]})
	var cfg := {"map": int(lobby.map), "mode": mode, "diff": int(lobby.bot_diff), "upgrades": bool(lobby.upgrades), "roster": roster}
	for p in lobby.players:
		p.ready = p.peer == 1
	_sync()
	_start.rpc(cfg)
	_start(cfg)


@rpc("authority", "call_remote", "reliable")
func _start(cfg: Dictionary) -> void:
	_loaded = {}
	_wait_t = 15.0
	start_match.emit(cfg)


## Called by the menu once this device has built the match.
func match_ready(m: Match) -> void:
	game = m
	_snap_t = 0.0
	if role == "host":
		_loaded[1] = true
		_check_go()
	else:
		_loaded_ack.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _loaded_ack() -> void:
	if role == "host":
		_loaded[multiplayer.get_remote_sender_id()] = true
		_check_go()


func _check_go() -> void:
	if game == null:
		return
	for p in lobby.players:
		if not _loaded.has(p.peer) and _wait_t > 0:
			return
	game.go()


func match_over() -> void:
	game = null


# ---------- in a match ----------

func tick(m: Match, dt: float) -> void:
	if role == "host":
		if m.state == "waiting":
			_wait_t -= dt
			if _wait_t <= 0:
				_check_go()   # someone is very slow to load: start without waiting any longer
		_snap_t -= dt
		if _snap_t <= 0:
			_snap_t = 1.0 / SNAP_HZ
			_snap.rpc(m.time, m.state, m.make_snap())
	elif role == "client":
		_in_t -= dt
		if _in_t <= 0:
			_in_t = 1.0 / INPUT_HZ
			var p := m.player
			_net_input.rpc_id(1, p.throttle, p.steer, p.firing)
		_ping_t -= dt
		if _ping_t <= 0:
			_ping_t = 1.0
			_ping.rpc_id(1, Time.get_ticks_msec())


@rpc("authority", "call_remote", "unreliable_ordered")
func _snap(t: float, st: String, data: PackedFloat32Array) -> void:
	if game and game.net_role == "client":
		game.on_snap(t, st, data)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_input(th: float, st: float, fire: bool) -> void:
	if role != "host" or game == null:
		return
	var c := game.car_for_peer(multiplayer.get_remote_sender_id())
	if c:
		c.throttle = clamp(th, -1.0, 1.0)
		c.steer = clamp(st, -1.0, 1.0)
		c.firing = fire


func send_button(what: String) -> void:
	_button.rpc_id(1, what)


@rpc("any_peer", "call_remote", "reliable")
func _button(what: String) -> void:
	if role != "host" or game == null:
		return
	var c := game.car_for_peer(multiplayer.get_remote_sender_id())
	if c:
		game.remote_button(c, what)


func send_event(name: String, args: Array) -> void:
	_event.rpc(name, args)


@rpc("authority", "call_remote", "reliable")
func _event(name: String, args: Array) -> void:
	event_counts[name] = event_counts.get(name, 0) + 1
	if game and game.net_role == "client":
		game.net_event(name, args)


@rpc("any_peer", "call_remote", "unreliable")
func _ping(t: int) -> void:
	_pong.rpc_id(multiplayer.get_remote_sender_id(), t)


@rpc("any_peer", "call_remote", "unreliable")
func _pong(t: int) -> void:
	rtt = lerp(rtt, (Time.get_ticks_msec() - t) / 1000.0, 0.3)


func _process(dt: float) -> void:
	_discovery(dt)
	if _connect_t > 0:
		_connect_t -= dt
		if _connect_t <= 0 and role == "client" and lobby.is_empty():
			status.emit(I18n.t("Couldn't reach that room"))
			leave()
