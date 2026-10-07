extends RefCounted
## The heroes in the run: one when playing alone, up to four in co-op. Enemies, loot and
## boss attacks ask this who to go for. It also hands out the short ids that co-op snapshots
## use to tell things apart.

## Every hero in the tree, dead or alive (Player nodes; they add and remove themselves).
static var heroes: Array = []

static var _next_id := 0


static func alive() -> Array:
	return heroes.filter(func(hero: Node3D) -> bool: return not hero.dead and hero.active)


## The nearest living hero to `from`, or null.
static func nearest(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for hero: Node3D in heroes:
		if hero.dead or not hero.active:
			continue
		var distance := from.distance_squared_to(hero.global_position)
		if distance < best_distance:
			best_distance = distance
			best = hero
	return best


## A 16-bit id, unique among everything alive at once.
static func next_id() -> int:
	_next_id = (_next_id + 1) & 0xFFFF
	return _next_id
