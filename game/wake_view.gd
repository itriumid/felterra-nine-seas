class_name WakeView
extends Node2D
## Foam a ship leaves behind: puffs shed at the stern and the bow that spread outward and fade,
## opening into the V of a real wake. It lasts long enough to trace the ship's track, which is
## the clearest sign of how far it has come and where it turned.

const LIFETIME := 40.0
const SHED_INTERVAL := 0.1

var ship: Ship
var pixels_per_meter := 2.0
## World position drawn at the screen's top-left, so the view never handles huge coordinates.
var origin := Vector2.ZERO

# Each puff is [position in meters, velocity in meters per second, age and lifetime in seconds].
var _puffs: Array[Array] = []
var _since_shed := 0.0
var _random := RandomNumberGenerator.new()


func clear() -> void:
	_puffs.clear()


func advance(delta: float) -> void:
	for puff in _puffs:
		puff[0] += puff[1] * delta
		puff[1] *= exp(-delta * 0.6)
		puff[2] += delta
	_puffs = _puffs.filter(func(puff: Array) -> bool: return puff[2] < puff[3])

	var speed := ship.velocity.length()
	_since_shed += delta
	if speed < 0.4 or _since_shed < SHED_INTERVAL:
		return
	_since_shed = 0.0
	var forward := ship.forward()
	var starboard := ship.starboard()
	var half_length := ship.design.length_overall / 2.0
	var half_beam := ship.design.beam / 2.0
	# Waves spread at about a third of the ship's speed, which opens the classic narrow V.
	var spread := speed * 0.33
	for side: float in [-1.0, 1.0]:
		var stern := ship.position - forward * half_length * 0.95 + starboard * side * half_beam * 0.5
		_shed(stern, starboard * side * spread)
		if speed > ship.design.hull_speed() * 0.6:
			var bow := ship.position + forward * half_length * 0.6 + starboard * side * half_beam
			_shed(bow, starboard * side * spread * 1.4)


## Foam is broken and uneven, so each puff lands a little off and lasts a little differently.
func _shed(at: Vector2, drift: Vector2) -> void:
	if _random.randf() < 0.35:
		return
	var jitter := Vector2(_random.randf_range(-0.6, 0.6), _random.randf_range(-0.6, 0.6))
	_puffs.append([at + jitter, drift * _random.randf_range(0.6, 1.2), 0.0, LIFETIME * _random.randf_range(0.4, 1.0)])


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for puff in _puffs:
		var life: float = puff[2] / puff[3]
		var color := Palette.FOAM if life < 0.35 else Palette.FOAM_FADING
		if life > 0.75:
			color = Palette.RIPPLE
		var point: Vector2 = (puff[0] - origin) * pixels_per_meter
		draw_rect(Rect2(point.floor(), Vector2.ONE), color)
