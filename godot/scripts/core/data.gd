extends Node
## Static game data: vehicles and their abilities, maps, difficulty and economy.
## Everything the game needs about a car lives in its entry; a new car is a new entry plus assets/cars/<id>.glb.
##
## stats are 1..10 and map to real values in car_stats(); handling is turning response.
## model.length is the in-game length in metres; muzzles/rocket are points in the model's normalised box
##   (x: -1 left .. 1 right, y: 0 ground .. 1 roof, z: -1 rear .. 1 front).
## special: duration and cooldown in seconds, radius in metres.
## sound: engine loop file, gun calibre (pitch < 1 heavy, > 1 light), ability voice.

const LORE := "Twenty years after the oil ran dry, the old refineries became arenas. Every season the wasteland clans send their machines to the Iron Cup. Win, and you eat. Lose, and the scrappers strip what is left of you."

const CARS := [
	{
		"id": "ghost", "name": "WASTELAND GHOST", "price": 0, "cls": "medium",
		"desc": "Ghost of the wasteland. A practical, balanced survival machine that leans on its guns and a short smoke cover to slip out of bad fights.",
		"desc_ar": "شبح الأراضي المقفرة. مركبة نجاة قتالية عملية ومتوازنة، تعتمد على أسلحتها الأساسية والتمويه المؤقت لتجاوز المواجهات الصعبة.",
		"strong": "Balanced, flexible, easy to drive", "weak": "Not the best at speed, armor or damage",
		"stats": {"speed": 6, "armor": 6, "gun": 5, "rocket": 6, "handling": 6},
		"model": {"length": 6.2, "muzzles": [[0.05, 0.98, 0.15]], "rocket": [0, 0.95, -0.1]},
		"special": {"id": "smoke", "name": "Smoke Screen", "desc": "Drops a smoke cloud: enemies lose track of you for 3.5 s and you get a burst of speed.", "cooldown": 13.0, "duration": 3.5, "radius": 9.0},
		"sound": {"gun": 1.0, "ability": "smoke"},
	},
	{
		"id": "venom", "name": "QUEEN VENOM", "price": 1500, "cls": "sports",
		"desc": "Queen of speed and evasion. Lives on quick dashes and hit-and-run attacks, but takes less punishment than the heavy machines.",
		"desc_ar": "ملكة السرعة والمراوغة. تعتمد على الاندفاع السريع والهجمات الخاطفة، لكنها أقل تحملاً للضرر من المركبات الثقيلة.",
		"strong": "Speed and agility", "weak": "Low durability",
		"stats": {"speed": 10, "armor": 5, "gun": 6, "rocket": 5, "handling": 9},
		"model": {"length": 5.6, "muzzles": [[0.25, 0.95, 0.2], [-0.25, 0.95, 0.2]], "rocket": [0, 0.95, -0.2]},
		"special": {"id": "dash", "name": "Venom Dash", "desc": "A 1.3 s burst at double speed that also halves incoming damage, to dodge or reposition.", "cooldown": 6.0, "duration": 1.3},
		"sound": {"gun": 1.25, "ability": "dash"},
	},
	{
		"id": "toxic", "name": "TOXIC VIPER", "price": 2000, "cls": "sports",
		"desc": "The poisoned viper. Controls space with short-lived toxic zones that wear down anyone who stays inside.",
		"desc_ar": "الأفعى السامة. تتحكم بمساحة المعركة عبر مناطق سامة مؤقتة تضعف الخصوم الذين يبقون داخلها.",
		"strong": "Area control, forces enemies to move", "weak": "Damage over time can be escaped",
		"stats": {"speed": 8, "armor": 6, "gun": 6, "rocket": 5, "handling": 8},
		"model": {"length": 5.8, "muzzles": [[0.3, 0.95, 0.1], [-0.3, 0.95, 0.1]], "rocket": [0, 0.95, -0.2]},
		"special": {"id": "toxic", "name": "Toxic Cloud", "desc": "Throws a toxic cloud 9 m ahead: 9 m wide, burns 14 HP per second for 6 s.", "cooldown": 9.0, "duration": 6.0, "radius": 9.0},
		"sound": {"gun": 1.15, "ability": "toxic"},
	},
	{
		"id": "megalodon", "name": "MEGALODON", "price": 2500, "cls": "medium",
		"desc": "The sea predator. Rams and surges to throw enemies off balance, sending them skidding out of control.",
		"desc_ar": "المفترس البحري. يستخدم هجمات الصدم والاندفاع لإرباك الخصوم ودفعهم إلى الانزلاق وفقدان السيطرة مؤقتاً.",
		"strong": "Surge and disruption", "weak": "Must get close; weak at long range",
		"stats": {"speed": 7, "armor": 6, "gun": 7, "rocket": 5, "handling": 7},
		"model": {"length": 6.4, "muzzles": [[0.2, 0.92, 0.25], [-0.2, 0.92, 0.25]], "rocket": [0, 0.9, -0.2]},
		"special": {"id": "riptide", "name": "Riptide", "desc": "A surge forward that blasts a wave ahead (14 m cone): pushes cars away and makes them skid for 1.5 s.", "cooldown": 8.0, "duration": 1.5, "radius": 14.0},
		"sound": {"gun": 1.05, "ability": "riptide"},
	},
	{
		"id": "siren", "name": "BLUE SIREN", "price": 3000, "cls": "armored",
		"desc": "Field control unit. Electric pulses jam enemy guns and slow them down for a moment.",
		"desc_ar": "وحدة السيطرة الميدانية. تستخدم النبضات الكهربائية لتعطيل الخصوم وإبطاء حركتهم مؤقتاً.",
		"strong": "Disables enemies, solid armor", "weak": "Slower and less agile than sports cars",
		"stats": {"speed": 6, "armor": 7, "gun": 6, "rocket": 6, "handling": 6},
		"model": {"length": 6.5, "muzzles": [[0.3, 0.97, 0.1], [-0.3, 0.97, 0.1]], "rocket": [0, 0.97, -0.25]},
		"special": {"id": "pulse", "name": "Shock Pulse", "desc": "Electric pulse, 16 m around you: enemies are slowed 50% and their guns jam for 2.5 s.", "cooldown": 12.0, "duration": 2.5, "radius": 16.0},
		"sound": {"gun": 1.0, "ability": "zap"},
	},
	{
		"id": "reaper", "name": "YELLOW REAPER", "price": 3500, "cls": "tracked",
		"desc": "The yellow reaper. A heavy breaching machine that charges and crashes through enemy defenses.",
		"desc_ar": "الحصادة الصفراء. مركبة اقتحام ثقيلة تعتمد على الاندفاع والاصطدام لتدمير دفاعات الخصوم.",
		"strong": "Head-on attacks, close fights", "weak": "Slow, poor turning",
		"stats": {"speed": 4, "armor": 8, "gun": 6, "rocket": 6, "handling": 3},
		"model": {"length": 7.2, "muzzles": [[0.25, 0.98, -0.1], [-0.25, 0.98, -0.1]], "rocket": [0, 0.98, -0.3]},
		"special": {"id": "ram", "name": "Reaper Charge", "desc": "A 1.4 s charge: anything you hit takes heavy damage and is thrown aside.", "cooldown": 9.0, "duration": 1.4},
		"sound": {"gun": 0.85, "ability": "charge"},
	},
	{
		"id": "rex", "name": "REX RAMPAGE", "price": 4000, "cls": "monster",
		"desc": "Dinosaur fury. Lives on charges, mechanical strikes and heavy collisions against nearby enemies.",
		"desc_ar": "غضب الديناصور. يعتمد على الاندفاع والضربات الميكانيكية والاصطدامات القوية لإلحاق الضرر بالخصوم القريبين.",
		"strong": "Close combat, good durability", "weak": "Clumsy turning, must get close",
		"stats": {"speed": 6, "armor": 8, "gun": 7, "rocket": 5, "handling": 5},
		"model": {"length": 8.8, "muzzles": [[0.2, 0.98, 0.1], [-0.2, 0.98, 0.1]], "rocket": [0, 1.0, -0.1]},
		"special": {"id": "whip", "name": "Tail Whip", "desc": "Spins its tail: everything within 10 m takes damage and is knocked back.", "cooldown": 10.0, "radius": 10.0},
		"sound": {"gun": 0.95, "ability": "roar"},
	},
	{
		"id": "titan", "name": "BLOOD TITAN", "price": 4500, "cls": "tank",
		"desc": "The red titan. Huge firepower and heavy shots, but its main gun needs good timing and a longer recharge.",
		"desc_ar": "العملاق الأحمر. يمتلك قوة نارية مرتفعة وضربات ثقيلة، لكن أسلحته الرئيسية تحتاج إلى توقيت جيد وفترات إعادة شحن أطول.",
		"strong": "Damage and explosive attacks", "weak": "Slow, long recharge",
		"stats": {"speed": 4, "armor": 8, "gun": 7, "rocket": 7, "handling": 4},
		"model": {"length": 7.7, "muzzles": [[0.35, 0.85, 0.3], [-0.35, 0.85, 0.3]], "rocket": [0, 0.9, 0.5]},
		"special": {"id": "shell", "name": "Titan Shell", "desc": "Main cannon: a slow, huge shell (85 damage, 11 m blast). A red line shows its path, so it can be dodged.", "cooldown": 11.0, "radius": 11.0},
		"sound": {"gun": 0.8, "ability": "cannon"},
	},
	{
		"id": "colossus", "name": "IRON COLOSSUS", "price": 5000, "cls": "heavy",
		"desc": "The armored giant. Soaks up huge damage and dominates with heavy weapons, at the cost of slow movement and acceleration.",
		"desc_ar": "العملاق المدرع. يتحمل أضراراً كبيرة ويستخدم تسليحه الثقيل للسيطرة على ساحة المعركة، مقابل بطء الحركة والتسارع.",
		"strong": "High health and armor", "weak": "Slow, hard to turn",
		"stats": {"speed": 3, "armor": 8, "gun": 6, "rocket": 6, "handling": 3},
		"model": {"length": 8.4, "muzzles": [[0.3, 0.98, 0.25], [-0.3, 0.98, 0.25]], "rocket": [0, 0.98, -0.2]},
		"special": {"id": "shield", "name": "Bulwark", "desc": "Raises a shield that cuts incoming damage by 70% for 5 s.", "cooldown": 16.0, "duration": 5.0},
		"sound": {"gun": 0.75, "ability": "shield"},
	},
]

const UPGRADES := [
	{"id": "gun", "name": "Machine Gun", "desc": "Bullet damage"},
	{"id": "rocket", "name": "Rockets", "desc": "Rocket damage and blast"},
	{"id": "armor", "name": "Armor", "desc": "Maximum health"},
	{"id": "speed", "name": "Engine", "desc": "Top speed and acceleration"},
	{"id": "special", "name": "Special", "desc": "Stronger, faster recharge"},
]
const MAX_UPGRADE := 5

## Arena maps. size is the side of the square in metres; colours tint the ground, sun and sky.
const MAPS := [
	{"id": "scrapyard", "name": "Scrapyard", "tag": "Junk piles and a watchtower", "size": 132.0,
		"ground": Color("8a7058"), "sun": Color("ffcf9a"), "sky_top": Color("3b4a63"), "horizon": Color("c9a582"), "concrete": 0.0, "event": "artillery"},
	{"id": "refinery", "name": "Refinery", "tag": "Fuel tanks ready to blow", "size": 142.0,
		"ground": Color("8c8778"), "sun": Color("e6ecff"), "sky_top": Color("41505f"), "horizon": Color("b9bcc2"), "concrete": 0.8, "event": "rupture"},
	{"id": "dustbowl", "name": "Dust Bowl", "tag": "Open ground, rock pillars", "size": 150.0,
		"ground": Color("c39a66"), "sun": Color("ffe2b0"), "sky_top": Color("6f8bab"), "horizon": Color("e3c79c"), "concrete": 0.0, "event": "sandstorm"},
	{"id": "shanty", "name": "Shanty Town", "tag": "Three towers, tight streets", "size": 138.0,
		"ground": Color("7a6452"), "sun": Color("ffb27a"), "sky_top": Color("2a2638"), "horizon": Color("a5786a"), "concrete": 0.45, "event": "artillery"},
	{"id": "outpost", "name": "The Outpost", "tag": "Fight around the fortress", "size": 142.0,
		"ground": Color("9b8366"), "sun": Color("ffd9a8"), "sky_top": Color("4d5d75"), "horizon": Color("cdb59a"), "concrete": 0.42, "event": "artillery"},
]

const DIFFICULTY := [
	{"id": "easy", "name": "Easy", "enemies": 3, "dmg": 0.5, "accuracy": 0.45, "aggression": 0.6, "focus": 1.15, "level": 0, "hp": 0.75, "max_price": 2500, "reward": 1.0, "base": 100},
	{"id": "normal", "name": "Medium", "enemies": 4, "dmg": 0.72, "accuracy": 0.65, "aggression": 0.8, "focus": 0.95, "level": 1, "hp": 0.9, "max_price": 4000, "reward": 1.6, "base": 160},
	{"id": "hard", "name": "Hard", "enemies": 5, "dmg": 0.9, "accuracy": 0.85, "aggression": 1.0, "focus": 0.8, "level": 2, "hp": 1.0, "max_price": 99999, "reward": 2.5, "base": 250},
]

const POWERS := {
	"railgun": {"name": "Railgun", "short": "RAIL", "ammo": 3, "desc": "Instant beam, punches through armor"},
	"napalm": {"name": "Napalm", "short": "NAPLM", "ammo": 3, "desc": "Rockets leave burning ground"},
	"nuke": {"name": "Mini Nuke", "short": "NUKE", "ammo": 1, "desc": "One rocket. Huge blast."},
}

const KILL_REWARD := 18
const START_POINTS := 300

## Daily contracts: three per day, picked from these templates with a seed from the date.
const CONTRACTS := [
	{"id": "kills", "text": "Wreck {n} cars", "goals": [5, 8, 12], "reward": 22},
	{"id": "rocketKills", "text": "Wreck {n} cars with rockets", "goals": [2, 3, 5], "reward": 55},
	{"id": "barrels", "text": "Blow up {n} fuel barrels", "goals": [4, 6, 10], "reward": 30},
	{"id": "airdrops", "text": "Grab {n} airdrops", "goals": [1, 2, 3], "reward": 110},
	{"id": "streak", "text": "Score a Double Wreck", "goals": [1], "reward": 180},
	{"id": "bounty", "text": "Claim {n} bounties", "goals": [1, 2], "reward": 120},
	{"id": "winMap", "text": "Win a match on {map}", "goals": [1], "reward": 200},
	{"id": "winVet", "text": "Win on Medium or Hard", "goals": [1], "reward": 260},
	{"id": "wave", "text": "Reach wave {n} in Survival", "goals": [4, 6, 8], "reward": 45},
]


func car(id: String) -> Dictionary:
	for c in CARS:
		if c.id == id:
			return c
	return CARS[0]


func map_by_id(id: String) -> Dictionary:
	for m in MAPS:
		if m.id == id:
			return m
	return MAPS[0]


func upgrade_cost(c: Dictionary, level: int) -> int:
	var base: float = 120.0 + c.price * 0.05
	return int(round(base * (level + 1) / 10.0) * 10)


## Converts 1..10 ratings plus upgrade levels into the numbers the game uses.
func car_stats(c: Dictionary, up: Dictionary = {}) -> Dictionary:
	var s: Dictionary = c.stats
	var m := func(k: String) -> float: return 1.0 + 0.12 * float(up.get(k, 0))
	return {
		"max_speed": (10.5 + s.speed * 1.1) * (1.0 + 0.05 * float(up.get("speed", 0))),
		"accel": (17.0 + s.speed * 1.3) * m.call("speed"),
		"turn": 1.9 + s.get("handling", 6) * 0.11,
		"hp": round((70 + s.armor * 15) * m.call("armor")),
		"gun_dmg": (1.1 + s.gun * 0.2) * m.call("gun"),
		"rocket_dmg": (22.0 + s.rocket * 3) * m.call("rocket"),
		"rocket_radius": 6.0 + s.rocket * 0.2 + float(up.get("rocket", 0)) * 0.3,
		"special_power": 1.0 + 0.15 * float(up.get("special", 0)),
		"special_cooldown": c.special.cooldown * (1.0 - 0.08 * float(up.get("special", 0))),
		"mass": 0.7 + s.armor * 0.08,
	}
