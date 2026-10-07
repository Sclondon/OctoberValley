extends SceneTree
## Co-op, end to end, with two copies of the game and a rooms server (tools/dev_relay.mjs).
## Run one copy as the host and one as the guest, sharing a file for the room code:
##
##     node tools/dev_relay.mjs <scareathon-v3/server> 3111
##     godot --headless --path . -s res://tests/coop_test.gd -- host  <code file> --server=http://127.0.0.1:3111
##     godot --headless --path . -s res://tests/coop_test.gd -- guest <code file> --server=http://127.0.0.1:3111
##
## The host makes the room, starts when the guest is in, fights, gives the guest a level,
## beats the boss, takes the portal, then lets everyone die. Each copy prints its own checks.
## Add --shots=<dir> to a copy run with a window to save pictures of what it sees.

const Db := preload("res://scripts/db.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Flags := preload("res://scripts/flags.gd")

const TIME_LIMIT := 120.0

var main: Node3D
var role := "host"
var code_file := ""
var failures := 0
var immortal := true
var clock := 0.0
var most_enemies := 0
var most_things := 0
var cards_taken := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	code_file = args[1]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	if role == "host":
		_host()
	else:
		_guest()


func check(what: String, ok: bool, detail := "") -> void:
	print("%s %s: %s %s" % ["PASS" if ok else "FAIL", role, what, detail])
	if not ok:
		failures += 1


func finish() -> void:
	print("COOP %s %s" % [role.to_upper(), "PASSED" if failures == 0 else "FAILED (%d)" % failures])
	quit(failures)


## Waits until `ready` returns true. Fails the test (and returns false) after `limit` seconds.
func until(what: String, ready: Callable, limit := 30.0) -> bool:
	var waited := 0.0
	while not ready.call():
		await physics_frame
		waited += 1.0 / 60.0
		clock += 1.0 / 60.0
		_tick()
		if waited > limit or clock > TIME_LIMIT:
			check(what, false, "(timed out)")
			return false
	check(what, true)
	return true


func frames(count: int) -> void:
	for i in count:
		await physics_frame
		clock += 1.0 / 60.0
		_tick()


## The bot's part on every frame: stay alive, take the first card, note what is on screen.
func _tick() -> void:
	if immortal and main.sync and main.net.is_host:
		for hero: Node3D in main.heroes.values():
			hero.hp = hero.max_hp()
	if main.state == "upgrade" and not main.menus._cards.is_empty():
		main.menus._cards[0].pressed.emit()
		cards_taken += 1
	if main.sync and not main.net.is_host:
		most_enemies = maxi(most_enemies, main.sync.enemy_count())
		most_things = maxi(most_things, main.sync._things.size())


func shot(file: String) -> void:
	var dir := Flags.value("shots")
	if dir == "":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.cam.rotation.y = atan2(main.player.global_position.x - main.heroes[0].global_position.x, main.player.global_position.z - main.heroes[0].global_position.z) if role == "guest" else 0.0
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join("%s_%s.png" % [role, file]))


func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)


func _host() -> void:
	await process_frame
	var net: Node = main.net
	net.create("joe")
	if not await until("makes a room", func() -> bool: return net.code != "", 10.0):
		return finish()
	var file := FileAccess.open(code_file, FileAccess.WRITE)
	file.store_string(net.code)
	file.close()
	check("is in the lobby as host", main.state == "lobby" and net.is_host and net.slot == 0)
	await shot("lobby")
	if not await until("guest joins", func() -> bool: return net.players.size() == 2, 30.0):
		return finish()
	await until("sees the guest's hero pick", func() -> bool: return net.players.any(func(p: Dictionary) -> bool: return p["hero"] == "alex"), 10.0)
	net.start_game()
	if not await until("game starts", func() -> bool: return main.state == "playing" and main.heroes.size() == 2, 10.0):
		return finish()
	var mate: Node3D = main.heroes[1]
	check("guest's hero is Alex, run here", mate.hero == "alex" and mate.driven and mate.simulate)
	var from: Vector3 = mate.global_position
	await until("guest's hero moves", func() -> bool: return mate.global_position.distance_to(from) > 4.0, 20.0)
	await until("the team gets kills", func() -> bool: return main.player.kills >= 5, 40.0)
	check("guest's weapons fight too", mate.weapons.size() == 1 and mate.weapons[0].id == "crossbow")

	var before: int = mate.inventory_rev
	mate.levels_owed += 1
	await until("guest picks an upgrade card", func() -> bool: return mate.inventory_rev > before and mate.levels_owed == 0, 15.0)

	main.player.respawn(main.altar.global_position + Vector3(2.0, 0.2, 0.0))
	await frames(10)
	await press("interact")
	check("boss arrives", main.director.boss != null)
	main.director.boss.hp = 1.0e9
	await frames(60 * 6)
	main.director.boss.hit(1.0e9)
	await frames(30)
	check("portal opens", main.altar.state == "portal")
	main.player.respawn(main.altar.global_position + Vector3(2.0, 0.2, 0.0))
	await frames(10)
	await press("interact")
	check("stage 2", main.stage_index == 1)
	await frames(60 * 5)

	immortal = false
	mate.hurt(1.0e6, mate.global_position + Vector3.FORWARD)
	await frames(30)
	check("one down is not game over", mate.dead and main.state != "dead")
	main.player.hurt(1.0e6, main.player.global_position + Vector3.FORWARD)
	await until("everyone down ends the run", func() -> bool: return main.state == "dead" and main.menus.visible, 5.0)
	await frames(60 * 3)
	finish()


func _guest() -> void:
	await process_frame
	var net: Node = main.net
	var waited := 0.0
	while not FileAccess.file_exists(code_file) and waited < 30.0:
		await frames(10)
		waited += 10.0 / 60.0
	net.join(FileAccess.get_file_as_string(code_file).strip_edges(), "joe")
	if not await until("joins the room", func() -> bool: return net.slot == 1 and main.state == "lobby", 10.0):
		return finish()
	net.pick_hero("alex")
	if not await until("game starts", func() -> bool: return main.state == "playing", 30.0):
		return finish()
	check("is a guest with two heroes", main.is_guest() and main.heroes.size() == 2 and main.player.hero == "alex")
	check("built the host's stage", main.stage_title == Db.STAGES[0]["name"] and main.altar != null)
	check("runs no enemies of its own", Enemy.all.is_empty() and not main.director.enabled)
	Input.action_press("move_forward")
	var mate: Node3D = main.heroes[0]
	await until("sees enemies", func() -> bool: return most_enemies > 0, 30.0)
	await until("sees shots and loot", func() -> bool: return most_things > 0, 30.0)
	await until("sees the host's hero", func() -> bool: return mate.driven and mate.global_position.length() > 1.0, 10.0)
	await until("gets the team's kills", func() -> bool: return main.player.kills >= 5, 40.0)
	await shot("fight")
	await until("is offered and takes a card", func() -> bool: return cards_taken >= 1 and main.player.weapons[0].level + main.player.weapons.size() + main.player.passives.size() > 2, 40.0)
	await until("sees the boss", func() -> bool: return not main.boss_info().is_empty(), 30.0)
	main.player.respawn(main.altar.global_position + Vector3(9.0, 0.2, 0.0))
	await frames(60)
	await shot("boss")
	Input.action_release("move_forward")
	await until("follows to stage 2", func() -> bool: return main.stage_index == 1 and main.stage_title == Db.STAGES[1]["name"], 30.0)
	check("no local enemies leaked", Enemy.all.is_empty())
	await until("is told when it is down", func() -> bool: return main.player.dead, 30.0)
	await until("game over arrives", func() -> bool: return main.state == "dead" and main.menus.visible, 15.0)
	finish()
