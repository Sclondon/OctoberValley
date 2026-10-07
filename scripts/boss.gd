extends "res://scripts/enemy.gd"
## A stage boss: a giant enemy that chases the hero and works through its list of attacks.
##   slam    a shockwave along the ground (two when enraged): jump over it
##   volley  three fans of slow shots
##   summon  a pack of minions
##   charge  a wind-up, then a fast dash in a straight line
## Below half health it is enraged: shorter rests and bigger attacks.

const Hazard := preload("res://scripts/hazard.gd")

const WINDUP := 0.75
const CHARGE_SPEED := 22.0
const CHARGE_TIME := 0.9
const SHOT_SPEED := 9.0

var boss_id := ""
var title := ""
## Set by the director, which the boss asks for minions.
var director: Node

var _boss: Dictionary
var _state := "chase"
var _timer := 3.0
var _attack := ""
var _next := 0
var _bursts := 0
var _charge_dir := Vector3.ZERO
var _second_ring := -1.0


func _def() -> Dictionary:
	_boss = Db.BOSSES[boss_id]
	var def: Dictionary = Db.ENEMIES[_boss["enemy"]].duplicate()
	def.merge(_boss, true)
	def["xp"] = 60
	return def


func _ready() -> void:
	is_boss = true
	super()
	title = _boss["name"]
	hit_radius = maxf(radius * 1.3, height * 0.3)


func enraged() -> bool:
	return hp < max_hp * 0.5


func _wish(delta: float) -> Vector3:
	_timer -= delta
	if _second_ring > 0.0:
		_second_ring -= delta
		if _second_ring <= 0.0:
			Hazard.ring(get_parent(), global_position, damage * 0.8, 26.0)
	match _state:
		"windup":
			sprite.modulate = tint.lerp(Color(1.0, 0.25, 0.2), 0.5 + 0.5 * sin(_timer * 30.0))
			if _timer <= 0.0:
				sprite.modulate = tint
				_release()
			return Vector3.ZERO
		"charge":
			if _timer <= 0.0:
				_rest()
			return _charge_dir * CHARGE_SPEED
		"volley":
			if _timer <= 0.0:
				_fan()
				_bursts -= 1
				_timer = 0.5
				if _bursts <= 0:
					_rest()
			return Vector3.ZERO
	if _timer <= 0.0:
		var attacks: Array = _boss["attacks"]
		_attack = attacks[_next % attacks.size()]
		_next += 1
		_state = "windup"
		_timer = WINDUP
	return super(delta)


func _rest() -> void:
	_state = "chase"
	accel = ACCEL
	_timer = randf_range(1.6, 2.6) if enraged() else randf_range(2.6, 4.0)


func _release() -> void:
	match _attack:
		"slam":
			Hazard.ring(get_parent(), global_position, damage * 0.8, 26.0)
			if enraged():
				_second_ring = 0.7
			_rest()
		"summon":
			for i in (6 if enraged() else 4):
				var out := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * (radius + 3.0)
				director.spawn(_boss["minion"], global_position + out)
			_rest()
		"charge":
			var to_target := target.global_position - global_position
			to_target.y = 0.0
			_charge_dir = to_target.normalized()
			_state = "charge"
			_timer = CHARGE_TIME
			accel = 200.0
			_touch_cd = 0.0
		"volley":
			_state = "volley"
			_bursts = 3
			_timer = 0.0


func _fan() -> void:
	var from := global_position + Vector3.UP * 1.4
	var aim: Vector3 = (target.centre() - from).normalized()
	var count := 7 if enraged() else 5
	for i in count:
		var angle := (i - (count - 1) * 0.5) * 0.2
		Hazard.ball(get_parent(), from, aim.rotated(Vector3.UP, angle) * SHOT_SPEED, damage * 0.7, _boss["shot"])
