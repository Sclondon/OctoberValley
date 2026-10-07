extends RefCounted
## Every piece of content as plain data: sprite sheets, weapons, passives, heroes, enemies,
## bosses and stages. The names and most numbers come from 8 Bit Evil Returns; distances are
## in metres and speeds in m/s. To add content, add an entry here.

# sheet: [file in res://sprites, frames, fps]
const SHEETS := {
	"zombie": ["zombie", 6, 8.0], "skull": ["skull_enemy", 6, 10.0], "ghost": ["ghost", 6, 8.0],
	"pumpkin": ["pumpkin", 6, 10.0], "werewolf": ["werewolf", 7, 12.0], "scarecrow": ["scarecrow", 6, 6.0],
	"swampthing": ["swampthing", 6, 6.0], "shadowbeast": ["shadowbeast", 6, 8.0],
	"fireball": ["fireball", 7, 14.0], "fireball_explosion": ["fireball_explosion", 7, 20.0],
	"lightning": ["lightning", 9, 24.0], "boomerang": ["boomerang", 4, 16.0], "bearclaw": ["bearclaw", 11, 30.0],
	"crossbow_bolt": ["crossbow_bolt", 1, 1.0], "cursed_sword": ["cursed_sword", 6, 12.0],
	"acid_potion": ["acid_potion", 4, 12.0], "acid_pool": ["acid_pool", 6, 8.0], "bat": ["bat", 4, 12.0],
	"wisp": ["willOWisp", 6, 10.0],
	"candy_corn": ["candy_corn", 6, 8.0], "candy_bar": ["candy_bar", 5, 8.0],
	"candy_bubblegum": ["candy_bubblegum", 6, 8.0], "heart_pump": ["heart_pump", 5, 8.0], "chest": ["chest", 1, 1.0],
	"magic_tome": ["magic_tome", 13, 10.0], "onion": ["onion", 13, 10.0], "tentacle": ["tentacle", 12, 10.0],
	"heartbeat": ["heartbeat", 8, 10.0], "snail_lord": ["snailLord", 13, 10.0], "vacusuck": ["vacusuck", 5, 8.0],
	"holy_cross": ["holy_cross", 10, 10.0], "street_lamp": ["street_lamp", 4, 6.0], "tree_owl": ["tree_owl", 5, 4.0],
}

# ---------------------------------------------------------------- weapons
# Every weapon fires by itself. Stats (missing = the default):
#   cooldown s, damage, speed m/s, amount, area (scale), duration s, pierce (-1 = all),
#   knockback m/s, range m
const WEAPON_DEFAULTS := {
	"cooldown": 1.0, "damage": 10.0, "speed": 14.0, "amount": 1, "area": 1.0,
	"duration": 1.0, "pierce": 1, "knockback": 4.0, "range": 16.0,
}
const MAX_WEAPONS := 5
const MAX_PASSIVES := 5

# `levels` holds the change applied at levels 2..N. A key ending in _mul multiplies.
const WEAPONS := {
	"claw": {
		"name": "Claw", "quote": "RAWR xD", "icon": "owl_claw_skill", "behavior": "slash", "sheet": "bearclaw",
		"base": {"cooldown": 1.0, "damage": 25.0, "knockback": 8.0, "range": 3.4},
		"levels": [
			{"desc": "Also slash behind you", "amount": 1}, {"desc": "+10 damage", "damage": 10.0},
			{"desc": "Bigger slashes", "area": 0.2}, {"desc": "+10 damage", "damage": 10.0},
			{"desc": "Cooldown -15%", "cooldown_mul": 0.85}, {"desc": "Bigger slashes", "area": 0.2},
			{"desc": "+15 damage", "damage": 15.0},
		],
	},
	"crossbow": {
		"name": "CrossBow", "quote": "IT'S HIGH NOOOOON", "icon": "runic_crossbow_skill", "behavior": "bolt",
		"sheet": "crossbow_bolt", "flat": true,
		"base": {"cooldown": 0.5, "damage": 6.0, "speed": 26.0, "pierce": 1, "range": 26.0},
		"levels": [
			{"desc": "Fire 1 more bolt", "amount": 1}, {"desc": "+5 damage", "damage": 5.0},
			{"desc": "Bolts pierce 1 more", "pierce": 1}, {"desc": "Fire 1 more bolt", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0}, {"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "Fire 1 more bolt, pierce 1 more", "amount": 1, "pierce": 1},
		],
	},
	"fireball": {
		"name": "Fireball", "quote": "FLAMIN HOT", "icon": "fireball_icon", "behavior": "bolt",
		"sheet": "fireball", "explode": 2.6,
		"base": {"cooldown": 2.0, "damage": 15.0, "speed": 15.0, "pierce": 1, "range": 22.0},
		"levels": [
			{"desc": "+5 damage", "damage": 5.0}, {"desc": "Throw 1 more fireball", "amount": 1},
			{"desc": "Bigger explosions", "area": 0.25}, {"desc": "+10 damage", "damage": 10.0},
			{"desc": "Throw 1 more fireball", "amount": 1}, {"desc": "Bigger explosions", "area": 0.25},
			{"desc": "+10 damage", "damage": 10.0},
		],
	},
	"boomerang": {
		"name": "Boomerang", "quote": "OY MATE!!!", "icon": "boomerang_skill", "behavior": "boomerang", "sheet": "boomerang",
		"base": {"cooldown": 3.0, "damage": 10.0, "speed": 17.0, "pierce": -1, "range": 10.0},
		"levels": [
			{"desc": "Throw 1 more boomerang", "amount": 1}, {"desc": "+5 damage", "damage": 5.0},
			{"desc": "Flies further", "range": 3.0}, {"desc": "Throw 1 more boomerang", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0}, {"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "Throw 1 more boomerang", "amount": 1},
		],
	},
	"lightning": {
		"name": "Lightning", "quote": "A shocking discovery", "icon": "lightning_skill", "behavior": "strike",
		"sheet": "lightning", "strike_radius": 2.2,
		"base": {"cooldown": 2.5, "damage": 15.0, "amount": 2, "range": 18.0},
		"levels": [
			{"desc": "1 more strike", "amount": 1}, {"desc": "+10 damage", "damage": 10.0},
			{"desc": "Bigger strikes", "area": 0.25}, {"desc": "1 more strike", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0}, {"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "2 more strikes", "amount": 2},
		],
	},
	"cursed_sword": {
		"name": "Cursed Sword", "quote": "BOOOOO!", "icon": "cursed_sword_skill", "behavior": "orbit",
		"sheet": "cursed_sword", "orbit_radius": 2.2,
		"base": {"cooldown": 1.5, "damage": 12.0, "speed": 5.0, "duration": 3.0, "pierce": -1, "amount": 2},
		"levels": [
			{"desc": "1 more sword", "amount": 1}, {"desc": "+5 damage", "damage": 5.0},
			{"desc": "Spins for longer", "duration": 0.75}, {"desc": "1 more sword", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0}, {"desc": "Bigger orbit", "area": 0.25},
			{"desc": "1 more sword", "amount": 1},
		],
	},
	"acid": {
		"name": "Acid", "quote": "This tastes funny...", "icon": "potion_skill", "behavior": "flask",
		"sheet": "acid_potion", "pool_sheet": "acid_pool", "tick": 0.35, "pool_radius": 2.4,
		"base": {"cooldown": 4.0, "damage": 4.0, "duration": 2.5, "range": 9.0},
		"levels": [
			{"desc": "Throw 1 more flask", "amount": 1}, {"desc": "+2 damage", "damage": 2.0},
			{"desc": "Throw 1 more flask", "amount": 1}, {"desc": "Pools last longer", "duration": 1.0},
			{"desc": "+2 damage", "damage": 2.0}, {"desc": "Bigger pools", "area": 0.3},
			{"desc": "Throw 1 more flask", "amount": 1},
		],
	},
	"bat_swarm": {
		"name": "Bat Swarm", "quote": "JUSTICE!!!!!", "icon": "bat_skill", "behavior": "seeker", "sheet": "bat", "bite": 0.4,
		"base": {"cooldown": 5.0, "damage": 6.0, "speed": 11.0, "duration": 4.0, "amount": 2, "pierce": -1, "knockback": 0.0},
		"levels": [
			{"desc": "1 more bat", "amount": 1}, {"desc": "+3 damage", "damage": 3.0},
			{"desc": "Bats stay longer", "duration": 1.5}, {"desc": "1 more bat", "amount": 1},
			{"desc": "+3 damage", "damage": 3.0}, {"desc": "Faster bats", "speed": 3.0},
			{"desc": "2 more bats", "amount": 2},
		],
	},
	"will_o_wisp": {
		"name": "Will-O-Wisp", "quote": "WILLY O WISPY", "icon": "wisp_skill", "behavior": "seeker", "sheet": "wisp",
		"base": {"cooldown": 2.6, "damage": 12.0, "speed": 10.0, "duration": 5.0, "amount": 1, "pierce": 3},
		"levels": [
			{"desc": "1 more wisp", "amount": 1}, {"desc": "+5 damage", "damage": 5.0},
			{"desc": "Wisps burn through 2 more", "pierce": 2}, {"desc": "1 more wisp", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0}, {"desc": "Faster wisps", "speed": 2.5},
			{"desc": "2 more wisps", "amount": 2},
		],
	},
}

# ---------------------------------------------------------------- passives
# Each level adds `per_level` to the hero's stats (see Player.STAT_DEFAULTS).
const PASSIVES := {
	"attack_up": {"name": "Attack Up", "desc": "+10% damage", "icon": "tentacle", "per_level": {"might": 0.10}, "max_level": 5},
	"tome_of_speed": {"name": "Tome Of Speed", "desc": "Cooldowns 8% shorter", "icon": "magic_tome", "per_level": {"cooldown": -0.08}, "max_level": 5},
	"snail_king": {"name": "Snail King", "desc": "Take 6% less damage", "icon": "snail_lord", "per_level": {"armor": 0.06}, "max_level": 5},
	"experience_up": {"name": "Experience Up", "desc": "+10% candy experience", "icon": "onion", "per_level": {"growth": 0.10}, "max_level": 5},
	"health_regen": {"name": "Health Regen", "desc": "+0.5 health a second", "icon": "holy_cross", "per_level": {"regen": 0.5}, "max_level": 5},
	"max_health": {"name": "Max Health", "desc": "+15% maximum health", "icon": "heartbeat", "per_level": {"max_hp_mul": 0.15}, "max_level": 5},
	"vacuusuck": {"name": "VacuuSuck", "desc": "Pull candy from further away", "icon": "vacusuck", "per_level": {"magnet": 0.4}, "max_level": 5},
}

# Offered when nothing else is left to level.
const ELIXIRS := {
	"elixir_heal": {"name": "Heart", "desc": "Heal 40 health", "icon": "heart", "heal": 40.0},
}

# ---------------------------------------------------------------- heroes
const HEROES := {
	"joe": {"name": "Joe", "perk": "All-rounder. +10% damage.", "weapon": "claw", "stats": {"might": 0.10}},
	"matt": {"name": "Matt", "perk": "Tough. +30 max health.", "weapon": "cursed_sword", "stats": {"max_hp": 30.0}},
	"alex": {"name": "Alex", "perk": "Ranged. Shots fly 20% faster.", "weapon": "crossbow", "stats": {"proj_speed": 0.2}},
	"jon": {"name": "Jon", "perk": "Lucky. +15% candy experience.", "weapon": "will_o_wisp", "stats": {"growth": 0.15}},
}
const HERO_ORDER: Array[String] = ["joe", "matt", "alex", "jon"]

# ---------------------------------------------------------------- enemies
# move: walk, hop or fly. cost: director credits. hp and damage are at difficulty 1.
const ENEMIES := {
	"zombie": {"sheet": "zombie", "height": 1.9, "radius": 0.4, "speed": 3.2, "move": "walk", "hp": 10.0, "damage": 8.0, "xp": 1, "cost": 1.0},
	"pumpkin": {"sheet": "pumpkin", "height": 1.0, "radius": 0.45, "speed": 4.6, "move": "hop", "hp": 16.0, "damage": 10.0, "xp": 2, "cost": 1.5},
	"skull": {"sheet": "skull", "height": 1.1, "radius": 0.45, "speed": 5.8, "move": "fly", "hp": 7.0, "damage": 6.0, "xp": 1, "cost": 1.5},
	"ghost": {"sheet": "ghost", "height": 2.3, "radius": 0.45, "speed": 3.2, "move": "fly", "hp": 24.0, "damage": 10.0, "xp": 3, "cost": 3.0},
	"scarecrow": {"sheet": "scarecrow", "height": 3.0, "radius": 0.5, "speed": 3.0, "move": "walk", "hp": 60.0, "damage": 14.0, "xp": 6, "cost": 6.0},
	"werewolf": {"sheet": "werewolf", "height": 1.7, "radius": 0.6, "speed": 6.4, "move": "walk", "hp": 45.0, "damage": 14.0, "xp": 6, "cost": 6.0},
	"shadowbeast": {"sheet": "shadowbeast", "height": 2.2, "radius": 0.7, "speed": 4.6, "move": "walk", "hp": 90.0, "damage": 18.0, "xp": 10, "cost": 10.0},
	"swampthing": {"sheet": "swampthing", "height": 3.6, "radius": 0.8, "speed": 3.2, "move": "walk", "hp": 160.0, "damage": 22.0, "xp": 16, "cost": 16.0},
}

# A boss is a giant version of an enemy with its own attacks (see boss.gd):
#   slam (a shockwave to jump over), volley (a fan of shots), summon (a pack), charge (a dash).
const BOSSES := {
	"scarecrow_king": {"name": "The Harvest King", "enemy": "scarecrow", "height": 7.0, "radius": 1.3, "speed": 4.0,
		"hp": 700.0, "damage": 16.0, "attacks": ["volley", "summon", "slam"], "shot": "fireball", "minion": "pumpkin"},
	"alpha_wolf": {"name": "The Alpha", "enemy": "werewolf", "height": 4.6, "radius": 1.6, "speed": 6.0,
		"hp": 1300.0, "damage": 22.0, "attacks": ["charge", "charge", "slam", "summon"], "shot": "fireball", "minion": "werewolf"},
	"swamp_lord": {"name": "Lord Of The Mire", "enemy": "swampthing", "height": 8.0, "radius": 1.8, "speed": 3.6,
		"hp": 1900.0, "damage": 26.0, "attacks": ["slam", "volley", "summon", "slam"], "shot": "wisp", "minion": "ghost"},
}

# Candy is the experience pickup: the biggest sprite the value covers is used.
const CANDY := [["candy_bubblegum", 20], ["candy_bar", 5], ["candy_corn", 1]]

# ---------------------------------------------------------------- stages
# roster: [enemy, seconds into the stage before it may spawn]. props: [sprite, height, weight].
# After the last stage the run loops back to the first, harder.
const STAGES := [
	{
		"name": "The Graveyard", "boss": "scarecrow_king",
		"roster": [["zombie", 0.0], ["skull", 25.0], ["ghost", 70.0], ["scarecrow", 130.0]],
		"props": [["grave_1_small", 1.6, 5], ["grave_2", 1.6, 5], ["tree", 9.0, 3], ["tree_3", 9.0, 2], ["mausoleum", 7.0, 1], ["street_lamp", 4.4, 2]],
		"ground": "2a2438", "rock": "4a4466", "ramp": "6a4a78", "wall": "1c1830", "line": "b08ad0",
		"sky_top": "120c2e", "sky_horizon": "9a4a8a", "ambient": "a098c8", "fog": "4a3a66", "sun": "d8c8ff",
	},
	{
		"name": "The Pumpkin Patch", "boss": "alpha_wolf",
		"roster": [["pumpkin", 0.0], ["zombie", 0.0], ["skull", 30.0], ["werewolf", 70.0], ["scarecrow", 110.0]],
		"props": [["tree_2", 9.0, 3], ["tree_4", 9.0, 3], ["tree_owl", 9.0, 1], ["tree_5", 9.0, 2], ["grave_2", 1.6, 1]],
		"ground": "3a2a1e", "rock": "6a4a30", "ramp": "c8541c", "wall": "24180f", "line": "f0a050",
		"sky_top": "241038", "sky_horizon": "e06a28", "ambient": "c8a890", "fog": "7a4030", "sun": "ffc890",
	},
	{
		"name": "The Black Mire", "boss": "swamp_lord",
		"roster": [["ghost", 0.0], ["skull", 0.0], ["shadowbeast", 40.0], ["werewolf", 80.0], ["swampthing", 120.0]],
		"props": [["tree_6", 9.0, 4], ["tree_5", 9.0, 3], ["tree", 9.0, 2], ["grave_1_small", 1.6, 2], ["street_lamp", 4.4, 1]],
		"ground": "14261e", "rock": "2c4a3a", "ramp": "2c866b", "wall": "0c1612", "line": "70e090",
		"sky_top": "04100c", "sky_horizon": "2a6a4a", "ambient": "80b098", "fog": "1e4030", "sun": "b8ffd0",
	},
]

# ---------------------------------------------------------------- helpers
static var _textures := {}
static var _icons := {}


static func tex(file: String) -> Texture2D:
	if not _textures.has(file):
		_textures[file] = load("res://sprites/%s.png" % file)
	return _textures[file]


## The texture, frame count and fps of a sheet. A bare file name works as a one-frame sheet.
static func sheet(id: String) -> Array:
	if SHEETS.has(id):
		var entry: Array = SHEETS[id]
		return [tex(entry[0]), entry[1], entry[2]]
	return [tex(id), 1, 1.0]


## A square icon: the first frame of a sheet, or a plain image.
static func icon(id: String) -> Texture2D:
	if not SHEETS.has(id):
		return tex(id)
	if not _icons.has(id):
		var info := sheet(id)
		var texture: Texture2D = info[0]
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(0, 0, texture.get_width() / float(info[1]), texture.get_height())
		_icons[id] = atlas
	return _icons[id]


static func upgrade_def(id: String) -> Dictionary:
	if WEAPONS.has(id):
		return WEAPONS[id]
	if PASSIVES.has(id):
		return PASSIVES[id]
	return ELIXIRS.get(id, {})


static func weapon_max_level(id: String) -> int:
	var levels: Array = WEAPONS[id]["levels"]
	return levels.size() + 1
