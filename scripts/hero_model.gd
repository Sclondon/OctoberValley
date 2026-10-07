extends Node3D
## A hero's 3D model (models/<hero>.glb, built by art/build_heroes.py) and its animations:
## idle, run, jump, fall. The model's front is +Z.

const HEROES: Array[String] = ["joe", "matt", "alex", "jon"]
const LOOPS: Array[String] = ["idle", "run", "jump", "fall"]
const BLEND := 0.12

var hero := ""
var anims: AnimationPlayer
var _current := ""


func set_hero(hero_name: String) -> void:
	for child in get_children():
		child.queue_free()
	hero = hero_name
	anims = null
	_current = ""
	var scene: PackedScene = load("res://models/%s.glb" % hero_name)
	if scene == null:
		push_warning("No model for hero '%s'" % hero_name)
		return
	var model := scene.instantiate()
	add_child(model)
	anims = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anims:
		for anim_name in LOOPS:
			if anims.has_animation(anim_name):
				anims.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		play("idle")


## Blends to an animation. `speed` scales the playback, so the run can match the ground speed.
func play(anim_name: String, speed := 1.0) -> void:
	if anims == null or not anims.has_animation(anim_name):
		return
	anims.speed_scale = speed
	if anim_name != _current:
		_current = anim_name
		anims.play(anim_name, BLEND)
