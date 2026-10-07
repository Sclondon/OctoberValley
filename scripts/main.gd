extends Node3D
## October Valley. The whole scene is built here in code, and this script runs the loop:
##
##   title -> pick a hero -> stage: fight, level up, find the altar, summon and beat the boss,
##   take the portal -> next stage (harder; after the last one the stages repeat) -> ... -> death
##
## The local hero, camera, director, HUD and menus live for the whole session. Each stage is
## a fresh `world` node holding the level, the altar, the enemies, shots and loot.
##
## Co-op (up to four, through a room on the Scareathon server): the player who made the room
## is the host and runs all of the above; guests move their own hero and draw what the host
## sends (see net.gd and netsync.gd). Nothing pauses in co-op, the fallen come back on the
## next stage, and the run ends when everyone is down.

const Controls := preload("res://scripts/controls.gd")
const Db := preload("res://scripts/db.gd")
const Stage := preload("res://scripts/stage.gd")
const TestLevel := preload("res://scripts/test_level.gd")
const Altar := preload("res://scripts/altar.gd")
const Player := preload("res://scripts/player.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const Director := preload("res://scripts/director.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Hud := preload("res://scripts/hud.gd")
const Menus := preload("res://scripts/menus.gd")
const Net := preload("res://scripts/net.gd")
const NetSync := preload("res://scripts/netsync.gd")
const Team := preload("res://scripts/team.gd")
const Fx := preload("res://scripts/fx.gd")

## Where to begin: "title", "run" (straight into stage 1) or "test" (the test yard).
@export var start_mode := "title"
## The hero for "run" and "test", and the one highlighted on the title.
@export var hero := "joe"
## Tests turn this off to get an empty level.
@export var spawn_enemies := true

var world: Node3D
var level: Node3D
var altar: Altar
## This machine's hero.
var player: Player
## seat -> hero. Only {0: player} unless in co-op.
var heroes := {}
var cam: CameraRig
var director: Director
var hud: Hud
var menus: Menus
var net: Net
## Only while a co-op game is running.
var sync: NetSync

## title, lobby, waiting (a guest before the host's stage arrives), playing, upgrade, paused or dead
var state := "title"
var in_test := false
var stage_index := 0
var stage_title := ""
## Guests: the boss as the host last described it ({} = none).
var boss_state := {}


func _ready() -> void:
	# main keeps running while paused so it can unpause; everything else stops
	process_mode = Node.PROCESS_MODE_ALWAYS
	Controls.setup()

	player = Player.new()
	player.hero = hero
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.died.connect(_on_hero_died.bind(player))
	heroes = {0: player}

	cam = CameraRig.new()
	cam.target = player
	cam.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(cam)
	player.camera = cam

	director = Director.new()
	director.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(director)
	director.enemy_killed.connect(_on_enemy_killed)
	director.boss_spawned.connect(func(boss: Node) -> void: _banner(boss.title, "Jump the shockwaves"))
	director.boss_defeated.connect(_on_boss_defeated)

	hud = Hud.new()
	hud.main = self
	hud.player = player
	hud.director = director
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud)

	net = Net.new()
	add_child(net)
	net.room_changed.connect(_on_room_changed)
	net.started.connect(_start_coop)
	net.failed.connect(func(message: String) -> void: menus.coop(message))
	net.closed.connect(func(reason: String) -> void:
		leave_coop("The host left the game." if reason == "host" else "The co-op game ended."))
	net.left.connect(_on_player_left)

	menus = Menus.new()
	add_child(menus)
	menus.hero_focused.connect(_on_hero_focused)
	menus.hero_chosen.connect(start_run)
	menus.test_chosen.connect(start_test)
	menus.upgrade_chosen.connect(_on_upgrade_chosen)
	menus.resumed.connect(_resume)
	menus.retried.connect(_retry)
	menus.quit_to_title.connect(leave_coop)
	menus.coop_opened.connect(func() -> void: menus.coop())
	menus.coop_created.connect(func() -> void:
		menus.notice("Making a room...")
		net.create(hero))
	menus.coop_joined.connect(func(code: String) -> void:
		menus.notice("Joining room %s..." % code)
		net.join(code, hero))
	menus.coop_hero_picked.connect(func(id: String) -> void: net.pick_hero(id))
	menus.coop_started.connect(func() -> void: net.start_game())

	match start_mode:
		"run":
			start_run(hero)
		"test":
			start_test(hero)
		_:
			show_title()


func coop() -> bool:
	return sync != null


## In co-op and not the one running the fight.
func is_guest() -> bool:
	return coop() and not net.is_host


## The stage boss for the HUD: {title, hp, max_hp, enraged}, or {} when there is none.
func boss_info() -> Dictionary:
	if is_guest():
		return boss_state
	var boss := director.boss
	if boss == null:
		return {}
	return {"title": boss.title, "hp": boss.hp, "max_hp": boss.max_hp, "enraged": boss.enraged()}


func enemy_count() -> int:
	return sync.enemy_count() if is_guest() else Enemy.all.size()


# ---------------------------------------------------------------- the loop

## The title screen, with stage 1 and the chosen hero turning slowly behind it.
func show_title(note := "") -> void:
	state = "title"
	in_test = false
	get_tree().paused = false
	_build(0, false)
	player.reset_run(hero)
	player.active = false
	director.enabled = false
	hud.visible = false
	cam.target = player
	cam.orbit = true
	cam.distance = 4.5
	cam.pitch = -0.12
	cam.grab_on_click = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.title(hero, note)


func start_run(hero_name: String) -> void:
	hero = hero_name
	player.hero = hero
	in_test = false
	director.reset()
	_build(0, false)
	_begin_play()
	_banner("STAGE 1", stage_title)


func _retry() -> void:
	if in_test:
		start_test(hero)
	else:
		start_run(hero)


## The test yard: every enemy type, no altar, no boss.
func start_test(hero_name: String) -> void:
	hero = hero_name
	player.hero = hero
	in_test = true
	director.reset()
	_build(0, true)
	_begin_play()


func _begin_play() -> void:
	for each: Player in heroes.values():
		each.reset_run(each.hero)
		each.active = true
	director.enabled = spawn_enemies and not is_guest()
	hud.visible = true
	cam.target = player
	cam.orbit = false
	cam.distance = 7.0
	cam.pitch = -0.3
	cam.rotation.y = 0.0
	_resume()


## Throws the old stage away and builds stage `index`. The heroes keep everything.
func _build(index: int, test_yard: bool, seed_value := randi()) -> void:
	if world:
		remove_child(world)
		world.queue_free()
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	stage_index = index
	altar = null
	boss_state = {}
	var roster: Array = Director.DEFAULT_ROSTER
	if test_yard:
		level = TestLevel.new()
		stage_title = "The Test Yard"
	else:
		var theme: Dictionary = Db.STAGES[index % Db.STAGES.size()]
		var stage := Stage.new()
		stage.theme = theme
		stage.seed_value = seed_value
		level = stage
		roster = theme["roster"]
		var lap := index / Db.STAGES.size()
		stage_title = theme["name"] + ("" if lap == 0 else "  (LOOP %d)" % (lap + 1))
	world.add_child(level)
	if level.altar_position != Vector3.INF:
		altar = Altar.new()
		altar.position = level.altar_position
		world.add_child(altar)
		altar.summoned.connect(_on_altar_summoned)
		altar.entered.connect(_on_portal_entered)
	for seat: int in heroes:
		var each: Player = heroes[seat]
		each.world = world
		each.respawn(level.start_position + Vector3(seat * 1.6, 0.0, 0.0))
		if each.dead and each.simulate:
			each.revive()
	director.begin_stage(index, roster, world, level.half_extent)
	if coop() and net.is_host:
		sync.send_stage(index, seed_value)


func _on_altar_summoned() -> void:
	var theme: Dictionary = Db.STAGES[stage_index % Db.STAGES.size()]
	director.summon_boss(theme["boss"], altar.global_position)


func _on_boss_defeated() -> void:
	if altar:
		altar.open_portal()
	_banner("BOSS DEFEATED", "Enter the portal")


func _on_portal_entered() -> void:
	_build(stage_index + 1, false)
	cam.rotation.y = 0.0
	_banner("STAGE %d" % (stage_index + 1), stage_title)


func _on_enemy_killed(_enemy: Node) -> void:
	for each: Player in heroes.values():
		each.kills += 1


## A hero uses the altar or the portal if they are standing at it (guests ask the host).
func interact_as(who: Player) -> void:
	if altar and not who.dead and altar.prompt(who.global_position) != "":
		altar.interact()


## A banner on this screen, and on every guest's.
func _banner(text: String, sub := "") -> void:
	hud.banner(text, sub)
	if coop() and net.is_host:
		sync.send_banner(text, sub)


func _on_hero_died(who: Player) -> void:
	if coop() and not Team.alive().is_empty():
		return  # the others fight on; this hero is back on the next stage
	if who != player and not coop():
		return
	var seconds := int(director.time)
	var lines := [
		"Reached stage %d: %s" % [stage_index + 1, stage_title],
		"Survived %d:%02d   %d kills" % [seconds / 60, seconds % 60, player.kills],
	]
	if coop():
		sync.send_over(lines)
	else:
		lines.append("%s got to level %d" % [Db.HEROES[hero]["name"], player.level])
	game_over(lines)


## Ends the run and shows why. Guests are sent here by the host.
func game_over(lines: Array) -> void:
	if state == "dead":
		return
	state = "dead"
	for each: Player in heroes.values():
		each.active = false
	await get_tree().create_timer(1.2).timeout
	if state != "dead":
		return
	_show_menu()
	menus.game_over(lines, not coop())


# ---------------------------------------------------------------- co-op

func _on_hero_focused(id: String) -> void:
	hero = id
	player.set_hero(id)


func _on_room_changed() -> void:
	if net.in_game:
		return
	state = "lobby"
	for entry: Dictionary in net.players:
		if int(entry["slot"]) == net.slot and Db.HEROES.has(str(entry["hero"])) and str(entry["hero"]) != hero:
			_on_hero_focused(str(entry["hero"]))
	menus.lobby(net.code, net.players, net.slot, net.is_host)


## The room's leader pressed START. `players` is [{slot, name, hero}].
func _start_coop(players: Array) -> void:
	in_test = false
	sync = NetSync.new()
	sync.main = self
	sync.net = net
	heroes = {}
	for entry: Dictionary in players:
		var seat := int(entry["slot"])
		var who := player
		if seat != net.slot:
			who = Player.new()
			who.driven = true
			who.process_mode = Node.PROCESS_MODE_PAUSABLE
			add_child(who)
			who.died.connect(_on_hero_died.bind(who))
			_name_tag(who, "P%d" % (seat + 1))
		who.hero = str(entry["hero"]) if Db.HEROES.has(str(entry["hero"])) else "joe"
		who.seat = seat
		who.simulate = net.is_host
		who.camera = cam if who == player else null
		heroes[seat] = who
	hero = player.hero
	add_child(sync)
	director.reset()
	if net.is_host:
		Fx.record = true
		_build(0, false)
		_begin_play()
		_banner("STAGE 1", stage_title)
	else:
		state = "waiting"
		menus.notice("Waiting for the host...")


## Guests: the host says which stage to build.
func guest_stage(index: int, seed_value: int) -> void:
	var first := state == "waiting"
	_build(index, false, seed_value)
	if first:
		_begin_play()
	cam.rotation.y = 0.0
	if state == "upgrade":
		_resume()


## Guests: the host offers upgrade cards.
func show_offer(heading: String, ids: Array[String]) -> void:
	if state != "playing":
		return
	state = "upgrade"
	_show_menu()
	menus.upgrades(heading, ids, player)


func _on_player_left(seat: int) -> void:
	if not coop() or not heroes.has(seat) or heroes[seat] == player:
		return
	heroes[seat].queue_free()
	heroes.erase(seat)
	if net.is_host and state == "playing" and Team.alive().is_empty():
		_on_hero_died(player)


## Out of the room (if in one) and back to the title. Also the menus' way back to the title.
func leave_coop(note := "") -> void:
	if net.active():
		net.leave()
	if sync:
		sync.queue_free()
		sync = null
	Fx.record = false
	Fx.events.clear()
	for seat: int in heroes:
		if heroes[seat] != player:
			heroes[seat].queue_free()
	heroes = {0: player}
	player.seat = 0
	player.driven = false
	player.simulate = true
	show_title(note)


func _name_tag(who: Player, text: String) -> void:
	var tag := Label3D.new()
	tag.text = text
	tag.font = Hud.FONT
	tag.font_size = 48
	tag.outline_size = 12
	tag.pixel_size = 0.008
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tag.modulate = Color("ffd9a0")
	tag.position.y = 2.3
	who.add_child(tag)


# ---------------------------------------------------------------- menus and pausing

func _process(_delta: float) -> void:
	if coop():
		# a fallen hero watches a teammate until the next stage
		var watch: Node3D = player
		if player.dead and not Team.alive().is_empty():
			watch = Team.alive()[0]
		cam.target = watch
	if state == "playing" and not is_guest() and not player.dead and (player.levels_owed > 0 or player.chests_owed > 0):
		state = "upgrade"
		_show_menu()
		var heading := "TREASURE" if player.chests_owed > 0 else "LEVEL UP"
		menus.upgrades(heading, player.upgrade_options(3), player)


func _on_upgrade_chosen(id: String) -> void:
	if state != "upgrade":
		return
	if is_guest():
		sync.send_pick(id)
	else:
		player.apply_upgrade(id)
		if player.chests_owed > 0:
			player.chests_owed -= 1
		else:
			player.levels_owed -= 1
	_resume()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == "playing":
			state = "paused"
			_show_menu()
			menus.pause(not coop())
		elif state == "paused":
			_resume()
	elif state != "playing":
		return
	elif event.is_action_pressed("interact"):
		if is_guest():
			sync.send_interact()
		else:
			interact_as(player)
	elif event.is_action_pressed("toggle_spawns") and in_test:
		director.enabled = not director.enabled


## Opens a menu over the game. Alone, the game stops behind it; in co-op it cannot.
func _show_menu() -> void:
	get_tree().paused = not coop()
	cam.grab_on_click = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	state = "playing"
	menus.close()
	get_tree().paused = false
	cam.grab_on_click = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
