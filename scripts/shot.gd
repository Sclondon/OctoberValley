extends Node3D
## One attack in the world. `mode` picks how it moves and hits:
##   bolt       flies straight, pierces, may explode (crossbow, fireball)
##   boomerang  flies out, then home to the hero
##   seeker     homes in on the nearest enemy (wisps, bats)
##   orbit      circles the hero (cursed sword)
##   flask      arcs to a spot and becomes a pool
##   pool       damages everything standing in it every `tick`
##   flash      only a picture; the weapon already dealt the damage (claw, lightning)

const Db := preload("res://scripts/db.gd")
const Enemy := preload("res://scripts/enemy.gd")
const AnimSprite := preload("res://scripts/anim_sprite.gd")
const Fx := preload("res://scripts/fx.gd")
const Team := preload("res://scripts/team.gd")

const GROUP := "shots"

const FLASK_TIME := 0.6

var mode := "bolt"
var player: Node3D
var damage := 10.0
var knockback := 4.0
var pierce := 1
var life := 6.0
var hit_radius := 0.5
var velocity := Vector3.ZERO
var speed := 14.0
var range_left := 16.0
## Explosion radius when a bolt lands (0 = none).
var explode := 0.0
## Seconds before the same enemy can be hit again.
var again := 0.45
var angle := 0.0
var orbit_radius := 2.8
var from := Vector3.ZERO
var to := Vector3.ZERO
var pool_sheet := ""
var pool_radius := 2.4
var tick := 0.35
var duration := 2.5
## For "flash": stay this far from the hero's centre.
var follow := Vector3.ZERO
var tint := Color.WHITE
## What co-op guests draw for this shot: its sheet and size, and whether it is a bolt laid
## along its flight path.
var net_id := 0
var net_sheet := ""
var net_size := 1.0
var net_laid := false

var _hits := {}
var _clock := 0.0
var _seek := 0.0
var _target: Node3D
var _returning := false
var _tick := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	net_id = Team.next_id()


func _physics_process(delta: float) -> void:
	_clock += delta
	match mode:
		"bolt":
			var step := velocity * delta
			global_position += step
			range_left -= step.length()
			if _sweep() and explode > 0.0:
				_explode()
			elif range_left <= 0.0:
				if explode > 0.0:
					_explode()
				else:
					queue_free()
		"boomerang":
			if _returning:
				var home: Vector3 = player.centre() - global_position
				if home.length() < 1.0:
					queue_free()
					return
				global_position += home.normalized() * speed * delta
			else:
				global_position += velocity * delta
				range_left -= speed * delta
				_returning = range_left <= 0.0
			_sweep()
		"seeker":
			_seek -= delta
			if _seek <= 0.0 or not is_instance_valid(_target) or _target.dead:
				_seek = 0.25
				_target = Enemy.nearest(global_position, 40.0)
			var aim: Vector3 = _target.centre() if _target else player.centre() + Vector3.UP * 1.5
			velocity = velocity.move_toward((aim - global_position).normalized() * speed, speed * 5.0 * delta)
			global_position += velocity * delta
			_sweep()
			life -= delta
			if life <= 0.0:
				queue_free()
		"orbit":
			angle += speed * delta
			global_position = player.centre() + Vector3(cos(angle), 0.0, sin(angle)) * orbit_radius
			_sweep()
			life -= delta
			if life <= 0.0:
				queue_free()
		"flask":
			var t := minf(_clock / FLASK_TIME, 1.0)
			global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 3.0
			if t >= 1.0:
				_become_pool()
		"pool":
			_tick -= delta
			if _tick <= 0.0:
				_tick = tick
				for enemy: Node3D in Enemy.within(global_position, pool_radius):
					if absf(enemy.global_position.y - global_position.y) < 2.0:
						enemy.hit(damage)
			life -= delta
			if life <= 0.0:
				queue_free()
		"flash":
			if player:
				global_position = player.centre() + follow


## Hits every enemy the shot is touching. Returns true if it struck something.
func _sweep() -> bool:
	var struck := false
	for i in range(Enemy.all.size() - 1, -1, -1):
		if i >= Enemy.all.size():
			continue
		var enemy: Node3D = Enemy.all[i]
		if global_position.distance_to(enemy.centre()) > hit_radius + enemy.hit_radius:
			continue
		var id := enemy.get_instance_id()
		if _hits.has(id) and _clock - _hits[id] < again:
			continue
		_hits[id] = _clock
		var push: Vector3 = enemy.centre() - (player.centre() if player else global_position)
		push.y = 0.0
		enemy.hit(damage, push.normalized() * knockback)
		struck = true
		if pierce > 0:
			pierce -= 1
			if pierce == 0:
				if explode <= 0.0:
					queue_free()
				return true
	return struck


func _explode() -> void:
	for enemy: Node3D in Enemy.within(global_position, explode):
		var push: Vector3 = enemy.centre() - global_position
		enemy.hit(damage, push.normalized() * knockback)
	Fx.burst(get_parent(), global_position, "fireball_explosion", explode * 2.2, tint)
	queue_free()


func _become_pool() -> void:
	mode = "pool"
	life = duration
	net_sheet = pool_sheet
	net_size = pool_radius * 2.2
	for child in get_children():
		child.queue_free()
	add_child(pool_sprite(pool_sheet, net_size))


## A pool lying flat on the ground (guests draw the same one).
static func pool_sprite(sheet: String, size: float) -> Sprite3D:
	var sprite := AnimSprite.make(sheet, size)
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.axis = Vector3.AXIS_Y
	sprite.position.y = 0.08
	return sprite


## Turns a bolt's sprite into two crossed copies lying along -Z, so it reads from any
## camera angle. The art is drawn pointing up-right.
static func lay_flat(holder: Node3D) -> void:
	var flat: Sprite3D = holder.get_child(0)
	flat.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	flat.axis = Vector3.AXIS_Y
	flat.rotation.y = PI * 0.75
	var upright: Sprite3D = flat.duplicate()
	upright.axis = Vector3.AXIS_Z
	upright.rotation = Vector3(0.0, PI * 0.5, -PI * 0.25)
	holder.add_child(upright)
