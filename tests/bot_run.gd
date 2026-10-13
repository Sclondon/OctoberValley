extends SceneTree
## A bot plays a real run, for checking the balance rather than the code. Two bots:
##
##   kite    (the default) plays like someone who knows the game: runs from whatever is close,
##           sweeps up candy, sprints out of trouble, goes to the altar after `farm seconds`,
##           stays in the ring and hops the shockwaves, and picks a card at random
##   circle  the old one: runs in a small circle and always takes the first card. Close to the
##           worst a player can do while still moving
##
## It logs its state every 30 s and ends on death, after `STAGES` stages, or at the time limit.
##
##     godot --headless --fixed-fps 60 --path . -s res://tests/bot_run.gd -- [hero] [farm seconds] [kite|circle] [seed]

const Enemy := preload("res://scripts/enemy.gd")
const Pickup := preload("res://scripts/pickup.gd")
const Hazard := preload("res://scripts/hazard.gd")

const STAGES := 3
const TIME_LIMIT := 1500.0

var main: Node3D
var hero := "joe"
var farm_time := 150.0
var style := "kite"
var low_hp := 1.0e9
var hits := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		hero = args[0]
	if args.size() > 1:
		farm_time = float(args[1])
	if args.size() > 2:
		style = args[2]
	if args.size() > 3:
		seed(int(args[3]))
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
	var stage_began := 0.0
	var stage_seen := 0
	player.hurt_taken.connect(func(_amount: float) -> void: hits += 1)
	Input.action_press("move_forward")
	print("bot: %s, %s, farms %d s a stage" % [hero, style, int(farm_time)])
	while director.time < TIME_LIMIT:
		await physics_frame
		if main.state == "upgrade" and not main.menus._cards.is_empty():
			var cards: Array = main.menus._cards
			cards[0 if style == "circle" else randi() % cards.size()].pressed.emit()
			continue
		if main.state == "dead" or player.dead:
			var boss_left := "no boss"
			if director.boss:
				boss_left = "boss at %d%%" % int(director.boss.hp / director.boss.max_hp * 100.0)
			print("DIED at %s, stage %d (%s into it), level %d, %d kills, %s, altar %d%%, score %d" % [_clock(director.time), main.stage_index + 1,
				_clock(director.time - stage_began), player.level, player.kills, boss_left, int(main.altar.charge * 100.0), main.run_score()])
			break
		if main.stage_index != stage_seen:
			print("stage %d cleared in %s (run %s), level %d, %d kills, lowest health %d, hit %d times" % [stage_seen + 1,
				_clock(director.time - stage_began), _clock(director.time), player.level, player.kills, low_hp, hits])
			stage_seen = main.stage_index
			stage_began = director.time
			low_hp = 1.0e9
			hits = 0
		if main.stage_index >= STAGES:
			print("CLEARED %d stages at %s, level %d, %d kills, score %d" % [STAGES, _clock(director.time), player.level, player.kills, main.run_score()])
			break
		low_hp = minf(low_hp, player.hp)
		var altar: Node3D = main.altar
		var to_altar := altar.global_position - player.global_position
		to_altar.y = 0.0
		if director.boss and boss_began < 0.0:
			boss_began = director.time
		if altar.state == "portal" and boss_began >= 0.0:
			print("boss down and altar charged %d s after the summons" % int(director.time - boss_began))
			boss_began = -1.0
		var farming: bool = altar.state == "idle" and director.stage_time < farm_time
		if altar.prompt(player.global_position) != "" and not farming:
			altar.interact()
		if style == "circle":
			if director.boss != null or farming:
				main.cam.rotation.y += 0.6 / 60.0
			else:
				main.cam.rotation.y = atan2(-to_altar.x, -to_altar.z)
			if player.is_on_floor() and (player.is_on_wall() or (director.boss and int(director.time * 60.0) % 50 == 0)):
				Input.action_press("jump")
			else:
				Input.action_release("jump")
		else:
			_kite(player, altar, to_altar, farming)
		if director.time >= next_log:
			next_log += 30.0
			var names: Array = player.weapons.map(func(weapon: RefCounted) -> String: return "%s %d" % [weapon.id, weapon.level])
			print("%s  stage %d  lv %d  hp %d/%d  kills %d  alive %d  diff %.1f  altar %d%%  %s  +%d passives" % [_clock(director.time), main.stage_index + 1,
				player.level, player.hp, player.max_hp(), player.kills, director.alive(), director.difficulty(), int(altar.charge * 100.0), ", ".join(names), player.passives.size()])
	quit()


## Steers by adding up pulls: away from enemies that are too close, toward candy, toward the
## horde when nothing is in reach of its weapons, and toward the place it wants to be
## (wandering while farming, the altar after, inside the ring in a fight).
func _kite(player: CharacterBody3D, altar: Node3D, to_altar: Vector3, farming: bool) -> void:
	var here := player.global_position
	var pull := Vector3.ZERO
	var nearest := 1.0e9
	var nearest_dir := Vector3.ZERO
	# fighters with short weapons have to stand closer
	var keep := 3.0 if player.weapons[0].id in ["claw", "cursed_sword"] and player.weapons.size() < 3 else 5.0
	var crowd := 0
	for enemy: Node3D in Enemy.all:
		var away: Vector3 = here - enemy.global_position
		away.y = 0.0
		var body: float = enemy.radius
		var distance := maxf(away.length() - body, 0.3)
		if distance < nearest:
			nearest = distance
			nearest_dir = -away.normalized()
		var reach := maxf(keep + 2.0, 6.0) if enemy.is_boss else keep
		if distance < reach * 2.0:
			crowd += 1
		if distance < reach:
			pull += away.normalized() * (reach / distance - 1.0) * (4.0 if enemy.is_boss else 2.0)
	# step out of the way of boss shots that are coming this way
	for hazard: Node3D in get_nodes_in_group(Hazard.GROUP):
		if hazard.mode != "ball":
			continue
		var flight: Vector3 = hazard.velocity
		var gap: Vector3 = here + Vector3.UP - hazard.global_position
		var ahead := gap.dot(flight.normalized())
		if ahead < 0.0 or ahead > 14.0:
			continue
		var side := gap - flight.normalized() * ahead
		side.y = 0.0
		if side.length() < 2.4:
			var step := side.normalized() if side.length() > 0.1 else flight.normalized().rotated(Vector3.UP, PI * 0.5)
			pull += step * 7.0
	# low on health: keep a wider berth
	if player.hp < player.max_hp() * 0.35:
		pull *= 2.0
	var candy := Vector3.ZERO
	var candy_distance := 40.0
	for pickup: Node3D in get_nodes_in_group(Pickup.GROUP):
		var to: Vector3 = pickup.global_position - here
		to.y = 0.0
		if to.length() < candy_distance:
			candy_distance = to.length()
			candy = to.normalized()
	pull += candy * 2.0
	if candy == Vector3.ZERO and nearest > keep * 1.5 and nearest < 60.0:
		pull += nearest_dir * 1.5  # nothing to pick up: go and find the fight
	if altar.state == "boss":
		# hold the ring: drift back toward the altar, harder the nearer the edge
		var ring: float = altar.CHARGE_RADIUS
		var out := to_altar.length() / ring
		pull += to_altar.normalized() * maxf(out - 0.5, 0.0) * 12.0
		# and keep circling so nothing catches up
		pull += to_altar.normalized().rotated(Vector3.UP, PI * 0.5) * 1.0
	elif not farming:
		pull += to_altar.normalized() * 3.0
	else:
		# wander: a slow circle around the middle of the map keeps new ground coming
		var spot := Vector3(sin(main.director.time * 0.05), 0.0, cos(main.director.time * 0.05)) * 60.0
		pull += (spot - here).normalized() * 0.5
	if pull.length() > 0.01:
		main.cam.rotation.y = atan2(-pull.x, -pull.z)
	if nearest < 2.5 or crowd > 12:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	# hop walls, and shockwaves as they arrive
	var jump := player.is_on_floor() and player.is_on_wall()
	for hazard: Node3D in get_nodes_in_group(Hazard.GROUP):
		if hazard.mode == "ring":
			var flat := Vector2(here.x - hazard.global_position.x, here.z - hazard.global_position.z).length()
			if absf(flat - hazard.ring_radius) < 2.6 and player.is_on_floor():
				jump = true
	if jump:
		Input.action_press("jump")
	else:
		Input.action_release("jump")


func _clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
