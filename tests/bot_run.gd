extends SceneTree
## A crude bot plays a real run, for checking the balance rather than the code: it kites in
## circles for a while, runs to the altar, fights the boss, and takes the portal. It always
## picks the first card. It logs its state every 30 s and ends on death or after `STAGES`.
##
##     godot --headless --fixed-fps 60 --path . -s res://tests/bot_run.gd -- [hero] [farm seconds]

const STAGES := 2
const TIME_LIMIT := 900.0

var main: Node3D
var hero := "joe"
var farm_time := 150.0
var low_hp := 1.0e9


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		hero = args[0]
	if args.size() > 1:
		farm_time = float(args[1])
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "run"
	main.hero = hero
	root.add_child(main)
	_run()


func _run() -> void:
	await process_frame  # main builds itself once the tree starts
	var player: CharacterBody3D = main.player
	var director: Node = main.director
	var next_log := 30.0
	var boss_began := -1.0
	Input.action_press("move_forward")
	while director.time < TIME_LIMIT:
		await physics_frame
		if main.state == "upgrade" and not main.menus._cards.is_empty():
			main.menus._cards[0].pressed.emit()
			continue
		if main.state == "dead" or player.dead:
			var boss_left := "no boss"
			if director.boss:
				boss_left = "boss at %d%%" % int(director.boss.hp / director.boss.max_hp * 100.0)
			print("DIED at %s, stage %d, level %d, %d kills, %s" % [_clock(director.time), main.stage_index + 1, player.level, player.kills, boss_left])
			break
		if main.stage_index >= STAGES:
			print("CLEARED %d stages at %s, level %d, %d kills, lowest health %d" % [STAGES, _clock(director.time), player.level, player.kills, low_hp])
			break
		low_hp = minf(low_hp, player.hp)
		var altar: Node3D = main.altar
		var to_altar := altar.global_position - player.global_position
		var kiting: bool = director.boss != null or director.stage_time < farm_time
		if kiting:
			main.cam.rotation.y += 0.6 / 60.0
			if director.boss and boss_began < 0.0:
				boss_began = director.time
		else:
			main.cam.rotation.y = atan2(-to_altar.x, -to_altar.z)
			if altar.prompt(player.global_position) != "":
				if altar.state == "portal" and boss_began >= 0.0:
					print("boss down in %d s" % int(director.time - boss_began))
					boss_began = -1.0
				altar.interact()
		# hop over shockwaves and obstacles
		if player.is_on_floor() and (player.is_on_wall() or (director.boss and int(director.time * 60.0) % 50 == 0)):
			Input.action_press("jump")
		else:
			Input.action_release("jump")
		if director.time >= next_log:
			next_log += 30.0
			var names: Array = player.weapons.map(func(weapon: RefCounted) -> String: return "%s %d" % [weapon.id, weapon.level])
			print("%s  stage %d  lv %d  hp %d/%d  kills %d  alive %d  diff %.1f  %s" % [_clock(director.time), main.stage_index + 1,
				player.level, player.hp, player.max_hp(), player.kills, director.alive(), director.difficulty(), ", ".join(names)])
	quit()


func _clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
