class_name TestCase
extends RefCounted
## Base for test files: collects failed checks instead of stopping at the first one.

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
