extends Node
## The co-op connection to the Scareathon server's October Valley rooms
## (/october-valley/ws; see server/routes/octoberValley.js in scareathon-v3). It works the
## same way as 8 Bit Evil Returns V2's: the server keeps the lobby and relays binary packets
## between the host (whoever made the room) and everyone else.
##
## Packets: byte 0 is the seat (the host writes who it's for, 255 = everyone; the server
## rewrites it to who sent it), byte 1 the packet type, then data.
##
## A dropped socket doesn't end anything: the server holds the seat for a while, and this
## reconnects with backoff and takes it back with the token it was given.

const Flags := preload("res://scripts/flags.gd")

signal room_changed            # the lobby's roster or our seat changed
signal started(players: Array)
signal closed(reason: String)  # the host left, the room idled out, or we gave up reconnecting
signal failed(message: String)
signal packet(from: int, kind: int, data: PackedByteArray)
signal left(slot: int)
signal back(slot: int)         # a player who dropped has reconnected

const BROADCAST := 255
const K_JSON := 74  # J
const PATH := "/october-valley/ws"
const DEFAULT_SERVER := "https://scareathon-v3-production.up.railway.app"
const GIVE_UP_AFTER := 95.0  # the server holds a seat for 90 s in a game

var ws: WebSocketPeer
var code := ""
var slot := -1
var token := ""
## This device runs the fight (it made the room).
var is_host := false
## [{slot, name, hero, away}]
var players: Array = []
var in_game := false
var reconnecting := false

var _pending := {}
var _was_open := false
var _retry_in := 0.0
var _backoff := 0.5
var _down_for := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## In a room (lobby or game).
func active() -> bool:
	return slot >= 0


func create(hero: String) -> void:
	_open({"type": "create", "name": "PLAYER", "hero": hero})


func join(room_code: String, hero: String) -> void:
	_open({"type": "join", "code": room_code, "name": "PLAYER", "hero": hero})


func pick_hero(hero: String) -> void:
	_send_text({"type": "pick", "hero": hero})


func start_game() -> void:
	_send_text({"type": "start"})


## Leaving on purpose: the seat is freed for good (and a host leaving closes the room).
func leave() -> void:
	if ws:
		_send_text({"type": "leave"})
		ws.close()
	_reset()


## Host: send to one seat or BROADCAST. Guest: `to` is ignored (it always goes to the host).
func send(to: int, kind: int, data: PackedByteArray) -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN or reconnecting:
		return
	var out := PackedByteArray([to, kind])
	out.append_array(data)
	ws.send(out, WebSocketPeer.WRITE_MODE_BINARY)


## Small game messages as JSON inside a binary packet.
func send_json(to: int, message: Dictionary) -> void:
	send(to, K_JSON, JSON.stringify(message).to_utf8_buffer())


func _url() -> String:
	var base := Flags.value("server", DEFAULT_SERVER).trim_suffix("/")
	return base.replace("https://", "wss://").replace("http://", "ws://") + PATH


func _reset() -> void:
	ws = null
	code = ""
	slot = -1
	token = ""
	is_host = false
	players = []
	in_game = false
	reconnecting = false
	_was_open = false
	_retry_in = 0.0


func _open(first: Dictionary) -> void:
	if ws and not reconnecting:
		leave()
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	_was_open = false
	if ws.connect_to_url(_url()) != OK:
		ws = null
		if reconnecting:
			_schedule_retry()
		else:
			failed.emit("Couldn't reach the server.")
		return
	_pending = first


func _send_text(message: Dictionary) -> void:
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(message))


func _schedule_retry() -> void:
	ws = null
	_retry_in = _backoff
	_backoff = minf(_backoff * 2.0, 5.0)


func _give_up(reason: String) -> void:
	_reset()
	closed.emit(reason)


func _process(delta: float) -> void:
	if reconnecting:
		_down_for += delta
		if _down_for > GIVE_UP_AFTER:
			_give_up("lost")
			return
		if ws == null:
			_retry_in -= delta
			if _retry_in <= 0.0:
				_open({"type": "rejoin", "code": code, "token": token})
			return
	if ws == null:
		return
	ws.poll()
	var state := ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			if not _pending.is_empty():
				_send_text(_pending)
				_pending = {}
		while ws and ws.get_available_packet_count() > 0:
			var data := ws.get_packet()
			if ws.was_string_packet():
				_on_text(data.get_string_from_utf8())
			elif data.size() >= 2:
				packet.emit(data[0], data[1], data.slice(2))
	elif state == WebSocketPeer.STATE_CLOSED:
		if slot >= 0 or reconnecting:
			# we had a seat: go and get it back
			if not reconnecting:
				reconnecting = true
				_down_for = 0.0
				_backoff = 0.5
			_schedule_retry()
		else:
			var opened := _was_open
			_reset()
			if not opened:
				failed.emit("Couldn't reach the server.")


func _on_text(text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if not (message is Dictionary):
		return
	match str(message.get("type")):
		"room":
			code = str(message["code"])
			slot = int(message["slot"])
			token = str(message.get("token", token))
			is_host = bool(message["host"])
			players = message["players"]
			reconnecting = false
			room_changed.emit()
		"start":
			in_game = true
			players = message["players"]
			is_host = slot == int(message.get("host", 0))
			started.emit(players)
		"left":
			left.emit(int(message["slot"]))
		"back":
			back.emit(int(message["slot"]))
		"closed":
			_give_up(str(message.get("reason", "")))
		"error":
			if str(message.get("code")) == "gone":
				_give_up("gone")
			else:
				failed.emit(str(message.get("message", "Something went wrong.")))
