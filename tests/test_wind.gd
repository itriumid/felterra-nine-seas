extends TestCase


func test_bearings_match_the_compass() -> void:
	check(Wind.bearing_to_direction(0.0).is_equal_approx(Vector2.UP), "north is not up")
	check(Wind.bearing_to_direction(90.0).is_equal_approx(Vector2.RIGHT), "east is not right")
	check(is_equal_approx(Wind.direction_to_bearing(Vector2.DOWN), 180.0), "down is not south")


func test_wind_blows_away_from_its_bearing() -> void:
	var wind := Wind.steady(7.0, 0.0)
	var velocity := wind.velocity_at(Vector2.ZERO)
	check(velocity.is_equal_approx(Vector2.DOWN * 7.0), "a north wind blew toward %s" % velocity)


func test_gusts_vary_but_stay_near_the_mean() -> void:
	var wind := Wind.new()
	var slowest := INF
	var fastest := 0.0
	for index in 200:
		var speed := wind.velocity_at(Vector2(index * 37.0, index * 11.0)).length()
		slowest = minf(slowest, speed)
		fastest = maxf(fastest, speed)
	check(fastest - slowest > 0.5, "gusts ranged only %.2f meters per second" % (fastest - slowest))
	check(slowest > wind.base_speed * 0.6 and fastest < wind.base_speed * 1.4,
		"wind ranged from %.2f to %.2f" % [slowest, fastest])
