extends Node3D
## Something to collect: candy (experience), a heart (health) or a chest (a free upgrade).
## Candy and hearts fly to the hero once inside the magnet range.

const AnimSprite := preload("res://scripts/anim_sprite.gd")
const Db := preload("res://scripts/db.gd")
const Team := preload("res://scripts/team.gd")

const GROUP := "pickups"
const MAGNET_RANGE := 3.5
const HEART_HEAL := 25.0

var kind := "candy"
var value := 1
## The sprite sheet it shows, and its id, for co-op snapshots.
var sheet := "chest"
var net_id := 0
## Set to pull this in from anywhere (the candy sweep when a boss dies).
var vacuum := false

var _pull := 0.0
var _clock := 0.0
var _rest := Vector3.ZERO


static func drop(parent: Node, pickup_kind: String, at: Vector3, amount := 1) -> Node3D:
	var pickup: Node3D = load("res://scripts/pickup.gd").new()
	pickup.kind = pickup_kind
	pickup.value = amount
	pickup.position = at
	parent.add_child(pickup)
	return pickup


func _ready() -> void:
	add_to_group(GROUP)
	net_id = Team.next_id()
	if kind == "heart":
		sheet = "heart_pump"
	elif kind == "candy":
		for tier: Array in Db.CANDY:
			sheet = tier[0]
			if value >= tier[1]:
				break
	add_child(make_sprite(sheet))
	_rest = position
	_clock = randf() * TAU


## The floating sprite for a pickup sheet (guests draw the same one).
static func make_sprite(pickup_sheet: String) -> Sprite3D:
	var size := 1.3 if pickup_sheet == "chest" else (0.8 if pickup_sheet == "heart_pump" else 0.9)
	var sprite := AnimSprite.make(pickup_sheet, size)
	sprite.position.y = size * 0.5 + 0.1
	return sprite


func _physics_process(delta: float) -> void:
	var hero := Team.nearest(global_position)
	if hero == null:
		return
	_clock += delta
	var to_player: Vector3 = hero.centre() - global_position
	var distance := to_player.length()
	if distance < (1.6 if kind == "chest" else 1.0):
		_collect(hero)
		return
	if kind != "chest" and (vacuum or distance < MAGNET_RANGE * hero.stat("magnet")):
		_pull = minf(_pull + 40.0 * delta, 30.0)
		global_position += to_player / distance * _pull * delta
	else:
		_pull = 0.0
		position.y = _rest.y + sin(_clock * 3.0) * 0.12


## Candy is shared: everyone on the team gets the experience. Hearts and chests go to
## whoever picked them up.
func _collect(hero: Node3D) -> void:
	match kind:
		"candy":
			for each: Node3D in Team.heroes:
				each.gain_xp(value)
		"heart":
			hero.heal(HEART_HEAL)
		"chest":
			hero.chests_owed += 1
	queue_free()
