extends CharacterBody3D
## A hero. Risk of Rain 2 style movement (run relative to the camera, quick acceleration, a
## high jump, an air jump, a sprint) plus everything a run tracks: health, experience, level,
## and the weapons and passives picked so far. Weapons fire by themselves.
##
## In co-op every player has one of these on every machine. Two switches say what this copy
## does: `driven` (it goes where the network says, instead of reading the controls) and
## `simulate` (this machine runs its weapons and health, which only the host does).

const HeroModel := preload("res://scripts/hero_model.gd")
const Db := preload("res://scripts/db.gd")
const Weapon := preload("res://scripts/weapon.gd")
const Fx := preload("res://scripts/fx.gd")
const Team := preload("res://scripts/team.gd")

signal died
signal inventory_changed
signal hurt_taken(amount: float)

const RUN_SPEED := 7.0
const SPRINT_MULT := 1.45
const ACCEL := 80.0
## How much of ACCEL you keep in the air.
const AIR_CONTROL := 0.3
const GRAVITY := 30.0
const JUMP_VELOCITY := 13.0
## Jumps allowed after leaving the ground (0 = none, 1 = a double jump).
const AIR_JUMPS := 1
## Grace after walking off a ledge, and how early a jump press is remembered.
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const TURN_SPEED := 14.0
const KILL_HEIGHT := -30.0
## Seconds of safety after a hit, so a crowd cannot land every blow at once.
const HURT_SAFETY := 0.5

## Passives and hero perks add to these.
const STAT_DEFAULTS := {
	"might": 1.0, "cooldown": 1.0, "armor": 0.0, "growth": 1.0, "regen": 0.0,
	"max_hp": 100.0, "max_hp_mul": 1.0, "magnet": 1.0, "proj_speed": 1.0,
}

var hero := "joe"
## Set by main: movement is relative to this rig's yaw.
var camera: Node3D
## Set by main: where shots are added. Replaced on every stage.
var world: Node3D
var model: HeroModel
var sprinting := false
## False on the title screen and when dead: no input, no weapons.
var active := false
var dead := false
## The player's seat in a co-op room (0 when playing alone).
var seat := 0
var driven := false
var simulate := true
## Where a driven hero is heading, how it faces, and its animation (idle, run, jump, fall).
var net_position := Vector3.ZERO
var net_facing := 0.0
var net_anim := "idle"
## Upgrade cards this hero has earned and not picked yet.
var levels_owed := 0
var chests_owed := 0
## Bumped whenever the weapons or passives change (the host resends them to guests).
var inventory_rev := 0

var hp := 100.0
var level := 1
var xp := 0.0
var kills := 0
var weapons: Array[Weapon] = []
## passive id -> level
var passives := {}

var _start := Vector3.ZERO
var _coyote := 0.0
var _jump_buffer := 0.0
var _air_jumps_left := 0
var _facing := 0.0
var _safe := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 8
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.76
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.88
	add_child(collider)
	model = HeroModel.new()
	add_child(model)
	model.set_hero(hero)
	_start = global_position
	net_position = global_position
	Team.heroes.append(self)


func _exit_tree() -> void:
	Team.heroes.erase(self)


func set_hero(hero_name: String) -> void:
	hero = hero_name
	model.set_hero(hero_name)


## A fresh hero for a new run: full health, level 1, only the starting weapon.
func reset_run(hero_name: String) -> void:
	set_hero(hero_name)
	weapons.clear()
	passives.clear()
	level = 1
	xp = 0.0
	kills = 0
	dead = false
	levels_owed = 0
	chests_owed = 0
	model.visible = true
	weapons.append(Weapon.new(Db.HEROES[hero]["weapon"]))
	hp = max_hp()
	_changed()


## Back on your feet with half health (co-op: the fallen return on the next stage).
func revive() -> void:
	dead = false
	model.visible = true
	hp = max_hp() * 0.5


## The build as plain data, and back again (how the host tells a guest what they carry).
func inventory() -> Dictionary:
	var owned := []
	for weapon in weapons:
		owned.append([weapon.id, weapon.level])
	return {"weapons": owned, "passives": passives}


func set_inventory(build: Dictionary) -> void:
	weapons.clear()
	for entry: Array in build["weapons"]:
		var weapon := Weapon.new(entry[0])
		for i in int(entry[1]) - 1:
			weapon.level_up()
		weapons.append(weapon)
	passives.clear()
	for id: String in build["passives"]:
		passives[id] = int(build["passives"][id])
	inventory_changed.emit()


func _changed() -> void:
	inventory_rev += 1
	inventory_changed.emit()


func respawn(at: Vector3) -> void:
	_start = at
	global_position = at
	net_position = at
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func centre() -> Vector3:
	return global_position + Vector3.UP * 0.95


func facing_dir() -> Vector3:
	return Vector3(sin(_facing), 0.0, cos(_facing))


## Speed along the ground, in m/s.
func ground_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# ---------------------------------------------------------------- stats

func stat(stat_name: String) -> float:
	var value: float = STAT_DEFAULTS[stat_name]
	value += Db.HEROES[hero]["stats"].get(stat_name, 0.0)
	for id: String in passives:
		value += Db.PASSIVES[id]["per_level"].get(stat_name, 0.0) * passives[id]
	return value


func max_hp() -> float:
	return stat("max_hp") * stat("max_hp_mul")


func xp_needed() -> float:
	return 5.0 + level * 3.0 + floorf(level * level * 0.3)


func gain_xp(amount: float) -> void:
	if not simulate:
		return
	xp += amount * stat("growth")
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		levels_owed += 1


func heal(amount: float) -> void:
	if dead or not simulate:
		return
	hp = minf(hp + amount, max_hp())
	Fx.number(world, centre() + Vector3.UP, amount, Color("70e090"))


func hurt(amount: float, from: Vector3) -> void:
	if dead or not active or not simulate or _safe > 0.0:
		return
	amount *= 1.0 - minf(stat("armor"), 0.75)
	hp -= amount
	_safe = HURT_SAFETY
	var shove := global_position - from
	shove.y = 0.0
	if not driven:
		velocity += shove.normalized() * 6.0
	Fx.number(world, centre() + Vector3.UP, amount, Color("ff5a5a"))
	hurt_taken.emit(amount)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		model.visible = false
		died.emit()


# ---------------------------------------------------------------- upgrades

func weapon_level(id: String) -> int:
	for weapon in weapons:
		if weapon.id == id:
			return weapon.level
	return 0


## Up to `count` upgrade ids to offer: new or better weapons and passives, or a heal when
## everything is maxed.
func upgrade_options(count: int) -> Array[String]:
	var pool: Array[String] = []
	for id: String in Db.WEAPONS:
		var owned := weapon_level(id)
		if (owned == 0 and weapons.size() < Db.MAX_WEAPONS) or (owned > 0 and owned < Db.weapon_max_level(id)):
			pool.append(id)
	for id: String in Db.PASSIVES:
		var owned: int = passives.get(id, 0)
		if (owned == 0 and passives.size() < Db.MAX_PASSIVES) or (owned > 0 and owned < int(Db.PASSIVES[id]["max_level"])):
			pool.append(id)
	pool.shuffle()
	pool.resize(mini(count, pool.size()))
	if pool.is_empty():
		pool.append("elixir_heal")
	return pool


## What an upgrade card should say for this hero: [name, level text, description].
func describe_upgrade(id: String) -> Array:
	var def := Db.upgrade_def(id)
	if Db.WEAPONS.has(id):
		var owned := weapon_level(id)
		if owned == 0:
			return [def["name"], "NEW WEAPON", def["quote"]]
		return [def["name"], "LEVEL %d" % (owned + 1), def["levels"][owned - 1]["desc"]]
	if Db.PASSIVES.has(id):
		var owned: int = passives.get(id, 0)
		return [def["name"], "NEW" if owned == 0 else "LEVEL %d" % (owned + 1), def["desc"]]
	return [def["name"], "", def["desc"]]


func apply_upgrade(id: String) -> void:
	if Db.WEAPONS.has(id):
		var found := false
		for weapon in weapons:
			if weapon.id == id:
				weapon.level_up()
				found = true
		if not found:
			weapons.append(Weapon.new(id))
	elif Db.PASSIVES.has(id):
		var before := max_hp()
		passives[id] = int(passives.get(id, 0)) + 1
		hp += max_hp() - before
	else:
		heal(Db.ELIXIRS[id].get("heal", 0.0))
	_changed()


# ---------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if driven:
		_follow_network(delta)
	else:
		_move(delta)
	if not (active and not dead and simulate):
		return
	_safe = maxf(_safe - delta, 0.0)
	model.visible = _safe <= 0.0 or fmod(_safe, 0.12) < 0.06
	hp = minf(hp + stat("regen") * delta, max_hp())
	for weapon in weapons:
		weapon.tick(delta, self)


## A hero another machine controls: glide to where it says we are.
func _follow_network(delta: float) -> void:
	var blend := 1.0 - exp(-18.0 * delta)
	if global_position.distance_to(net_position) > 12.0:
		blend = 1.0
	global_position = global_position.lerp(net_position, blend)
	_facing = lerp_angle(_facing, net_facing, blend)
	model.rotation.y = _facing
	model.play(net_anim)


## What the model is doing, for the other machines.
func anim_name() -> String:
	if not is_on_floor():
		return "jump" if velocity.y > 0.0 else "fall"
	return "run" if ground_speed() > 0.5 else "idle"


func facing() -> float:
	return _facing


func _move(delta: float) -> void:
	var playing := active and not dead
	var input := Vector2.ZERO
	if playing:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw: float = camera.rotation.y if camera else 0.0
	var wish := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	sprinting = playing and Input.is_action_pressed("sprint") and input.length() > 0.1

	var grounded := is_on_floor()
	if grounded:
		_coyote = COYOTE_TIME
		_air_jumps_left = AIR_JUMPS
	else:
		_coyote = maxf(_coyote - delta, 0.0)
		velocity.y -= GRAVITY * delta

	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if playing and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	if _jump_buffer > 0.0 and (_coyote > 0.0 or _air_jumps_left > 0):
		if _coyote <= 0.0:
			_air_jumps_left -= 1
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		grounded = false

	var top_speed := RUN_SPEED * (SPRINT_MULT if sprinting else 1.0)
	var accel := ACCEL if grounded else ACCEL * AIR_CONTROL
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish * top_speed, accel * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	move_and_slide()

	if global_position.y < KILL_HEIGHT:
		respawn(_start)

	if wish.length() > 0.1:
		_facing = lerp_angle(_facing, atan2(wish.x, wish.z), minf(TURN_SPEED * delta, 1.0))
		model.rotation.y = _facing
	if not is_on_floor():
		model.play("jump" if velocity.y > 0.0 else "fall")
	elif ground_speed() > 0.5:
		model.play("run", clampf(ground_speed() / RUN_SPEED, 0.6, 1.6))
	else:
		model.play("idle")
