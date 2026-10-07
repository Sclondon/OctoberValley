extends "res://scripts/level_base.gd"
## The test yard: a walled greybox for trying out movement and weapons (TEST YARD on the
## title screen). It has no altar, so there is no boss and no way out.
##
## From the start, facing north (-Z): the hill is straight ahead, the slope tests are to the
## west, the jump-height steps to the east, the gap run behind you, and the pillar field and
## the climbing tower beyond the hill.

const GROUND := Color("2a2438")
const WALL := Color("1c1830")
const STONE := Color("4a4466")
const PUMPKIN := Color("c8541c")
const MOSS := Color("2c866b")
const LOOK := {"sky_top": "120c2e", "sky_horizon": "d9632a", "ambient": "a098c8", "fog": "6a3a4c", "sun": "ffc890"}


func _ready() -> void:
	build_sky(LOOK)
	yard(GROUND, WALL, 10.0)
	_build_hill()
	_build_slopes()
	_build_steps()
	_build_gaps()
	_build_pillars()
	_build_tower()


## A plateau with a ramp up each side.
func _build_hill() -> void:
	block(Vector3(0, 2.0, -8.0), Vector3(16, 4, 16), STONE)
	for i in 4:
		var yaw := i * PI * 0.5
		var out := Vector3.FORWARD.rotated(Vector3.UP, yaw)
		ramp(Vector3(0, 0, -8.0) - out * 20.0, yaw, 12.0, 4.0, 6.0, PUMPKIN)


## Ramps of rising steepness. The hero walks up anything under 50 degrees.
func _build_slopes() -> void:
	var degrees := [15, 30, 45, 55]
	for i in degrees.size():
		var x := -30.0 - i * 9.0
		var rise := 5.0
		var run := rise / tan(deg_to_rad(degrees[i]))
		ramp(Vector3(x, 0, 30.0), 0.0, run, rise, 7.0, PUMPKIN)
		block(Vector3(x, rise * 0.5, 30.0 - run - 3.0), Vector3(7, rise, 6), STONE)
		sign_post(Vector3(x, 2.2, 32.0), "%d°" % degrees[i])


## Blocks of rising height, for judging the jump and the double jump.
func _build_steps() -> void:
	for i in 6:
		var height := 1.0 + i
		var x := 22.0 + i * 6.0
		block(Vector3(x, height * 0.5, 30.0), Vector3(5, height, 5), MOSS)
		sign_post(Vector3(x, height + 1.6, 30.0), "%d m" % int(height))


## A raised run of platforms with wider and wider gaps between them.
func _build_gaps() -> void:
	var z := 56.0
	var x := -20.0
	ramp(Vector3(x - 12.0, 0, z), -PI * 0.5, 9.0, 3.0, 5.0, PUMPKIN)
	for gap: float in [0.0, 3.0, 5.0, 7.0, 9.0]:
		x += gap
		if gap > 0.0:
			sign_post(Vector3(x - gap * 0.5, 4.4, z), "%d m" % int(gap))
		block(Vector3(x, 1.5, z), Vector3(6, 3, 5), MOSS)
		x += 6.0


## Something to weave through, and for enemies to get stuck on.
func _build_pillars() -> void:
	for ix in 5:
		for iz in 5:
			block(Vector3(18.0 + ix * 6.0, 3.0, -24.0 - iz * 6.0), Vector3(1.4, 6.0, 1.4), STONE)


## Platforms spiralling up a column.
func _build_tower() -> void:
	var centre := Vector3(-32.0, 0.0, -34.0)
	block(centre + Vector3.UP * 10.0, Vector3(4, 20, 4), STONE)
	for i in 9:
		var out := Vector3.FORWARD.rotated(Vector3.UP, i * PI * 0.5) * 4.5
		block(centre + out + Vector3.UP * (2.0 + i * 2.2), Vector3(5, 0.6, 5), MOSS)
	sign_post(centre + Vector3(0, 3.0, 9.0), "climb")
