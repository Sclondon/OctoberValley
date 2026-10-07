extends RefCounted
## One weapon the hero owns. It counts down its cooldown and fires by itself, aiming at the
## nearest enemy. Its level decides its stats (see Db.WEAPONS).

const Db := preload("res://scripts/db.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Shot := preload("res://scripts/shot.gd")
const AnimSprite := preload("res://scripts/anim_sprite.gd")
const Fx := preload("res://scripts/fx.gd")

const SLASH_ARC := 1.4  # radians either side of the aim
const SLASH_TURNS := [0.0, PI, PI * 0.5, -PI * 0.5]

var id := ""
var level := 1
var def: Dictionary
var stats: Dictionary

var _timer := 0.5


func _init(weapon_id: String) -> void:
	id = weapon_id
	def = Db.WEAPONS[id]
	_refresh()


func level_up() -> void:
	level += 1
	_refresh()


func _refresh() -> void:
	stats = Db.WEAPON_DEFAULTS.duplicate()
	stats.merge(def["base"], true)
	var levels: Array = def.get("levels", [])
	for i in mini(level - 1, levels.size()):
		var step: Dictionary = levels[i]
		for key: String in step:
			if key == "desc":
				continue
			if key.ends_with("_mul"):
				stats[key.trim_suffix("_mul")] *= step[key]
			else:
				stats[key] += step[key]


func tick(delta: float, player: Node3D) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	if Enemy.all.is_empty():
		_timer = 0.2
		return
	var cooldown: float = stats["cooldown"] * maxf(player.stat("cooldown"), 0.3)
	if _fire(player):
		_timer = cooldown + (float(stats["duration"]) if def["behavior"] == "orbit" else 0.0)
	else:
		_timer = 0.15


## Fires once. Returns false if there was nothing in reach to fire at.
func _fire(player: Node3D) -> bool:
	var origin: Vector3 = player.centre()
	var damage: float = stats["damage"] * player.stat("might")
	var area: float = stats["area"]
	var amount: int = stats["amount"]
	var reach: float = stats["range"]
	var speed: float = stats["speed"] * player.stat("proj_speed")
	var sheet: String = def["sheet"]
	var behavior: String = def["behavior"]
	var target := Enemy.nearest(origin, reach * 1.15 * (area if behavior == "slash" else 1.0))
	if target == null and behavior in ["slash", "bolt", "boomerang", "strike"]:
		return false
	var aim: Vector3 = player.facing_dir()
	if target:
		aim = (target.centre() - origin).normalized()

	match behavior:
		"slash":
			var flat_aim := Vector3(aim.x, 0.0, aim.z).normalized()
			for i in amount:
				var dir := flat_aim.rotated(Vector3.UP, SLASH_TURNS[i % SLASH_TURNS.size()])
				for enemy: Node3D in Enemy.within(origin, reach * area):
					var to_enemy: Vector3 = enemy.centre() - origin
					to_enemy.y = 0.0
					if to_enemy.length() < 0.6 or dir.angle_to(to_enemy) < SLASH_ARC:
						enemy.hit(damage, to_enemy.normalized() * stats["knockback"])
				var slash := _shot(player, "flash", sheet, 3.0 * area, damage)
				slash.follow = dir * reach * area * 0.55
				slash.global_position = origin + slash.follow
		"bolt":
			for i in amount:
				var dir := aim.rotated(Vector3.UP, (i - (amount - 1) * 0.5) * 0.12)
				var bolt := _shot(player, "bolt", sheet, 0.9 if def.has("flat") else 1.3, damage)
				bolt.global_position = origin
				bolt.velocity = dir * speed
				bolt.range_left = reach
				bolt.pierce = stats["pierce"]
				bolt.explode = float(def.get("explode", 0.0)) * area
				if def.has("flat"):
					_lay_along(bolt, dir)
		"boomerang":
			for i in amount:
				var dir := aim.rotated(Vector3.UP, (i - (amount - 1) * 0.5) * 0.5)
				var rang := _shot(player, "boomerang", sheet, 1.1 * area, damage)
				rang.global_position = origin
				rang.velocity = dir * speed
				rang.speed = speed
				rang.range_left = reach
				rang.pierce = -1
				rang.hit_radius = 0.8 * area
		"strike":
			var radius: float = def["strike_radius"] * area
			var marks := Enemy.within(origin, reach)
			marks.shuffle()
			for i in mini(amount, marks.size()):
				var mark: Node3D = marks[i]
				var ground: Vector3 = mark.global_position
				for enemy: Node3D in Enemy.within(ground + Vector3.UP, radius):
					enemy.hit(damage)
				Fx.burst(player.world, ground + Vector3.UP * 4.0, sheet, 8.0, Color.WHITE, true)
		"orbit":
			for i in amount:
				var sword := _shot(player, "orbit", sheet, 1.9, damage)
				sword.angle = TAU * i / amount
				sword.orbit_radius = def["orbit_radius"] * area
				sword.speed = speed
				sword.life = stats["duration"]
				sword.pierce = -1
				sword.hit_radius = 1.3
				sword.global_position = origin
		"flask":
			var marks := Enemy.within(origin, reach)
			marks.shuffle()
			for i in amount:
				var flask := _shot(player, "flask", sheet, 0.9, damage)
				flask.from = origin
				if i < marks.size():
					flask.to = marks[i].global_position
				else:
					flask.to = player.global_position + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(2.0, reach)
				flask.pool_sheet = def["pool_sheet"]
				flask.pool_radius = def["pool_radius"] * area
				flask.tick = def["tick"]
				flask.duration = stats["duration"]
				flask.global_position = origin
		"seeker":
			for i in amount:
				var seeker := _shot(player, "seeker", sheet, 1.2, damage)
				seeker.global_position = origin + Vector3.UP * 0.6
				seeker.velocity = Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.0), randf_range(-1.0, 1.0)).normalized() * speed
				seeker.speed = speed
				seeker.life = stats["duration"]
				seeker.pierce = stats["pierce"]
				seeker.again = def.get("bite", 0.6)
				seeker.hit_radius = 0.7
	return true


func _shot(player: Node3D, mode: String, sheet: String, size: float, damage: float) -> Shot:
	var shot := Shot.new()
	shot.mode = mode
	shot.player = player
	shot.damage = damage
	shot.knockback = stats["knockback"]
	shot.net_sheet = sheet
	shot.net_size = size
	var sprite := AnimSprite.make(sheet, size)
	if mode == "flash":
		sprite.loop = false
		sprite.finished.connect(shot.queue_free)
	shot.add_child(sprite)
	player.world.add_child(shot)
	return shot


## Bolts are drawn pointing up-right. Lay two copies along the flight path, one flat and one
## upright, so the bolt reads from any camera angle.
func _lay_along(shot: Shot, dir: Vector3) -> void:
	Shot.lay_flat(shot)
	shot.net_laid = true
	shot.look_at_from_position(shot.global_position, shot.global_position + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
