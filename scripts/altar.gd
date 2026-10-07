extends Node3D
## The stage's goal, marked by a beam of light you can see from anywhere. It works like Risk
## of Rain 2's teleporter: interact to summon the boss, then hold the ground around it while
## it charges. When the boss is dead and the charge is full it becomes the portal to the next
## stage.

const Team := preload("res://scripts/team.gd")

signal summoned
signal entered
## The boss is dead and the charge is full: the portal is open.
signal opened

const REACH := 5.0
## Seconds of a hero standing inside CHARGE_RADIUS to fill the charge.
const CHARGE_TIME := 75.0
const CHARGE_RADIUS := 24.0
const COLORS := {"idle": Color("b070ff"), "boss": Color("ff4030"), "portal": Color("50ffc0")}

## idle, boss (summoned: fight and charge) or portal
var state := "idle"
## 0 to 1
var charge := 0.0
var boss_dead := false
## False on co-op guests, who are told the state and charge by the host.
var simulate := true

var _beam: StandardMaterial3D
var _ring: MeshInstance3D
var _zone: MeshInstance3D


func _ready() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("3a3448")
	stone.roughness = 1.0
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 3.2
	base_mesh.bottom_radius = 3.6
	base_mesh.height = 0.2
	base_mesh.material = stone
	var base := MeshInstance3D.new()
	base.mesh = base_mesh
	base.position.y = 0.1
	add_child(base)

	_beam = StandardMaterial3D.new()
	_beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam.disable_fog = true
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.6
	beam_mesh.bottom_radius = 0.6
	beam_mesh.height = 160.0
	beam_mesh.material = _beam
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.position.y = 80.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.5
	ring_mesh.outer_radius = 1.9
	ring_mesh.material = _beam
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.position.y = 2.2
	_ring.rotation.x = PI * 0.5
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# the edge of the ground to hold while it charges
	var zone_mesh := TorusMesh.new()
	zone_mesh.inner_radius = CHARGE_RADIUS - 0.25
	zone_mesh.outer_radius = CHARGE_RADIUS
	zone_mesh.rings = 96
	zone_mesh.ring_segments = 4
	zone_mesh.material = _beam
	_zone = MeshInstance3D.new()
	_zone.mesh = zone_mesh
	_zone.position.y = 0.15
	_zone.scale.y = 0.4
	_zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_zone)
	_show_state()


func _process(delta: float) -> void:
	_ring.rotation.y += delta * (3.0 if state == "portal" else 0.8)
	if not simulate or state != "boss":
		return
	if charge < 1.0 and _held():
		charge = minf(charge + delta / CHARGE_TIME, 1.0)
	if boss_dead and charge >= 1.0:
		set_state("portal")
		opened.emit()


## True while a living hero stands inside the charge ring.
func _held() -> bool:
	for hero: Node3D in Team.alive():
		var offset := hero.global_position - global_position
		if Vector2(offset.x, offset.z).length() < CHARGE_RADIUS:
			return true
	return false


## What the HUD should offer the hero standing at `from`, or "" if out of reach.
func prompt(from: Vector3) -> String:
	if Vector2(from.x - global_position.x, from.z - global_position.z).length() > REACH:
		return ""
	match state:
		"idle":
			return "Summon the boss"
		"portal":
			return "Enter the portal"
	return ""


func interact() -> void:
	if state == "idle":
		set_state("boss")
		summoned.emit()
	elif state == "portal":
		entered.emit()


func set_state(new_state: String) -> void:
	if new_state != state:
		state = new_state
		_show_state()


func _show_state() -> void:
	var color: Color = COLORS[state]
	_beam.albedo_color = Color(color, 0.55)
	_ring.visible = state != "boss"
	_zone.visible = state == "boss"
