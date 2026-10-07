extends SceneTree
## Screenshots for eyeballing the game. Needs a window (no --headless):
##
##     godot --path . -s res://tests/shots.gd -- <out dir>
##
## Saves title.png, fight.png (every weapon firing), cards.png, boss.png, stage2.png,
## stage3.png and gameover.png.

const Db := preload("res://scripts/db.gd")
const Weapon := preload("res://scripts/weapon.gd")

var main: Node3D
var out_dir := "user://shots"
var immortal := true
## Hold the upgrade screen open instead of picking a card.
var hold_cards := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
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
	var player: CharacterBody3D = main.player
	await frames(40)
	await shot("title.png")

	main.start_run("alex")
	for id: String in Db.WEAPONS:
		if player.weapon_level(id) == 0:
			player.weapons.append(Weapon.new(id))
	player.inventory_changed.emit()
	main.director.time = 120.0
	main.cam.distance = 10.0
	main.cam.pitch = -0.45
	await frames(60 * 14)
	await shot("fight.png")

	hold_cards = true
	for pickup in get_nodes_in_group("pickups"):
		pickup.vacuum = true
	for i in 240:
		await frames(1)
		if main.state == "upgrade":
			break
	await frames(5)
	await shot("cards.png")
	hold_cards = false
	await frames(5)

	player.respawn(main.altar.global_position + Vector3(2.0, 0.2, 0.0))
	await frames(20)
	await shot("altar.png")
	main.altar.interact()
	var boss: Node3D = main.director.boss
	boss.hp = 1.0e9
	boss.max_hp = 2.0e9
	main.cam.distance = 12.0
	await frames(60 * 6)
	await shot("boss.png")
	boss.hit(boss.hp)
	main.altar.charge = 1.0
	await frames(90)

	for stage in [2, 3]:
		main.altar.interact()
		main.cam.distance = 9.0
		await frames(60 * 8)
		await shot("stage%d.png" % stage)
		main.altar.set_state("portal")

	immortal = false
	player.hurt(1.0e6, player.global_position + Vector3.FORWARD)
	await frames(60 * 2)
	await shot("gameover.png")
	quit()
