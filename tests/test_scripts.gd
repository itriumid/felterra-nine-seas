extends TestCase
## Every script in the game has to compile. The physics tests never touch the game's views, so
## without this a typo there would only show up when someone launched the game.

const DIRECTORIES: Array[String] = ["res://game", "res://simulation"]


func test_every_script_compiles() -> void:
	for directory in DIRECTORIES:
		for file_name in DirAccess.get_files_at(directory):
			if not file_name.ends_with(".gd"):
				continue
			var path := directory.path_join(file_name)
			var script := load(path) as GDScript
			check(script != null and script.can_instantiate(), "%s doesn't compile" % path)
