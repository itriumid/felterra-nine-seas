class_name SaveGame
extends RefCounted
## Writes the voyage to a file and reads it back. The file lives in each operating system's
## usual place for an application's data (Godot's user://), as JSON with a version number, so a
## save from an older build is recognized instead of misread.

const PATH := "user://voyage.json"
## Bump this whenever what's saved changes shape; older saves are then set aside, not misread.
const VERSION := 1


static func exists(path := PATH) -> bool:
	return FileAccess.file_exists(path)


## Saves the voyage, unless the player is in a battle bubble. Returns whether it saved.
static func save(voyage: Voyage, path := PATH) -> bool:
	if voyage.bubble != null:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	# Full precision: a time or position rounded even slightly shifts when things happen, and
	# the voyage after loading would drift away from the one that was saved.
	file.store_string(JSON.stringify({"version": VERSION, "voyage": voyage.to_saved()}, "", true, true))
	file.close()
	return true


## The saved voyage, or null if there's none, it's unreadable, or it's from another version.
static func load_voyage(path := PATH) -> Voyage:
	if not exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != VERSION:
		return null
	var voyage := Voyage.new()
	voyage.restore(parsed.voyage)
	return voyage
