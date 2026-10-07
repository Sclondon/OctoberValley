extends SceneTree
## Headless check of the whole loop: weapons kill, candy levels the hero up, an upgrade card
## works, the altar summons the boss, the boss attacks and dies, the portal leads to stage 2,
## death shows the game-over screen, and TRY AGAIN starts over.
##
##     godot --headless --path . -s res://tests/loop_test.gd

const Db := preload("res://scripts/db.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Weapon := preload("res://scripts/weapon.gd")
const Hazard := preload("res://scripts/hazard.gd")
const Pickup := preload("res://scripts/pickup.gd")

var main: Node3D
var failures := 0
## Keeps the hero alive while the test watches something else.
var immortal := true
var upgrades_taken := 0
var hazards_seen := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "run"
	root.add_child(main)
	_run()


func check(what: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		failures += 1


## Waits, and meanwhile plays the bot's part: stay alive, take the first card offered.
func frames(count: int) -> void:
	for i in count:
		await physics_frame
		if immortal:
			main.player.hp = main.player.max_hp()
		if main.state == "upgrade" and not main.menus._cards.is_empty():
			main.menus._cards[0].pressed.emit()
			upgrades_taken += 1
		for child in main.world.get_children():
			if child.get_script() == Hazard:
				hazards_seen += 1


func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)


func _run() -> void:
	await process_frame  # main builds itself once the tree starts
	var player: CharacterBody3D = main.player
	var director: Node = main.director
	check("starts in stage 1", main.state == "playing" and main.stage_title == Db.STAGES[0]["name"], main.stage_title)
	check("has an altar far away", main.altar != null and main.altar.global_position.distance_to(player.global_position) > 70.0)
	check("starts with the hero's weapon", player.weapons.size() == 1 and player.weapons[0].id == Db.HEROES["joe"]["weapon"])

	# one of every weapon, so each behaviour runs
	for id: String in Db.WEAPONS:
		if player.weapon_level(id) == 0:
			player.weapons.append(Weapon.new(id))
	await frames(60 * 20)
	# the bot stands still, so pull in the candy that dropped out of reach
	for pickup in get_nodes_in_group(Pickup.GROUP):
		pickup.vacuum = true
	await frames(60 * 4)
	check("weapons kill", player.kills >= 10, "%d kills" % player.kills)
	check("candy levels the hero up", player.level >= 2, "level %d" % player.level)
	check("upgrade cards work", upgrades_taken >= 1 and main.state == "playing", "%d taken" % upgrades_taken)

	player.respawn(main.altar.global_position + Vector3(2.0, 0.2, 0.0))
	await frames(10)
	check("altar offers the boss", main.altar.prompt(player.global_position) != "")
	await press("interact")
	var boss: Node3D = director.boss
	check("boss arrives", boss != null and boss.is_boss)
	if boss:
		# out of the weapons' reach, so the boss lives long enough to use every attack
		boss.hp = 1.0e9
		boss.max_hp = 2.0e9
		await frames(60 * 22)
		check("boss attacks", hazards_seen > 0, "%d hazard frames" % hazards_seen)
		boss.hit(boss.hp)
		await frames(5)
		check("boss death opens the portal", main.altar.state == "portal" and director.boss == null)
		check("the horde stops", Enemy.all.is_empty() and not director.spawning)
		await frames(120)
		player.respawn(main.altar.global_position + Vector3(2.0, 0.2, 0.0))
		await frames(10)
		await press("interact")
		check("portal leads to stage 2", main.stage_index == 1 and main.stage_title == Db.STAGES[1]["name"], main.stage_title)
		check("hero keeps their build", player.weapons.size() == Db.WEAPONS.size() and player.level >= 2)
		await frames(60 * 6)
		check("stage 2 spawns its roster", Enemy.all.size() > 0, "%d alive" % Enemy.all.size())

	immortal = false
	player.hurt(1.0e6, player.global_position + Vector3.FORWARD)
	await frames(60 * 2)
	check("death shows game over", main.state == "dead" and main.menus.visible and paused)
	main.menus.retried.emit()
	await frames(10)
	check("try again restarts", main.state == "playing" and main.stage_index == 0 and player.level == 1 and not player.dead and player.weapons.size() == 1)

	print("LOOP TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(failures)
