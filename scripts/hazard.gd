extends Node3D
## Things bosses throw at the hero. A "ball" flies straight and hurts on touch. A "ring" is a
## shockwave that spreads along the ground: jump over it.

const AnimSprite := preload("res://scripts/anim_sprite.gd")
const Team := preload("res://scripts/team.gd")

const GROUP := "hazards"

const RING_WIDTH := 0.9
## How high the hero's feet must be above the ring to clear it.
const RING_CLEARANCE := 0.9

var mode := "ball"
## The ball's sheet, and this hazard's id, for co-op snapshots.
var sheet := ""
var net_id := 0
var damage := 10.0
var velocity := Vector3.ZERO
var life := 6.0
var ring_radius := 1.0
var ring_speed := 11.0
var ring_max := 24.0

var _torus: TorusMesh
## Heroes this ring has already hit.
var _spent := {}


static func ball(parent: Node, at: Vector3, shot_velocity: Vector3, shot_damage: float, ball_sheet: String) -> Node3D:
	var hazard: Node3D = load("res://scripts/hazard.gd").new()
	hazard.sheet = ball_sheet
	hazard.damage = shot_damage
	hazard.velocity = shot_velocity
	hazard.position = at
	hazard.add_child(ball_sprite(ball_sheet))
	parent.add_child(hazard)
	return hazard


## The red-tinted sprite of a boss shot (guests draw the same one).
static func ball_sprite(ball_sheet: String) -> Sprite3D:
	var sprite := AnimSprite.make(ball_sheet, 1.3)
	sprite.modulate = Color(1.0, 0.45, 0.45)
	return sprite


static func ring(parent: Node, at: Vector3, ring_damage: float, max_radius: float) -> Node3D:
	var hazard: Node3D = load("res://scripts/hazard.gd").new()
	hazard.mode = "ring"
	hazard.damage = ring_damage
	hazard.ring_max = max_radius
	hazard.position = at + Vector3.UP * 0.2
	parent.add_child(hazard)
	return hazard


func _ready() -> void:
	add_to_group(GROUP)
	net_id = Team.next_id()
	if mode != "ring":
		return
	add_child(ring_visual())
	_torus = get_child(0).mesh
	_set_ring()


## The shockwave's mesh (guests draw the same one).
static func ring_visual() -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ff5a3c")
	var torus := TorusMesh.new()
	torus.material = material
	torus.rings = 48
	torus.ring_segments = 6
	var visual := MeshInstance3D.new()
	visual.mesh = torus
	visual.scale.y = 0.5
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual


func _physics_process(delta: float) -> void:
	if mode == "ball":
		global_position += velocity * delta
		life -= delta
		for hero: Node3D in Team.alive():
			var centre: Vector3 = hero.centre()
			if global_position.distance_to(centre) < 1.0:
				hero.hurt(damage, global_position)
				queue_free()
				return
		if life <= 0.0:
			queue_free()
		return
	ring_radius += ring_speed * delta
	_set_ring()
	for hero: Node3D in Team.alive():
		var offset := hero.global_position - global_position
		var flat := Vector2(offset.x, offset.z).length()
		if not _spent.has(hero) and absf(flat - ring_radius) < RING_WIDTH and offset.y < RING_CLEARANCE and offset.y > -2.5:
			_spent[hero] = true
			hero.hurt(damage, global_position)
	if ring_radius >= ring_max:
		queue_free()


func _set_ring() -> void:
	_torus.inner_radius = maxf(ring_radius - 0.35, 0.05)
	_torus.outer_radius = ring_radius + 0.35
