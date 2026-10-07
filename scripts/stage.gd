extends "res://scripts/level_base.gd"
## A stage of the run, generated from a seed and a theme (see Db.STAGES): a walled valley
## with plateaus you can run up, rocks to hop on, floating steps, and sprite props. The altar
## is placed far from the start.

const WALL_HEIGHT := 16.0
const PLATEAUS := 9
const ROCKS := 18
const STEP_CHAINS := 3
const PROPS := 110
## Kept clear of scenery around the start and the altar.
const CLEARING := 9.0

var theme: Dictionary
var seed_value := 0

var _rng := RandomNumberGenerator.new()
## Footprints already taken, as [centre, half size] on the XZ plane.
var _taken: Array = []


func _ready() -> void:
	_rng.seed = seed_value
	half_extent = 80.0
	line_color = Color(theme["line"])
	build_sky(theme)
	yard(Color(theme["ground"]), Color(theme["wall"]), WALL_HEIGHT)
	start_position = Vector3(0.0, 0.1, half_extent - 14.0)
	altar_position = _random_spot(half_extent - 16.0)
	while altar_position.distance_to(start_position) < 75.0:
		altar_position = _random_spot(half_extent - 16.0)
	_build_plateaus()
	_build_rocks()
	_build_steps()
	_build_props()


func _random_spot(limit: float) -> Vector3:
	return Vector3(_rng.randf_range(-limit, limit), 0.0, _rng.randf_range(-limit, limit))


## True if a footprint of `half` size at `at` would touch a clearing or anything already built.
func _blocked(at: Vector3, half: Vector2) -> bool:
	var reach := maxf(half.x, half.y) + CLEARING
	if at.distance_to(start_position) < reach or at.distance_to(altar_position) < reach:
		return true
	for taken: Array in _taken:
		var centre: Vector2 = taken[0]
		var size: Vector2 = taken[1]
		if absf(at.x - centre.x) < half.x + size.x and absf(at.z - centre.y) < half.y + size.y:
			return true
	return false


func _build_plateaus() -> void:
	var rock := Color(theme["rock"])
	var slope := Color(theme["ramp"])
	for i in PLATEAUS:
		for attempt in 20:
			var size := Vector3(_rng.randf_range(10.0, 20.0), _rng.randf_range(2.0, 5.0), _rng.randf_range(10.0, 20.0))
			var run := size.y * 2.4
			var half := Vector2(size.x * 0.5 + run, size.z * 0.5 + run)
			var at := _random_spot(half_extent - 28.0)
			if _blocked(at, half):
				continue
			_taken.append([Vector2(at.x, at.z), half])
			block(at + Vector3.UP * size.y * 0.5, size, rock)
			var first := _rng.randi_range(0, 3)
			for side in _rng.randi_range(1, 2):
				var yaw := (first + side * 2) * PI * 0.5
				var out := Vector3.FORWARD.rotated(Vector3.UP, yaw)
				var along := size.z * 0.5 if is_zero_approx(out.x) else size.x * 0.5
				ramp(at - out * (along + run), yaw, run, size.y, 5.0, slope)
			break


func _build_rocks() -> void:
	var rock := Color(theme["rock"])
	for i in ROCKS:
		for attempt in 10:
			var size := Vector3(_rng.randf_range(2.5, 5.0), _rng.randf_range(1.0, 2.6), _rng.randf_range(2.5, 5.0))
			var half := Vector2(size.x, size.z) * 0.75
			var at := _random_spot(half_extent - 8.0)
			if _blocked(at, half):
				continue
			_taken.append([Vector2(at.x, at.z), half])
			block(at + Vector3.UP * size.y * 0.5, size, rock).rotation.y = _rng.randf() * PI
			break


## Platforms rising in a line: somewhere to climb away from the walkers.
func _build_steps() -> void:
	var slope := Color(theme["ramp"])
	for i in STEP_CHAINS:
		for attempt in 10:
			var at := _random_spot(half_extent - 30.0)
			var dir := Vector3.FORWARD.rotated(Vector3.UP, _rng.randi_range(0, 3) * PI * 0.5)
			var middle := at + dir * 10.0
			var half := Vector2(4.0 + absf(dir.x) * 10.0, 4.0 + absf(dir.z) * 10.0)
			if _blocked(middle, half):
				continue
			_taken.append([Vector2(middle.x, middle.z), half])
			for step in 5:
				block(at + dir * step * 5.0 + Vector3.UP * (2.0 + step * 2.0), Vector3(4.0, 0.6, 4.0), slope)
			break


func _build_props() -> void:
	var props: Array = theme["props"]
	var total := 0
	for entry: Array in props:
		total += int(entry[2])
	for i in PROPS:
		var at := _random_spot(half_extent - 3.0)
		if _blocked(at, Vector2.ZERO):
			continue
		var roll := _rng.randi_range(1, total)
		for entry: Array in props:
			roll -= int(entry[2])
			if roll <= 0:
				prop(entry[0], entry[1], at)
				break
