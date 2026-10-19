class_name EffectsView
extends Node2D
## What gunnery looks like: cannonballs in flight, the flash and smoke of each gun, smoke that
## drifts and thins on the real wind, splashes where balls fall short, splinters where they
## strike, and the wreckage where a ship goes down. All of it moves on the bubble's clock.

var bubble: Bubble
var pixels_per_meter := 2.0
## World position drawn at the screen's top-left, in the bubble's frame.
var origin := Vector2.ZERO

# Each particle is [position, velocity, age, lifetime, kind].
var _particles: Array[Array] = []
var _random := RandomNumberGenerator.new()


func advance(delta: float) -> void:
	for event in bubble.gunnery.events:
		_spawn(event)
	bubble.gunnery.events.clear()
	var wind := bubble.wind.velocity_at(bubble.player.position)
	var living: Array[Array] = []
	for particle in _particles:
		particle[2] += delta
		if particle[2] >= particle[3]:
			continue
		if particle[4] == "smoke":
			# Smoke is carried off by the wind and spreads as it goes.
			particle[1] = (particle[1] as Vector2).lerp(wind, 1.0 - exp(-delta / 2.0))
		else:
			particle[1] *= exp(-delta * 1.5)
		particle[0] += particle[1] * delta
		living.append(particle)
	_particles = living


func _spawn(event: Dictionary) -> void:
	var at: Vector2 = event.position
	var direction: Vector2 = event.direction
	match event.kind:
		"fire":
			_particles.append([at + direction * 1.5, Vector2.ZERO, 0.0, 0.15, "flash"])
			for puff in 4:
				var push := direction * _random.randf_range(3.0, 9.0) + direction.orthogonal() * _random.randf_range(-1.5, 1.5)
				_particles.append([at + direction * 2.0, push, 0.0, _random.randf_range(6.0, 10.0), "smoke"])
		"splash":
			_particles.append([at, Vector2.ZERO, 0.0, 1.5, "splash"])
		"hit":
			for splinter in 6:
				var flying := direction.rotated(_random.randf_range(-1.2, 1.2)) * _random.randf_range(3.0, 10.0)
				_particles.append([at, flying, 0.0, 1.0, "splinter"])
		"sinking":
			_particles.append([at, Vector2.ZERO, 0.0, 6.0, "sinking"])
			for piece in 20:
				var drift := Vector2.from_angle(_random.randf() * TAU) * _random.randf_range(0.5, 3.0)
				_particles.append([at, drift, 0.0, 20.0, "wreckage"])


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if bubble == null:
		return
	for particle in _particles:
		var point := ((particle[0] as Vector2) - origin) * pixels_per_meter
		var life: float = particle[2] / particle[3]
		match particle[4]:
			"smoke":
				var radius := (1.0 + life * 4.0) * maxf(pixels_per_meter, 0.5)
				draw_circle(point.floor(), radius, Palette.SMOKE if life < 0.5 else Palette.SMOKE_FADING)
			"flash":
				draw_rect(Rect2(point.floor() - Vector2.ONE, Vector2(3.0, 3.0)), Palette.FLASH)
			"splash":
				draw_arc(point.floor(), (0.5 + life * 3.0) * pixels_per_meter, 0.0, TAU, 12, Palette.FOAM)
			"splinter", "wreckage":
				draw_rect(Rect2(point.floor(), Vector2.ONE), Palette.HULL)
			"sinking":
				draw_arc(point.floor(), (2.0 + life * 12.0) * pixels_per_meter, 0.0, TAU, 24, Palette.FOAM_FADING)
	for ball in bubble.gunnery.balls:
		var point := ((ball.position as Vector2) - origin) * pixels_per_meter
		draw_rect(Rect2(point.floor(), Vector2(2.0, 2.0) if pixels_per_meter >= 1.0 else Vector2.ONE), Palette.CANNONBALL)
