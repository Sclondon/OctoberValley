extends Node3D
## Third-person orbit camera. The mouse (or right stick) turns it, the wheel zooms, and a
## spring arm keeps it out of walls. Main grabs and frees the mouse; a click grabs it back.

const MOUSE_SENS := 0.0028
const STICK_SENS := 2.8
const PITCH_MIN := -1.25
const PITCH_MAX := 0.5
const ZOOM_MIN := 3.0
const ZOOM_MAX := 12.0
const PIVOT_HEIGHT := 1.7

var target: Node3D
var camera: Camera3D
var arm: SpringArm3D
var pitch := -0.3
var distance := 7.0
## Turn slowly by itself (the title screen).
var orbit := false
## Main turns this off while a menu is up.
var grab_on_click := true


func _ready() -> void:
	# moved by hand every frame, so the engine must not smooth it a second time
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arm = SpringArm3D.new()
	arm.spring_length = distance
	arm.collision_mask = 1
	arm.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	arm.shape = probe
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 400.0
	arm.add_child(camera)
	camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotation.y -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance - 0.5, ZOOM_MIN)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance + 0.5, ZOOM_MAX)
		elif not captured and grab_on_click and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	rotation.y -= look.x * STICK_SENS * delta
	if orbit:
		rotation.y += delta * 0.35
	pitch = clampf(pitch - look.y * STICK_SENS * delta, PITCH_MIN, PITCH_MAX)
	rotation.x = pitch
	arm.spring_length = distance
	if target:
		global_position = target.get_global_transform_interpolated().origin + Vector3.UP * PIVOT_HEIGHT
