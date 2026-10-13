extends CharacterBody3D
## One enemy: an 8 Bit Evil Returns sprite sheet on a billboard that chases the hero in a
## straight line. Walkers leap when a wall stops them, hoppers bounce, flyers ignore gravity.
## They crowd each other, hurt the hero on touch, and drop candy when they die.

const Db := preload("res://scripts/db.gd")
const AnimSprite := preload("res://scripts/anim_sprite.gd")
const Fx := preload("res://scripts/fx.gd")
const Team := preload("res://scripts/team.gd")
const Sfx := preload("res://scripts/sfx.gd")

signal died(enemy: CharacterBody3D)

const GRAVITY := 30.0
const ACCEL := 20.0
## Enough to clear a 5 m ledge, so high ground is not a safe spot.
const WALL_JUMP := 18.0
const HOP := 6.5
const TOUCH_GAP := 1.0
## How often it looks again for the nearest hero.
const RETARGET := 0.4
const ELITE_TINT := Color(1.0, 0.78, 0.3)
## A struck enemy goes white for a moment (the sprite is unshaded, so this over-brightens it).
const FLASH_TINT := Color(5.0, 5.0, 5.0)
const FLASH_TIME := 0.08
const FLASH_GAP := 0.3
## Weapons judge a boss to be this much of its real distance away when choosing a target.
const BOSS_PULL := 0.3

## Every living enemy, bosses included. Shots and weapons search this.
static var all: Array = []

var kind := "zombie"
## The hero it is after: the nearest living one.
var target: Node3D
## Its id in co-op snapshots.
var net_id := 0
var sprite: Sprite3D
## Set by the director before the enemy enters the tree.
var hp_scale := 1.0
var damage_scale := 1.0
var elite := false

var is_boss := false
var hp := 10.0
var max_hp := 10.0
var damage := 8.0
var xp := 1
var height := 1.0
var radius := 0.4
## Shots hit a sphere of this size around centre().
var hit_radius := 0.5
var speed := 3.0
var move := "walk"
var accel := ACCEL
var dead := false
var tint := Color.WHITE
## Seconds it takes to grow out of the ground.
var rise_time := 0.35

var _touch_cd := 0.0
var _flash := 0.0
var _flash_rest := 0.0
var _retarget := 0.0


## The enemy's numbers. Bosses override this.
func _def() -> Dictionary:
	return Db.ENEMIES[kind]


func _ready() -> void:
	var def := _def()
	var grow := 1.3 if elite else 1.0
	height = def["height"] * grow
	radius = def["radius"] * grow
	hit_radius = maxf(radius, height * 0.4)
	speed = def["speed"]
	move = def["move"]
	max_hp = def["hp"] * hp_scale * (4.0 if elite else 1.0)
	hp = max_hp
	damage = def["damage"] * damage_scale * (1.5 if elite else 1.0)
	xp = int(def["xp"]) * (5 if elite else 1)
	if elite:
		tint = ELITE_TINT
	collision_layer = 4
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(50.0)
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	add_child(collider)

	sprite = AnimSprite.make(def["sheet"], height, true)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.clock = randf() * 10.0
	sprite.modulate = tint
	add_child(sprite)
	rise(sprite, rise_time)
	net_id = Team.next_id()
	all.append(self)


## Grows a sprite out of the ground, so nothing just appears (guests do the same to theirs).
static func rise(new_sprite: Sprite3D, seconds := 0.35) -> void:
	new_sprite.scale = Vector3(1.0, 0.05, 1.0)
	new_sprite.create_tween().tween_property(new_sprite, "scale", Vector3.ONE, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The pixels an enemy bursts into (guests do the same when one of theirs goes).
static func burst_at(parent: Node, at: Vector3, def: Dictionary, size: float, boss := false) -> void:
	Fx.puff(parent, at, Color(str(def.get("puff", "d8d0e8"))), 30 if boss else 9, clampf(size / 1.6, 0.8, 2.2))
	Sfx.at("boom" if boss else "kill", at, 1.0, randf_range(0.85, 1.15))
	if boss:
		Fx.shake(0.9, at)
		Fx.ring(parent, at - Vector3.UP * size * 0.5, Color("ffd9a0"), 14.0, 0.7)


func _exit_tree() -> void:
	all.erase(self)


func centre() -> Vector3:
	return global_position + Vector3.UP * height * 0.5


## Takes damage. `push` is a knockback velocity (bosses shrug it off).
func hit(amount: float, push := Vector3.ZERO) -> void:
	if dead:
		return
	hp -= amount
	Fx.number(get_parent(), global_position + Vector3.UP * (height + 0.3), amount, Color("ffe9a0") if amount < 30.0 else Color("ff9a50"))
	# flash, but not so often that something under steady fire stays white
	if _flash_rest <= 0.0:
		_flash = FLASH_TIME
		_flash_rest = FLASH_GAP
		sprite.modulate = FLASH_TINT
	Sfx.at("hit", global_position, 0.7, randf_range(0.9, 1.15))
	if not is_boss:
		velocity += Vector3(push.x, 0.0, push.z)
	if hp <= 0.0:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	all.erase(self)
	died.emit(self)
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	burst_at(get_parent(), centre(), _def(), height, is_boss)
	sprite.modulate = FLASH_TINT
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector3(1.5, 0.0, 1.5), 0.16)
	tween.tween_callback(queue_free)


## True for a moment after a hit (guests tint the sprite too).
func flashing() -> bool:
	return _flash > 0.0


func _physics_process(delta: float) -> void:
	if dead:
		return
	_retarget -= delta
	if _retarget <= 0.0 or not is_instance_valid(target) or target.dead:
		_retarget = RETARGET
		target = Team.nearest(global_position)
	if target == null:
		return
	_touch_cd -= delta
	_flash_rest -= delta
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			sprite.modulate = tint
	var wish := _wish(delta)
	if move == "fly":
		velocity = velocity.move_toward(wish, accel * delta)
	else:
		var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3(wish.x, 0.0, wish.z), accel * delta)
		velocity.x = flat.x
		velocity.z = flat.z
		if is_on_floor():
			if is_on_wall() and wish != Vector3.ZERO:
				velocity.y = WALL_JUMP
			elif move == "hop" and wish != Vector3.ZERO:
				velocity.y = HOP
		else:
			velocity.y -= GRAVITY * delta
	move_and_slide()
	_touch()
	_face_camera_side()


## The velocity this enemy wants: straight at the hero until it is close enough to touch.
func _wish(_delta: float) -> Vector3:
	var aim := target.global_position + (Vector3.UP * 0.5 if move == "fly" else Vector3.ZERO)
	var to_target := aim - global_position
	if move != "fly":
		to_target.y = 0.0
	if to_target.length() > radius + 0.5:
		return to_target.normalized() * speed
	return Vector3.ZERO


## Hurts the hero when it is close enough, at most once every TOUCH_GAP.
func _touch() -> void:
	if _touch_cd > 0.0:
		return
	var offset := target.global_position - global_position
	if Vector2(offset.x, offset.z).length() < radius + 0.9 and offset.y > -1.9 and offset.y < height + 0.3:
		_touch_cd = TOUCH_GAP
		target.hurt(damage, global_position)


## The sheets are drawn facing right, so flip when moving left across the screen.
func _face_camera_side() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or Vector2(velocity.x, velocity.z).length() < 0.2:
		return
	sprite.flip_h = velocity.dot(cam.global_basis.x) < 0.0


## The living enemy within `reach` of `from` to aim at, or null: the nearest, except that a
## boss counts as much closer than it is, so weapons turn on it once it is in reach.
static func nearest(from: Vector3, reach: float) -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_score := INF
	for enemy: CharacterBody3D in all:
		var distance: float = from.distance_to(enemy.centre()) - enemy.hit_radius
		if distance >= reach:
			continue
		var score := distance * (BOSS_PULL if enemy.is_boss else 1.0)
		if score < best_score:
			best_score = score
			best = enemy
	return best


## Enemies within `reach` of `from` in the order to strike them: the boss first, then any.
static func marks(from: Vector3, reach: float) -> Array:
	var found := within(from, reach)
	found.shuffle()
	for i in found.size():
		if found[i].is_boss:
			found.push_front(found.pop_at(i))
	return found


## Every living enemy whose body is within `reach` of `from`.
static func within(from: Vector3, reach: float) -> Array:
	var found := []
	for enemy: CharacterBody3D in all:
		if from.distance_to(enemy.centre()) - enemy.hit_radius < reach:
			found.append(enemy)
	return found
