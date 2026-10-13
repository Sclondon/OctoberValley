extends RefCounted
## What is remembered between visits: the best run with each hero, how many runs were played,
## and whether the sound is off. One small JSON file (in the browser it lives in the page's
## own storage).

const PATH := "user://october_valley.json"

static var _data := {}
static var _loaded := false
## Tests point this somewhere else, or turn saving off with "".
static var path := PATH


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {"best": {}, "runs": 0, "muted": false}
		if path != "" and FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_data.merge(parsed, true)
	return _data


static func write() -> void:
	if path == "":
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data()))
		file.close()


## The best run with `hero` ({score, stage, seconds, kills, level}), or {} if there is none.
static func best(hero: String) -> Dictionary:
	var all: Dictionary = data()["best"]
	var entry: Variant = all.get(hero, {})
	return entry if entry is Dictionary else {}


## The highest score with any hero.
static func best_score() -> int:
	var top := 0
	var all: Dictionary = data()["best"]
	for hero: String in all:
		top = maxi(top, int(best(hero).get("score", 0)))
	return top


## Counts the run, and keeps it if it beats the hero's best. Returns true if it did.
static func record(hero: String, run: Dictionary) -> bool:
	data()["runs"] = int(data()["runs"]) + 1
	var better := int(run["score"]) > int(best(hero).get("score", 0))
	if better:
		data()["best"][hero] = run
	write()
	return better


static func set_muted(muted: bool) -> void:
	data()["muted"] = muted
	write()
