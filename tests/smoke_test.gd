extends SceneTree
## Headless check of the basics in the test yard: the hero stands, runs, jumps and double
## jumps; every hero model loads with its animations; the director spawns enemies and they
## close in.
##
##     godot --headless --path . -s res://tests/smoke_test.gd

const HeroModel := preload("res://scripts/hero_model.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Touch := preload("res://scripts/touch.gd")

var main: Node3D
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "test"
	main.spawn_enemies = false
	root.add_child(main)
	_run()


func check(what: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		failures += 1


func frames(count: int) -> void:
	for i in count:
		await physics_frame


## A finger going down or coming up at `at` (in screen layout units, as the HUD sees them).
func finger(index: int, at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = root.get_final_transform() * at
	event.pressed = down
	Input.parse_input_event(event)


func drag(index: int, from: Vector2, to: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = root.get_final_transform() * to
	event.relative = root.get_final_transform().basis_xform(to - from)
	Input.parse_input_event(event)


func _run() -> void:
	await process_frame  # main builds itself once the tree starts
	var player: CharacterBody3D = main.player
	await frames(30)
	check("stands on the floor", player.is_on_floor(), "y=%.2f" % player.global_position.y)

	var from := player.global_position
	Input.action_press("move_forward")
	await frames(60)
	var ran := from.z - player.global_position.z
	check("runs forward", ran > 5.0 and ran < 8.0, "%.1f m in 1 s" % ran)
	check("plays the run", player.model.anims.current_animation == "run")
	Input.action_press("sprint")
	await frames(30)
	check("sprints", player.ground_speed() > 9.5, "%.1f m/s" % player.ground_speed())
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await frames(30)
	check("stops", player.ground_speed() < 0.1)

	var peak := 0.0
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	for i in 60:
		await physics_frame
		peak = maxf(peak, player.global_position.y)
	check("jumps", peak > 2.3 and peak < 3.3, "peak %.2f m" % peak)
	await frames(30)

	peak = 0.0
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(24)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	for i in 90:
		await physics_frame
		peak = maxf(peak, player.global_position.y)
	check("double jumps", peak > 4.5, "peak %.2f m" % peak)
	check("lands", player.is_on_floor())

	# touch: a thumb on the left half is a stick, the right half turns the view, JUMP jumps
	var view := root.get_visible_rect().size
	from = player.global_position
	var thumb := Vector2(200.0, view.y - 200.0)
	finger(0, thumb, true)
	drag(0, thumb, thumb + Vector2(0.0, -120.0))
	await frames(60)
	check("touch is noticed", Touch.active and main.touch.visible)
	check("touch stick runs forward", from.z - player.global_position.z > 4.0, "%.1f m in 1 s" % (from.z - player.global_position.z))
	var yaw: float = main.cam.rotation.y
	finger(1, Vector2(view.x * 0.75, view.y * 0.5), true)
	drag(1, Vector2(view.x * 0.75, view.y * 0.5), Vector2(view.x * 0.75 + 90.0, view.y * 0.5))
	await frames(2)
	check("touch drag turns the view while moving", absf(main.cam.rotation.y - yaw) > 0.3, "%.2f rad" % (main.cam.rotation.y - yaw))
	finger(1, Vector2(view.x * 0.75 + 90.0, view.y * 0.5), false)
	finger(0, thumb, false)
	await frames(30)
	check("letting go stops", player.ground_speed() < 0.1)
	view = root.get_visible_rect().size
	finger(2, Vector2(view.x - 96.0, view.y - 110.0), true)
	await frames(8)
	check("touch JUMP jumps", not player.is_on_floor(), "y=%.2f" % player.global_position.y)
	finger(2, Vector2(view.x - 96.0, view.y - 110.0), false)
	await frames(90)
	finger(3, Vector2(view.x - 40.0, 52.0), true)
	finger(3, Vector2(view.x - 40.0, 52.0), false)
	await frames(4)
	check("touch pause opens the menu", main.state == "paused")
	main._resume()
	await frames(2)
	check("touch never grabs the mouse", Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)

	for hero in HeroModel.HEROES:
		player.set_hero(hero)
		await frames(2)
		var anims: AnimationPlayer = player.model.anims
		var ok := anims != null
		for anim_name in HeroModel.LOOPS:
			ok = ok and anims.has_animation(anim_name)
		check("model " + hero, ok)

	main.director.enabled = true
	await frames(60 * 14)  # the first minute is a warm-up, so give it time
	var enemies: Array = Enemy.all
	check("enemies spawn", enemies.size() + player.kills >= 4, "%d alive, %d killed" % [enemies.size(), player.kills])
	var nearest := INF
	for enemy: Node3D in enemies:
		nearest = minf(nearest, enemy.global_position.distance_to(player.global_position))
	check("enemies close in", nearest < 12.0 or player.kills > 0, "nearest %.1f m, %d killed" % [nearest, player.kills])

	print("SMOKE TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(failures)
