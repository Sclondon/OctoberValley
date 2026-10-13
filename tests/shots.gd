extends SceneTree
## Screenshots for eyeballing the game. Needs a window (no --headless):
##
##     godot --path . -s res://tests/shots.gd -- <out dir> [WIDTHxHEIGHT] [--touch]
##
## Saves title, fight (every weapon firing), cards, altar, boss, charge, portal, stage2, stage3,
## pause, gameover, coop and lobby. Give a size to see a phone (390x844 upright, 844x390 on its
## side); --touch draws the touch controls as a phone would.

const Db := preload("res://scripts/db.gd")
const Weapon := preload("res://scripts/weapon.gd")
const Save := preload("res://scripts/save.gd")

var main: Node3D
var out_dir := "user://shots"
var immortal := true
## Hold the upgrade screen open instead of picking a card.
var hold_cards := false
var window_size := Vector2i.ZERO


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1 and args[1].contains("x"):
		var parts := args[1].split("x")
		window_size = Vector2i(int(parts[0]), int(parts[1]))
	DirAccess.make_dir_recursive_absolute(out_dir)
	Save.path = ""  # pictures leave no saves behind
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func frames(count: int) -> void:
	for i in count:
		await physics_frame
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if immortal:
			main.player.hp = main.player.max_hp()
		if main.state == "upgrade" and not hold_cards and not main.menus._cards.is_empty():
			main.menus._cards[0].pressed.emit()


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(file))
	print("saved ", file)


func _run() -> void:
	await process_frame  # main builds itself once the tree starts
	if window_size != Vector2i.ZERO:
		root.borderless = true  # a titled window cannot be made as narrow as a phone
		DisplayServer.window_set_size(window_size)
		DisplayServer.window_set_position(Vector2i(40, 40))
		await process_frame
		await process_frame
	var player: CharacterBody3D = main.player
	await frames(40)
	await shot("title.png")

	main.start_run("alex")
	await frames(30)
	await shot("start.png")
	for id: String in Db.WEAPONS:
		if player.weapon_level(id) == 0:
			player.weapons.append(Weapon.new(id))
	player.inventory_changed.emit()
	main.director.time = 120.0
	await frames(60 * 14)
	await shot("fight.png")
	immortal = false
	player.hp = player.max_hp() * 0.2
	await frames(8)
	await shot("lowhealth.png")
	immortal = true

	hold_cards = true
	for pickup in get_nodes_in_group("pickups"):
		pickup.vacuum = true
	for i in 240:
		await frames(1)
		if main.state == "upgrade":
			break
	await frames(30)
	await shot("cards.png")
	hold_cards = false
	await frames(5)

	player.respawn(main.altar.global_position + Vector3(2.0, 0.2, 6.0))
	main.cam.rotation.y = 0.0
	await frames(30)
	await shot("altar.png")
	player.respawn(main.altar.global_position + Vector3(2.0, 0.2, 0.0))
	await frames(5)
	main.altar.interact()
	await frames(50)
	await shot("bossintro.png")
	var boss: Node3D = main.director.boss
	boss.hp = 1.0e9
	boss.max_hp = 2.0e9
	main.cam.distance = 12.0
	await frames(60 * 6)
	await shot("boss.png")
	boss.hit(boss.hp)
	await frames(60)
	await shot("charge.png")
	main.altar.charge = 1.0
	await frames(90)
	await shot("portal.png")

	for stage in [2, 3]:
		main.altar.interact()
		main.cam.distance = 9.0
		await frames(60 * 8)
		await shot("stage%d.png" % stage)
		main.altar.set_state("portal")

	var pause := InputEventAction.new()
	pause.action = "pause"
	pause.pressed = true
	Input.parse_input_event(pause)
	await frames(10)
	await shot("pause.png")
	main._resume()
	await frames(5)

	immortal = false
	player.hurt(1.0e6, player.global_position + Vector3.FORWARD)
	await frames(60 * 3)
	await shot("gameover.png")

	main.leave_coop()
	await frames(10)
	main.menus.coop()
	await frames(10)
	await shot("coop.png")
	main.menus.lobby("WXYZ", [{"slot": 0, "name": "", "hero": "joe"}, {"slot": 1, "name": "", "hero": "alex"}, {"slot": 2, "name": "", "hero": "jon", "away": true}], 0, true)
	await frames(10)
	await shot("lobby.png")
	quit()
