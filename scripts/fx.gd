extends RefCounted
## Throwaway effects: floating damage numbers, one-shot sprite bursts, puffs of pixels, rings
## that spread along the ground, and the camera shake.

const AnimSprite := preload("res://scripts/anim_sprite.gd")
const Sfx := preload("res://scripts/sfx.gd")
const FONT := preload("res://fonts/PixelifySans.ttf")
const MAX_NUMBERS := 40
const MAX_PUFFS := 28
const INK_DARK := Color("1a1026")

static var _numbers := 0
static var _puffs := 0
static var _puff_mesh: QuadMesh
static var _ring_mesh: TorusMesh
## While true (the co-op host), numbers and bursts are also noted in `events` for the guests:
## ["n", at, amount, colour] or ["b", at, sheet, height, colour, upright]. Puffs, rings and
## shakes are not sent: guests make their own from what they see.
static var record := false
static var events: Array = []
## The camera rig, which does the shaking. Main sets it.
static var rig: Node3D


## A number that pops up at `at`, drifts up and fades. Bigger hits are drawn bigger.
static func number(parent: Node, at: Vector3, amount: float, color := Color.WHITE) -> void:
	if record and events.size() < 60:
		events.append(["n", at, amount, color])
	if _numbers >= MAX_NUMBERS or not parent.is_inside_tree():
		return
	_numbers += 1
	var label := Label3D.new()
	label.text = str(maxi(int(round(amount)), 1))
	label.font = FONT
	label.font_size = 64
	label.outline_size = 10
	label.outline_modulate = INK_DARK
	label.pixel_size = 0.011 * clampf(0.85 + amount / 120.0, 0.85, 1.7)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.no_depth_test = true
	label.fixed_size = false
	label.modulate = color
	label.position = at + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
	label.scale = Vector3.ONE * 0.4
	parent.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector3.ONE * 1.25, 0.08)
	tween.tween_property(label, "scale", Vector3.ONE, 0.1)
	tween.parallel().tween_property(label, "position:y", label.position.y + 1.4, 0.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(label, "outline_modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	tween.tween_callback(label.queue_free)
	label.tree_exited.connect(func() -> void: _numbers -= 1)


## Plays a sheet once at `at` and removes it. `upright` keeps it vertical (lightning).
static func burst(parent: Node, at: Vector3, sheet: String, height: float, tint := Color.WHITE, upright := false) -> Sprite3D:
	if record and events.size() < 60:
		events.append(["b", at, sheet, height, tint, upright])
	Sfx.for_sheet(sheet, at)
	var sprite := AnimSprite.make(sheet, height)
	if upright:
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.loop = false
	sprite.modulate = tint
	sprite.position = at
	sprite.finished.connect(sprite.queue_free)
	parent.add_child(sprite)
	return sprite


## A spray of square pixels: something died, or landed, or was picked up.
static func puff(parent: Node, at: Vector3, color: Color, amount := 10, power := 1.0) -> void:
	if _puffs >= MAX_PUFFS or parent == null or not parent.is_inside_tree():
		return
	_puffs += 1
	if _puff_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.billboard_keep_scale = true
		_puff_mesh = QuadMesh.new()
		_puff_mesh.size = Vector2(0.16, 0.16)
		_puff_mesh.material = material
	var spray := CPUParticles3D.new()
	spray.mesh = _puff_mesh
	spray.amount = amount
	spray.lifetime = 0.55
	spray.one_shot = true
	spray.explosiveness = 1.0
	spray.direction = Vector3.UP
	spray.spread = 75.0
	spray.initial_velocity_min = 2.5 * power
	spray.initial_velocity_max = 7.0 * power
	spray.gravity = Vector3(0.0, -18.0, 0.0)
	spray.scale_amount_min = 0.7 * power
	spray.scale_amount_max = 1.8 * power
	spray.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color.WHITE)
	ramp.set_color(1, Color(0.55, 0.55, 0.6, 0.0))
	spray.color_ramp = ramp
	spray.position = at
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(spray)
	spray.emitting = true
	spray.tree_exited.connect(func() -> void: _puffs -= 1)
	var tween := spray.create_tween()
	tween.tween_interval(0.8)
	tween.tween_callback(spray.queue_free)


## A ring that spreads along the ground and fades: a level-up, a landing, a summons.
static func ring(parent: Node, at: Vector3, color: Color, radius := 4.0, seconds := 0.45) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.9
		_ring_mesh.outer_radius = 1.0
		_ring_mesh.rings = 40
		_ring_mesh.ring_segments = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	var visual := MeshInstance3D.new()
	visual.mesh = _ring_mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.position = at + Vector3.UP * 0.12
	visual.scale = Vector3(0.3, 0.5, 0.3)
	parent.add_child(visual)
	var tween := visual.create_tween()
	tween.tween_property(visual, "scale", Vector3(radius, 0.5, radius), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, seconds).set_ease(Tween.EASE_IN)
	tween.tween_callback(visual.queue_free)


## Shakes the camera (0 to 1). With `at`, less the further away it happened.
static func shake(amount: float, at := Vector3.INF) -> void:
	if not is_instance_valid(rig):
		return
	if at != Vector3.INF:
		amount *= clampf(1.0 - rig.global_position.distance_to(at) / 45.0, 0.0, 1.0)
	if amount > 0.02:
		rig.add_shake(amount)
