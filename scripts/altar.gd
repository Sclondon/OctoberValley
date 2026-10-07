extends Node3D
## The stage's goal, marked by a beam of light you can see from anywhere. Interact to summon
## the boss; when the boss dies the altar becomes the portal to the next stage.

signal summoned
signal entered

const REACH := 5.0
const COLORS := {"idle": Color("b070ff"), "boss": Color("ff4030"), "portal": Color("50ffc0")}

var state := "idle"

var _beam: StandardMaterial3D
var _ring: MeshInstance3D


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
	_show_state()


func _process(delta: float) -> void:
	_ring.rotation.y += delta * (3.0 if state == "portal" else 0.8)


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
		state = "boss"
		summoned.emit()
	elif state == "portal":
		entered.emit()
	_show_state()


func open_portal() -> void:
	set_state("portal")


func set_state(new_state: String) -> void:
	if new_state != state:
		state = new_state
		_show_state()


func _show_state() -> void:
	var color: Color = COLORS[state]
	_beam.albedo_color = Color(color, 0.55)
	_ring.visible = state != "boss"
