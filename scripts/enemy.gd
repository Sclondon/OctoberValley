extends CharacterBody3D
## One enemy: an 8 Bit Evil Returns sprite sheet on a billboard that chases the hero in a
## straight line. Walkers leap when a wall stops them, hoppers bounce, flyers ignore gravity.
## They crowd each other, hurt the hero on touch, and drop candy when they die.

const Db := preload("res://scripts/db.gd")
const AnimSprite := preload("res://scripts/anim_sprite.gd")
const Fx := preload("res://scripts/fx.gd")
const Team := preload("res://scripts/team.gd")

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

var _touch_cd := 0.0
var _flash := 0.0
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
	net_id = Team.next_id()
	all.append(self)


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
	_flash = 0.1
	sprite.modulate = Color(1.0, 0.35, 0.35)
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
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector3(1.6, 0.0, 1.6), 0.14)
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


## The nearest living enemy to `from` within `reach`, or null.
static func nearest(from: Vector3, reach: float) -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_distance := reach
	for enemy: CharacterBody3D in all:
		var distance: float = from.distance_to(enemy.centre()) - enemy.hit_radius
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## Every living enemy whose body is within `reach` of `from`.
static func within(from: Vector3, reach: float) -> Array:
	var found := []
	for enemy: CharacterBody3D in all:
		if from.distance_to(enemy.centre()) - enemy.hit_radius < reach:
			found.append(enemy)
	return found
