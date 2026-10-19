extends SceneTree
## Runs every test file in this directory and exits with a failure code if any test fails.
## Run with: godot --headless --path . --script tests/run_tests.gd
##
## A test file is any test_*.gd here; its tests are the methods whose names start with test_.
## Each test gets a fresh instance and reports failures through check().

const TEST_DIRECTORY := "res://tests"


func _init() -> void:
	var failures := 0
	var count := 0
	for file_name in DirAccess.get_files_at(TEST_DIRECTORY):
		if not (file_name.begins_with("test_") and file_name.ends_with(".gd")):
			continue
		var script := load(TEST_DIRECTORY.path_join(file_name)) as GDScript
		if script == null or not script.can_instantiate():
			# A test file that doesn't compile runs no tests; that's a failure, not a pass.
			count += 1
			failures += 1
			print("FAIL  %s: doesn't compile" % file_name)
			continue
		for method in script.get_script_method_list():
			var method_name: String = method.name
			if not method_name.begins_with("test_"):
				continue
			count += 1
			var test: TestCase = script.new()
			test.call(method_name)
			if test.failures.is_empty():
				print("pass  %s: %s" % [file_name, method_name])
			else:
				failures += 1
				print("FAIL  %s: %s" % [file_name, method_name])
				for message in test.failures:
					print("      " + message)
	print("\n%d of %d tests passed." % [count - failures, count])
	quit(1 if failures > 0 or count == 0 else 0)
