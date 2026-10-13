extends Node3D
## What every level is made from: boxes and ramps on collision layer 1 drawn with the grid
## shader, billboard props on layer 8 (the hero bumps into them, enemies pass through), signs,
## and the sky. test_level.gd and stage.gd build on this.

const GRID := preload("res://shaders/grid.gdshader")
const TERRAIN := preload("res://shaders/terrain.gdshader")
const NIGHT_SKY := preload("res://shaders/night_sky.gdshader")
const FOG_DENSITY := 0.0065
## Billboards this close to the camera are not drawn, so a tree cannot fill the screen.
const PROP_HIDE_WITHIN := 5.0
const FONT := preload("res://fonts/PixelifySans.ttf")
const AnimSprite := preload("res://scripts/anim_sprite.gd")

## Half the level's width: the walls stand at +/- this on X and Z.
var half_extent := 70.0
var start_position := Vector3(0.0, 0.1, 40.0)
## Where the altar goes. INF means this level has none.
var altar_position := Vector3.INF
var line_color := Color("f0a050")

## The test yard keeps the measuring grid; stages get the pixel terrain.
var greybox := false

var _materials := {}
var _glow_texture: GradientTexture2D


## A static box centred on `at`. Returns the body so callers can turn it.
func block(at: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	return body


## A ramp that starts at `from` (the middle of its bottom edge) and climbs `rise` over `run`
## metres in the direction of `yaw` (0 = north, -Z).
func ramp(from: Vector3, yaw: float, run: float, rise: float, width: float, color: Color) -> void:
	var thickness := 0.5
	var turn := Basis.from_euler(Vector3(atan2(rise, run), yaw, 0.0))
	var forward := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var centre := from + forward * run * 0.5 + Vector3.UP * rise * 0.5 - turn.y * thickness * 0.5
	var body := block(centre, Vector3(width, thickness, Vector2(run, rise).length()), color)
	body.basis = turn


## The ground slab and the four outer walls.
func yard(ground: Color, wall: Color, wall_height: float) -> void:
	block(Vector3(0, -0.5, 0), Vector3(half_extent * 2.0, 1.0, half_extent * 2.0), ground)
	for side: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var size := Vector3(1.0, wall_height, half_extent * 2.0) if side.x != 0.0 else Vector3(half_extent * 2.0, wall_height, 1.0)
		block(Vector3(side.x * half_extent, wall_height * 0.5, side.y * half_extent), size, wall)


## A pixel-art prop standing on the ground, with a small trunk to bump into.
func prop(sheet: String, height: float, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	body.position = at
	var sprite := AnimSprite.make(sheet, height, true, true)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.clock = randf() * 10.0
	if height > 4.0:
		sprite.visibility_range_begin = PROP_HIDE_WITHIN
	body.add_child(sprite)
	if sheet == "street_lamp":
		glow(Vector3(0.0, height * 0.86, 0.0), Color(1.0, 0.78, 0.4, 0.55), 2.6, body)
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = minf(height, 3.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	body.add_child(collider)
	add_child(body)


func sign_post(at: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = 96
	label.outline_size = 24
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.modulate = Color("ffd9a0")
	label.position = at
	add_child(label)


## The sky, fog and moonlight. `look` holds hex colours: sky_top, sky_horizon, ambient, fog, sun.
func build_sky(look: Dictionary) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, 140.0, 0.0)
	sun.light_color = Color(look["sun"])
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)
	var sky_material := ShaderMaterial.new()
	sky_material.shader = NIGHT_SKY
	sky_material.set_shader_parameter("top_color", Color(look["sky_top"]))
	sky_material.set_shader_parameter("horizon_color", Color(look["sky_horizon"]))
	sky_material.set_shader_parameter("moon_color", Color(look["sun"]).lerp(Color.WHITE, 0.4))
	sky_material.set_shader_parameter("moon_dir", sun.basis.z)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(look["ambient"])
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(look["fog"]).lerp(Color(look["sky_horizon"]), 0.35)
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _material(color: Color) -> ShaderMaterial:
	if not _materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = GRID if greybox else TERRAIN
		material.set_shader_parameter("base_color", color)
		if greybox:
			material.set_shader_parameter("line_color", line_color.lerp(color, 0.35))
		else:
			material.set_shader_parameter("accent_color", line_color.lerp(color, 0.25))
		_materials[color] = material
	return _materials[color]


## A soft round glow that always faces the camera (lamp heads, landmark crystals).
func glow(at: Vector3, color: Color, size: float, parent: Node3D = null) -> Sprite3D:
	if _glow_texture == null:
		var fade := Gradient.new()
		fade.set_color(0, Color(1.0, 1.0, 1.0, 0.85))
		fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = fade
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = 32
		_glow_texture.height = 32
	var sprite := Sprite3D.new()
	sprite.texture = _glow_texture
	sprite.pixel_size = size / 32.0
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.modulate = color
	sprite.position = at
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(sprite)
	return sprite
