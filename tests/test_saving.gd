extends TestCase
## A saved voyage has to come back exactly as it was: run the original and the loaded copy on
## side by side, and anything the save left out makes them drift apart.

const TEST_PATH := "user://voyage_test.json"


func _played_voyage() -> Voyage:
	var voyage := Voyage.new()
	voyage.buy("sugar", 10)
	voyage.hire(3)
	voyage.renown = 7.5
	voyage.honor = -4.0
	voyage.sail_to_port(voyage.port_named("Cirebon"))
	for hour in 30:
		voyage.advance(3600.0)
	return voyage


func test_a_loaded_voyage_matches_the_saved_one() -> void:
	var voyage := _played_voyage()
	check(SaveGame.save(voyage, TEST_PATH), "couldn't save")
	var loaded := SaveGame.load_voyage(TEST_PATH)
	check(loaded != null, "couldn't load")
	if loaded == null:
		return
	check(is_equal_approx(loaded.purse, voyage.purse), "purse %.2f against %.2f" % [loaded.purse, voyage.purse])
	check(loaded.ship.hold == voyage.ship.hold, "hold %s against %s" % [loaded.ship.hold, voyage.ship.hold])
	check(loaded.ship.position.is_equal_approx(voyage.ship.position), "the ship moved")
	check(is_equal_approx(loaded.calendar.seconds, voyage.calendar.seconds), "the date changed")
	check(loaded.captains.size() == voyage.captains.size(), "captains went missing")
	check(is_equal_approx(loaded.renown, 7.5) and is_equal_approx(loaded.honor, voyage.honor), "reputation changed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_a_loaded_voyage_carries_on_exactly_like_the_original() -> void:
	var voyage := _played_voyage()
	SaveGame.save(voyage, TEST_PATH)
	var loaded := SaveGame.load_voyage(TEST_PATH)
	for hour in 72:
		voyage.advance(3600.0)
		loaded.advance(3600.0)
	check(loaded.ship.position.distance_to(voyage.ship.position) < 1.0, "the player's ship drifted %.1f meters apart" % loaded.ship.position.distance_to(voyage.ship.position))
	check(loaded.docked.get("name", "") == voyage.docked.get("name", ""), "moored in different ports")
	var apart := 0.0
	for index in voyage.captains.size():
		apart = maxf(apart, voyage.captains[index].ship.position.distance_to(loaded.captains[index].ship.position))
	check(apart < 1.0, "a captain's ship drifted %.1f meters apart" % apart)
	check(is_equal_approx(loaded.markets["Batavia"].stock["sugar"], voyage.markets["Batavia"].stock["sugar"]), "Batavia's sugar stock drifted")
	check(is_equal_approx(loaded.purse, voyage.purse), "the purses drifted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_no_saving_in_the_middle_of_a_battle() -> void:
	var voyage := Voyage.new()
	voyage.bubble = Bubble.new()
	check(not SaveGame.save(voyage, TEST_PATH), "saved in the middle of a battle")


func test_a_save_from_another_version_is_set_aside() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": SaveGame.VERSION + 1, "voyage": {}}))
	file.close()
	check(SaveGame.load_voyage(TEST_PATH) == null, "read a save from another version")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
