extends Node
## Co-op traffic for a run, in the manner of 8 Bit Evil Returns V2. The host simulates
## everything; guests move their own hero and draw the rest from snapshots.
##
## Host -> everyone, 20 times a second:
##   S  run clock, stage, altar, boss health, and every hero (place, health, level...)
##   E  enemies, in one or more chunks
##   T  things: shots, pools, boss shots and shockwaves, pickups, in one or more chunks
## Guest -> host, 20 times a second:
##   I  where their hero is, which way it faces, what it is doing
## Either way, small JSON messages (J):
##   host:  stage, inv, offer, banner, fx, over, old
##   guest: hello, pick, interact
## Positions are 16-bit, 2 cm steps.

const Db := preload("res://scripts/db.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Shot := preload("res://scripts/shot.gd")
const Hazard := preload("res://scripts/hazard.gd")
const Pickup := preload("res://scripts/pickup.gd")
const AnimSprite := preload("res://scripts/anim_sprite.gd")
const Fx := preload("res://scripts/fx.gd")

const K_SNAP := 83    # S
const K_ENEMY := 69   # E
const K_THINGS := 84  # T
const K_INPUT := 73   # I
const K_JSON := 74    # J
const SEND_EVERY := 1.0 / 20.0
## The server refuses packets over 8 KB.
const CHUNK_ROWS := 500
const MAX_PICKUPS := 300
const POSITION_STEP := 50.0
const ANIMS: Array[String] = ["idle", "run", "jump", "fall"]
const ALTAR_STATES: Array[String] = ["idle", "boss", "portal"]
## Bump when the packets change, so a player on an old page is told to reload.
const PROTOCOL := 2

const BILLBOARD := 0
const POOL := 1
const BOLT := 2
const BALL := 3
const RING := 4
const LOOT := 5

var main: Node
var net: Node

var _clock := 0.0
var _seq := 0
var _sheets: Array = []
var _kinds: Array = []
var _bosses: Array = []
# host
var _stage := {}
var _offers := {}        # seat -> the upgrade ids on offer
var _inv_sent := {}      # seat -> inventory_rev last sent
# guest
var _hello := 0.0
var _got_stage := false
var _enemies := {}       # id -> view node
var _things := {}
var _seen := {}          # packet kind -> ids seen in the snapshot being read


func _ready() -> void:
	_sheets = Db.SHEETS.keys()
	_sheets.sort()
	_kinds = Db.ENEMIES.keys()
	_kinds.sort()
	_bosses = Db.BOSSES.keys()
	_bosses.sort()
	net.packet.connect(_on_packet)
	if net.is_host:
		net.back.connect(func(seat: int) -> void: _welcome(seat))


func _process(delta: float) -> void:
	_clock += delta
	if net.is_host:
		_serve_offers()
		if _clock >= SEND_EVERY:
			_clock = fmod(_clock, SEND_EVERY)
			_send_snapshot()
		return
	if _clock >= SEND_EVERY:
		_clock = fmod(_clock, SEND_EVERY)
		_send_input()
	if not _got_stage:
		# resent until the host answers: its game may not have been up for the first one
		_hello -= delta
		if _hello <= 0.0:
			_hello = 1.0
			net.send_json(0, {"t": "hello", "proto": PROTOCOL})
	_glide(delta)


# ---------------------------------------------------------------- host

## Tells everyone which stage to build. Guests generate the same level from the seed.
func send_stage(index: int, seed_value: int) -> void:
	_stage = {"t": "stage", "index": index, "seed": seed_value}
	net.send_json(net.BROADCAST, _stage)


func send_banner(text: String, sub: String) -> void:
	net.send_json(net.BROADCAST, {"t": "banner", "text": text, "sub": sub})


func send_over(lines: Array) -> void:
	net.send_json(net.BROADCAST, {"t": "over", "lines": lines})


## Everything a guest needs after joining late or reconnecting.
func _welcome(seat: int) -> void:
	if not _stage.is_empty():
		net.send_json(seat, _stage)
	_inv_sent.erase(seat)
	_offers.erase(seat)


## Sends each guest their build when it changes, and their upgrade cards when they are owed.
func _serve_offers() -> void:
	for seat: int in main.heroes:
		var hero: Node3D = main.heroes[seat]
		if not hero.driven:
			continue
		if _inv_sent.get(seat, -1) != hero.inventory_rev:
			_inv_sent[seat] = hero.inventory_rev
			net.send_json(seat, {"t": "inv", "inv": hero.inventory()})
		if not _offers.has(seat) and not hero.dead and (hero.chests_owed > 0 or hero.levels_owed > 0):
			_offers[seat] = hero.upgrade_options(3)
			net.send_json(seat, {"t": "offer", "heading": "TREASURE" if hero.chests_owed > 0 else "LEVEL UP", "ids": _offers[seat]})


func _send_snapshot() -> void:
	_seq = (_seq + 1) & 0xFFFF
	var out := StreamPeerBuffer.new()
	var director: Node = main.director
	out.put_u16(_seq)
	out.put_float(director.time)
	out.put_u8(main.stage_index)
	out.put_u8(ALTAR_STATES.find(main.altar.state) if main.altar else 255)
	out.put_u8(int(main.altar.charge * 100.0) if main.altar else 0)
	var boss: Node3D = director.boss
	out.put_u8(1 if boss else 0)
	if boss:
		out.put_u8(_bosses.find(boss.boss_id))
		out.put_float(boss.hp)
		out.put_float(boss.max_hp)
	out.put_u8(main.heroes.size())
	for seat: int in main.heroes:
		var hero: Node3D = main.heroes[seat]
		out.put_u8(seat)
		_put_position(out, hero.global_position)
		out.put_16(int(wrapf(hero.facing(), -PI, PI) * 1000.0))
		out.put_u8(ANIMS.find(hero.net_anim if hero.driven else hero.anim_name()))
		out.put_u8(1 if hero.dead else 0)
		out.put_float(hero.hp)
		out.put_u16(hero.level)
		out.put_float(hero.xp)
		out.put_u32(hero.kills)
	net.send(net.BROADCAST, K_SNAP, out.data_array)

	var rows: Array = []
	for enemy: Node3D in Enemy.all:
		var row := StreamPeerBuffer.new()
		row.put_u16(enemy.net_id)
		row.put_u8(200 + _bosses.find(enemy.boss_id) if enemy.is_boss else _kinds.find(enemy.kind))
		row.put_u8((1 if enemy.elite else 0) | (2 if enemy.flashing() else 0))
		_put_position(row, enemy.global_position)
		rows.append(row.data_array)
	_send_rows(K_ENEMY, rows)

	rows = []
	for shot: Node3D in get_tree().get_nodes_in_group(Shot.GROUP):
		if shot.net_sheet != "":
			var type := POOL if shot.mode == "pool" else (BOLT if shot.net_laid else BILLBOARD)
			rows.append(_thing(shot.net_id, type, shot.net_sheet, shot.global_position, shot.net_size))
	for hazard: Node3D in get_tree().get_nodes_in_group(Hazard.GROUP):
		if hazard.mode == "ring":
			rows.append(_thing(hazard.net_id, RING, "", hazard.global_position, hazard.ring_radius * 0.5))
		else:
			rows.append(_thing(hazard.net_id, BALL, hazard.sheet, hazard.global_position, 1.3))
	var loot := get_tree().get_nodes_in_group(Pickup.GROUP)
	for i in mini(loot.size(), MAX_PICKUPS):
		rows.append(_thing(loot[i].net_id, LOOT, loot[i].sheet, loot[i].global_position, 1.0))
	_send_rows(K_THINGS, rows)

	if not Fx.events.is_empty():
		var events := []
		for event: Array in Fx.events:
			var at: Vector3 = event[1]
			var packed: Array = [event[0], snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
			for i in range(2, event.size()):
				packed.append(event[i].to_html() if event[i] is Color else event[i])
			events.append(packed)
		Fx.events.clear()
		net.send_json(net.BROADCAST, {"t": "fx", "e": events})


func _thing(id: int, type: int, sheet: String, at: Vector3, size: float) -> PackedByteArray:
	var row := StreamPeerBuffer.new()
	row.put_u16(id)
	row.put_u8(type)
	row.put_u8(maxi(_sheets.find(sheet), 0))
	_put_position(row, at)
	row.put_u8(clampi(int(size * 10.0), 0, 255))
	return row.data_array


## Sends rows as packets of [seq, chunk, chunks, count, rows...]. Always sends at least one,
## so guests learn when there is nothing left.
func _send_rows(kind: int, rows: Array) -> void:
	var chunks := maxi(ceili(rows.size() / float(CHUNK_ROWS)), 1)
	for chunk in chunks:
		var out := StreamPeerBuffer.new()
		var first := chunk * CHUNK_ROWS
		var count := mini(rows.size() - first, CHUNK_ROWS)
		out.put_u16(_seq)
		out.put_u8(chunk)
		out.put_u8(chunks)
		out.put_u16(count)
		for i in count:
			out.put_data(rows[first + i])
		net.send(net.BROADCAST, kind, out.data_array)


func _put_position(out: StreamPeerBuffer, at: Vector3) -> void:
	out.put_16(clampi(int(round(at.x * POSITION_STEP)), -32768, 32767))
	out.put_16(clampi(int(round(at.y * POSITION_STEP)), -32768, 32767))
	out.put_16(clampi(int(round(at.z * POSITION_STEP)), -32768, 32767))


func _host_packet(from: int, kind: int, data: PackedByteArray) -> void:
	var hero: Node3D = main.heroes.get(from)
	if hero == null or not hero.driven:
		return
	if kind == K_INPUT and data.size() >= 9:
		var input := StreamPeerBuffer.new()
		input.data_array = data
		hero.net_position = _get_position(input)
		hero.net_facing = input.get_16() / 1000.0
		hero.net_anim = ANIMS[clampi(input.get_u8(), 0, ANIMS.size() - 1)]
	elif kind == K_JSON:
		var message := _json(data)
		match str(message.get("t")):
			"hello":
				if int(message.get("proto", 0)) != PROTOCOL:
					net.send_json(from, {"t": "old"})
				else:
					_welcome(from)
			"pick":
				var id := str(message.get("id"))
				if _offers.has(from) and id in _offers[from]:
					_offers.erase(from)
					hero.apply_upgrade(id)
					if hero.chests_owed > 0:
						hero.chests_owed -= 1
					else:
						hero.levels_owed -= 1
			"interact":
				main.interact_as(hero)


# ---------------------------------------------------------------- guest

func send_pick(id: String) -> void:
	net.send_json(0, {"t": "pick", "id": id})


func send_interact() -> void:
	net.send_json(0, {"t": "interact"})


## How many enemies the guest is drawing.
func enemy_count() -> int:
	return _enemies.size()


func _send_input() -> void:
	var hero: Node3D = main.player
	var out := StreamPeerBuffer.new()
	_put_position(out, hero.global_position)
	out.put_16(int(wrapf(hero.facing(), -PI, PI) * 1000.0))
	out.put_u8(ANIMS.find(hero.anim_name()))
	net.send(0, K_INPUT, out.data_array)


func _on_packet(from: int, kind: int, data: PackedByteArray) -> void:
	if net.is_host:
		_host_packet(from, kind, data)
		return
	var input := StreamPeerBuffer.new()
	input.data_array = data
	match kind:
		K_JSON:
			_guest_json(_json(data))
		K_SNAP:
			if _got_stage:
				_read_snapshot(input)
		K_ENEMY:
			if _got_stage:
				_read_rows(input, kind, _enemies)
		K_THINGS:
			if _got_stage:
				_read_rows(input, kind, _things)


func _guest_json(message: Dictionary) -> void:
	match str(message.get("t")):
		"stage":
			_got_stage = true
			_enemies.clear()
			_things.clear()
			main.guest_stage(int(message["index"]), int(message["seed"]))
		"inv":
			main.player.set_inventory(message["inv"])
		"offer":
			var ids: Array[String] = []
			ids.assign(message["ids"])
			main.show_offer(str(message["heading"]), ids)
		"banner":
			main.hud.banner(str(message["text"]), str(message["sub"]))
		"over":
			main.game_over(message["lines"])
		"old":
			main.leave_coop("This page is out of date. Reload it to play co-op.")
		"fx":
			for event: Array in message["e"]:
				var at := Vector3(event[1], event[2], event[3])
				if event[0] == "n":
					Fx.number(main.world, at, event[4], Color(str(event[5])))
				else:
					Fx.burst(main.world, at, event[4], event[5], Color(str(event[6])), event[7])


func _read_snapshot(input: StreamPeerBuffer) -> void:
	input.get_u16()
	var director: Node = main.director
	director.time = input.get_float()
	director.stage_index = input.get_u8()
	var altar_state := input.get_u8()
	var altar_charge := input.get_u8() / 100.0
	if main.altar and altar_state < ALTAR_STATES.size():
		main.altar.set_state(ALTAR_STATES[altar_state])
		main.altar.charge = altar_charge
	main.boss_state = {}
	if input.get_u8() == 1:
		var boss: Dictionary = Db.BOSSES[_bosses[input.get_u8()]]
		var hp := input.get_float()
		var max_hp := input.get_float()
		main.boss_state = {"title": boss["name"], "hp": hp, "max_hp": max_hp, "enraged": hp < max_hp * 0.5}
	for i in input.get_u8():
		var seat := input.get_u8()
		var at := _get_position(input)
		var facing := input.get_16() / 1000.0
		var anim := ANIMS[clampi(input.get_u8(), 0, ANIMS.size() - 1)]
		var dead := input.get_u8() == 1
		var hp := input.get_float()
		var level := input.get_u16()
		var xp := input.get_float()
		var kills := input.get_u32()
		var hero: Node3D = main.heroes.get(seat)
		if hero == null:
			continue
		if hero.driven:
			hero.net_position = at
			hero.net_facing = facing
			hero.net_anim = anim
		elif hp < hero.hp - 0.5:
			hero.hurt_taken.emit(hero.hp - hp)
		hero.hp = hp
		hero.level = level
		hero.xp = xp
		hero.kills = kills
		hero.dead = dead
		hero.model.visible = not dead


## Reads a chunk of enemy or thing rows into `views`: makes the new ones, moves the rest,
## and once the snapshot's last chunk is in, removes whatever was not in it.
func _read_rows(input: StreamPeerBuffer, kind: int, views: Dictionary) -> void:
	input.get_u16()
	var chunk := input.get_u8()
	var chunks := input.get_u8()
	if chunk == 0:
		_seen[kind] = {}
	var seen: Dictionary = _seen.get(kind, {})
	for i in input.get_u16():
		var id := input.get_u16()
		var a := input.get_u8()
		var b := input.get_u8()
		var at := _get_position(input)
		var size := 0.0 if kind == K_ENEMY else input.get_u8() / 10.0
		seen[id] = true
		var view: Node3D = views.get(id)
		if view == null:
			view = _enemy_view(a, b) if kind == K_ENEMY else _thing_view(a, b, size)
			view.position = at
			view.set_meta("to", at)
			main.world.add_child(view)
			views[id] = view
		elif not is_instance_valid(view):
			continue
		if kind == K_ENEMY:
			view.get_child(0).modulate = Color(1.0, 0.35, 0.35) if b & 2 else view.get_meta("tint")
		elif a == RING:
			var torus: TorusMesh = view.get_child(0).mesh
			torus.inner_radius = maxf(size * 2.0 - 0.35, 0.05)
			torus.outer_radius = size * 2.0 + 0.35
		view.set_meta("to", at)
	if chunk == chunks - 1:
		for id: int in views.keys():
			if not seen.has(id):
				if is_instance_valid(views[id]):
					views[id].queue_free()
				views.erase(id)


func _enemy_view(kind: int, flags: int) -> Node3D:
	var def: Dictionary
	if kind >= 200:
		var boss: Dictionary = Db.BOSSES[_bosses[kind - 200]]
		def = Db.ENEMIES[boss["enemy"]].duplicate()
		def.merge(boss, true)
	else:
		def = Db.ENEMIES[_kinds[kind]]
	var elite := flags & 1 == 1
	var view := Node3D.new()
	var sprite := AnimSprite.make(def["sheet"], def["height"] * (1.3 if elite else 1.0), true)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.clock = randf() * 10.0
	view.set_meta("tint", Enemy.ELITE_TINT if elite else Color.WHITE)
	sprite.modulate = view.get_meta("tint")
	view.add_child(sprite)
	view.set_meta("enemy", true)
	return view


func _thing_view(type: int, sheet_index: int, size: float) -> Node3D:
	var sheet: String = _sheets[sheet_index]
	var view := Node3D.new()
	view.set_meta("type", type)
	match type:
		POOL:
			view.add_child(Shot.pool_sprite(sheet, size))
		BOLT:
			view.add_child(AnimSprite.make(sheet, size))
			Shot.lay_flat(view)
		BALL:
			view.add_child(Hazard.ball_sprite(sheet))
		RING:
			view.add_child(Hazard.ring_visual())
		LOOT:
			view.add_child(Pickup.make_sprite(sheet))
		_:
			view.add_child(AnimSprite.make(sheet, size))
	return view


## Moves every view smoothly toward where the last snapshot put it.
func _glide(delta: float) -> void:
	var blend := 1.0 - exp(-16.0 * delta)
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	for views: Dictionary in [_enemies, _things]:
		for id: int in views:
			var view: Node3D = views[id]
			if not is_instance_valid(view):
				continue
			var to: Vector3 = view.get_meta("to")
			var step := (to - view.position) * blend
			if view.has_meta("enemy"):
				if cam and Vector2(step.x, step.z).length() > 0.002:
					view.get_child(0).flip_h = step.dot(cam.global_basis.x) < 0.0
			elif view.get_meta("type") == BOLT and step.length() > 0.01:
				view.look_at(view.position + step, Vector3.UP if absf(step.normalized().y) < 0.95 else Vector3.RIGHT)
			view.position += step


func _get_position(input: StreamPeerBuffer) -> Vector3:
	var x := input.get_16() / POSITION_STEP
	var y := input.get_16() / POSITION_STEP
	var z := input.get_16() / POSITION_STEP
	return Vector3(x, y, z)


func _json(data: PackedByteArray) -> Dictionary:
	var message: Variant = JSON.parse_string(data.get_string_from_utf8())
	return message if message is Dictionary else {}
