extends Node
## Runs the horde, Risk of Rain 2 style. It earns credits every second (faster as the
## difficulty climbs) and every few seconds spends them on a pack of one enemy type from the
## stage's roster, dropped on the ground in a ring around the hero. It also summons the boss,
## scales enemy health and damage with the difficulty, and drops the loot.

const Db := preload("res://scripts/db.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Boss := preload("res://scripts/boss.gd")
const Pickup := preload("res://scripts/pickup.gd")
const Team := preload("res://scripts/team.gd")

signal enemy_killed(enemy: Enemy)
signal boss_spawned(boss: Boss)
signal boss_defeated

const MAX_ALIVE := 90
## Each hero after the first adds this share of the credits, and this many more enemies.
const EXTRA_HERO_CREDITS := 0.6
const EXTRA_HERO_ALIVE := 20
const CREDITS_PER_SECOND := 1.7
const WAVE_GAP := Vector2(2.0, 4.0)
const PACK_SIZE := Vector2i(3, 8)
const RING := Vector2(16.0, 30.0)
const PACK_SPREAD := 3.0
## Enemies left this far behind, or fallen out of the world, are brought back to the ring.
const LEASH := 75.0
## Bosses feel the difficulty less than the horde does, or late summons drag on.
const BOSS_HP_SCALE := 0.75
const HEART_CHANCE := 0.03
const ELITE_CHEST_CHANCE := 0.25
## Used when the level has no theme (the test yard): everything, a little at a time.
const DEFAULT_ROSTER := [["zombie", 0.0], ["pumpkin", 0.0], ["skull", 20.0], ["ghost", 40.0],
	["scarecrow", 60.0], ["werewolf", 80.0], ["shadowbeast", 100.0], ["swampthing", 120.0]]

## Enemies and loot are added here. Main replaces it on every stage.
var world: Node3D
var enabled := true
## Half the level's width, so packs are not placed outside the walls.
var half_extent := 70.0
## Seconds of the whole run, and of this stage.
var time := 0.0
var stage_time := 0.0
var stage_index := 0
var roster: Array = DEFAULT_ROSTER
var credits := 4.0
var boss: Boss
## False once the stage's boss is dead: nothing more spawns until the next stage.
var spawning := true

var _wave_timer := 1.5


## 1.0 at the start; rises with every minute survived and every stage cleared.
func difficulty() -> float:
	return 1.0 + time / 120.0 + stage_index * 0.6


func hp_scale() -> float:
	return 1.0 + (difficulty() - 1.0) * 0.45


func damage_scale() -> float:
	return 1.0 + (difficulty() - 1.0) * 0.2


func alive() -> int:
	return Enemy.all.size()


## Back to the start of a run.
func reset() -> void:
	time = 0.0
	stage_index = 0


func begin_stage(index: int, stage_roster: Array, stage_world: Node3D, stage_half_extent: float) -> void:
	stage_index = index
	roster = stage_roster
	world = stage_world
	half_extent = stage_half_extent
	stage_time = 0.0
	credits = 4.0
	boss = null
	spawning = true
	_wave_timer = 1.5


func _physics_process(delta: float) -> void:
	if not enabled or world == null or Team.alive().is_empty():
		return
	time += delta
	stage_time += delta
	if not spawning:
		return
	var extra_heroes := Team.heroes.size() - 1
	var rate := CREDITS_PER_SECOND * difficulty() * (0.4 if boss else 1.0) * (1.0 + EXTRA_HERO_CREDITS * extra_heroes)
	credits = minf(credits + rate * delta, 30.0 + 20.0 * difficulty())
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = randf_range(WAVE_GAP.x, WAVE_GAP.y)
		_spawn_pack()
		_recall_strays()


func _spawn_pack() -> void:
	var room := MAX_ALIVE + EXTRA_HERO_ALIVE * (Team.heroes.size() - 1) - alive()
	var kinds: Array[String] = []
	for entry: Array in roster:
		if entry[1] <= stage_time and Db.ENEMIES[entry[0]]["cost"] <= credits:
			kinds.append(entry[0])
	if room <= 0 or kinds.is_empty():
		return
	var kind: String = kinds.pick_random()
	var cost: float = Db.ENEMIES[kind]["cost"]
	var count := mini(mini(int(credits / cost), randi_range(PACK_SIZE.x, PACK_SIZE.y)), room)
	var anchor := _ring_point()
	var elite_chance := clampf((difficulty() - 1.4) * 0.05, 0.0, 0.3)
	for i in count:
		var spread := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * PACK_SPREAD
		spawn(kind, _on_ground(anchor + spread), randf() < elite_chance)
		credits -= cost


func spawn(kind: String, at: Vector3, elite := false) -> Enemy:
	var enemy := Enemy.new()
	enemy.kind = kind
	enemy.elite = elite
	_place(enemy, at + (Vector3.UP * 2.5 if Db.ENEMIES[kind]["move"] == "fly" else Vector3.ZERO))
	return enemy


## Brings in the stage boss near `at`.
func summon_boss(boss_id: String, at: Vector3) -> Boss:
	boss = Boss.new()
	boss.boss_id = boss_id
	boss.director = self
	boss.hp_scale = BOSS_HP_SCALE
	_place(boss, _on_ground(at + Vector3(6.0, 0.0, 6.0)))
	boss_spawned.emit(boss)
	return boss


func _place(enemy: Enemy, at: Vector3) -> void:
	enemy.hp_scale *= hp_scale()
	enemy.damage_scale = damage_scale()
	enemy.position = at
	enemy.died.connect(_on_died)
	world.add_child(enemy)


func _on_died(enemy: Enemy) -> void:
	var at := _on_ground(enemy.global_position, enemy.global_position.y + 1.0)
	Pickup.drop(world, "candy", at, enemy.xp)
	if randf() < HEART_CHANCE:
		Pickup.drop(world, "heart", at + Vector3(0.6, 0.0, 0.0))
	if enemy == boss:
		boss = null
		spawning = false
		for i in Team.heroes.size():
			Pickup.drop(world, "chest", at + Vector3(i * 1.6, 0.0, 1.5))
		for other: Enemy in Enemy.all.duplicate():
			other.die()
		for pickup in get_tree().get_nodes_in_group(Pickup.GROUP):
			pickup.vacuum = true
		boss_defeated.emit()
	elif enemy.elite and randf() < ELITE_CHEST_CHANCE:
		Pickup.drop(world, "chest", at + Vector3(0.0, 0.0, 1.0))
	enemy_killed.emit(enemy)


func _recall_strays() -> void:
	for enemy: Enemy in Enemy.all:
		if enemy.is_boss and enemy.global_position.y > -20.0:
			continue
		var hero := Team.nearest(enemy.global_position)
		var away := enemy.global_position.distance_to(hero.global_position) if hero else 0.0
		if away > LEASH or enemy.global_position.y < -20.0:
			enemy.global_position = _on_ground(_ring_point())
			enemy.velocity = Vector3.ZERO
			enemy.reset_physics_interpolation()


## A random point in the ring around one of the heroes, kept inside the walls.
func _ring_point() -> Vector3:
	var limit := half_extent - 3.0
	var hero: Node3D = Team.alive().pick_random()
	var point := hero.global_position + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(RING.x, RING.y)
	point.x = clampf(point.x, -limit, limit)
	point.z = clampf(point.z, -limit, limit)
	return point


## Drops a point onto the level geometry under it, looking down from `from_height`.
func _on_ground(point: Vector3, from_height := 60.0) -> Vector3:
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, from_height, point.z), Vector3(point.x, -10.0, point.z), 1)
	var hit := space.intersect_ray(query)
	return hit["position"] if hit else Vector3(point.x, 0.0, point.z)
