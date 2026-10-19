class_name Ship
extends RefCounted
## One ship under sail: its state, and the forces that move it from one step to the next.
##
## The model, in order:
## 1. Apparent wind is the true wind minus the ship's own velocity. It's the only wind the
##    sails feel.
## 2. Each sail is a curved plate set at an angle to the centerline. Its angle of attack to the
##    apparent wind gives lift and drag coefficients, and the dynamic pressure of the apparent
##    wind turns those into a force.
## 3. The hull resists that force: little going forward, a lot going sideways (the keel), and a
##    steeply rising bow wave as it nears hull speed.
## 4. The rudder only turns the ship while water flows past it, so a ship that has stopped can't
##    steer. The wind on the hull and rigging still turns it, though, so a ship stopped head to
##    wind falls off on its own, the way a real one does in irons.
##
## Directions use Godot's screen coordinates: x to the right, y down, angles clockwise. A
## heading of 0 points east; -PI / 2 points north.

const AIR_DENSITY := 1.225
const WATER_DENSITY := 1025.0
const GRAVITY := 9.81
## Skin friction and form drag of the hull, per unit of wetted area.
const HULL_FRICTION := 0.0045
## Bow wave resistance at hull speed, as a fraction of the ship's weight.
const WAVE_RESISTANCE := 0.012
## Extra mass of the water the hull drags along when it accelerates.
const ADDED_MASS_FORWARD := 0.05
const ADDED_MASS_SIDEWAYS := 0.5
const RUDDER_LIMIT := deg_to_rad(35.0)
## How many simulation steps the automatic trim reuses its last answer.
const AUTOMATIC_TRIM_INTERVAL := 6
const AUTOMATIC_TRIM_SAMPLES := 24

var design: ShipDesign
var position := Vector2.ZERO
var velocity := Vector2.ZERO
var heading := 0.0
var yaw_rate := 0.0

## Helm, from -1 (hard to port) to 1 (hard to starboard).
var rudder := 0.0
## How much sail the crew is ordered to set, 0 (furled) to 1 (all plain sail).
var sail_ordered := 1.0
## How much sail is actually set right now; it follows the order at the crew's pace.
var sail_set := 1.0
## Manual trim, 0 (sheeted hard in) to 1 (eased right out).
var sheet := 0.5
## Trim the sails for the most drive every few steps, like a good crew would.
var automatic_trim := true
## Hold the headsails (the jib, or the foremast's yards) out against the wind. The wind then
## pushes the bow away from it: how sailors get a ship out of irons.
var backing_headsails := false

## Where the sails actually sit, from dead aft, positive to starboard. Swings toward the trim at
## the design's trim rate, so a tack or a gybe takes time.
var sail_angle := 0.0
## Positive heels to starboard.
var heel := 0.0
## Kilograms of cargo aboard. It weighs the ship down: more inertia, a deeper hull with more
## drag, and more stability under sail.
var cargo_mass := 0.0
## Barnacles and weed on the hull, 0 for a clean bottom. Each unit doubles the hull's friction.
var fouling := 0.0
## Soundness of the hull, 1 for new.
var hull := 1.0
## Soundness of masts, yards and sails, 1 for new: the share of sail the ship can still carry.
var rigging := 1.0

# Read by the views and the heads-up display; the simulation recomputes them every step.
var apparent_wind := Vector2.ZERO
var angle_of_attack := 0.0
var sail_force := Vector2.ZERO
var luffing := 0.0
var aback := false

var _automatic_trim_angle := 0.0
var _steps_since_trim := AUTOMATIC_TRIM_INTERVAL


func _init(ship_design: ShipDesign) -> void:
	design = ship_design
	sail_angle = design.sail_angle_minimum
	_automatic_trim_angle = design.sail_angle_minimum


func forward() -> Vector2:
	return Vector2.from_angle(heading)


## The ship and everything in it, in kilograms.
func mass() -> float:
	return design.mass + cargo_mass


## How much heavier than empty the ship is; the hull sinks deeper as this grows.
func _load_ratio() -> float:
	return mass() / design.mass


func starboard() -> Vector2:
	return Vector2.from_angle(heading + PI / 2.0)


func forward_speed() -> float:
	return velocity.dot(forward())


## Angle between the bow and where the given wind comes from: 0 is head to wind, PI is dead
## downwind. Positive when it comes over the starboard side.
func wind_angle(wind_velocity: Vector2) -> float:
	var coming_from := -wind_velocity
	return forward().angle_to(coming_from)


## Sets the sails straight to the best trim for the wind, as if the crew had been sailing all
## along: for a ship that's just appeared, not one that's been sailing.
func trim_instantly(true_wind: Vector2) -> void:
	apparent_wind = true_wind - velocity
	_automatic_trim_angle = _best_trim_angle()
	_steps_since_trim = 0
	sail_angle = _automatic_trim_angle * _leeward_sign()


## Puts the ship in the steady state for its speed and the wind: sails trimmed, forces and heel
## settled. For showing a ship whose motion is worked out elsewhere, like on the world map.
func settle(true_wind: Vector2) -> void:
	trim_instantly(true_wind)
	sail_force = _sail_force(sail_angle, true)
	heel = clampf(sail_force.dot(starboard()) / _heel_stiffness(), -1.2, 1.2)


func step(delta: float, true_wind: Vector2) -> void:
	sail_set = move_toward(sail_set, sail_ordered, design.sail_handling_rate * delta)
	apparent_wind = true_wind - velocity

	_trim_sails(delta)
	var headsail_force := Vector2.ZERO
	if backing_headsails and sail_set > 0.0:
		var backed_angle := -_leeward_sign() * design.backed_headsail_angle
		headsail_force = _sail_force(backed_angle, false, true) * design.headsail_fraction
		sail_force = _sail_force(sail_angle, true) * (1.0 - design.headsail_fraction)
	else:
		sail_force = _sail_force(sail_angle, true)
	var flow_speed := apparent_wind.length()
	var windage := 0.5 * AIR_DENSITY * flow_speed * design.windage_area * apparent_wind

	var ahead := forward()
	var side := starboard()
	var total := sail_force + headsail_force + windage
	var surge := velocity.dot(ahead)
	var sway := velocity.dot(side)

	var hull_forward := -_hull_resistance(surge)
	# The keel works like a wing: sideways force grows with both leeway and forward speed. The
	# second term is plain crossflow drag, which is all that's left once the ship stops.
	var hull_sideways := -0.5 * WATER_DENSITY * design.lateral_area * (
		design.lateral_lift_slope * absf(surge) * sway + sway * absf(sway)
	)

	var surge_force := total.dot(ahead) + hull_forward
	var sway_force := total.dot(side) + hull_sideways
	var acceleration := (
		ahead * surge_force / (mass() * (1.0 + ADDED_MASS_FORWARD))
		+ side * sway_force / (mass() * (1.0 + ADDED_MASS_SIDEWAYS))
	)
	velocity += acceleration * delta
	position += velocity * delta

	# Windage pushes forward of the keel's center, so it turns the ship as well as pushing it.
	var windage_torque := (ahead * design.windage_center).cross(windage)
	var headsail_torque := (ahead * design.headsail_center).cross(headsail_force)
	_turn(delta, surge, windage_torque + headsail_torque)

	var heel_target := clampf((sail_force + headsail_force).dot(side) / _heel_stiffness(), -1.2, 1.2)
	heel = lerpf(heel, heel_target, 1.0 - exp(-delta / 1.0))


func _turn(delta: float, surge: float, outside_torque: float) -> void:
	var empty_inertia := design.mass * pow(design.length_overall / 4.0, 2.0)
	var moment_of_inertia := empty_inertia * _load_ratio()
	var cruising := 0.8 * design.hull_speed()
	# Damping chosen so the empty hull settles into a turn in yaw_response seconds at cruising
	# speed, and rudder authority so the steady turn has the design's radius. Loaded, the same
	# rudder swings more mass, so the ship answers more slowly.
	var damping := empty_inertia / (design.yaw_response * cruising)
	var authority := damping / (design.turning_radius * design.length_overall)
	var rudder_torque := authority * rudder * surge * absf(surge)
	# A hull sitting still barely resists a slow turn, so the floor under the speed term is small.
	var damping_torque := -damping * yaw_rate * (absf(surge) + 0.1)
	yaw_rate += (rudder_torque + damping_torque + outside_torque) / moment_of_inertia * delta
	heading = wrapf(heading + yaw_rate * delta, -PI, PI)


func _hull_resistance(surge: float) -> float:
	# A deeper hull wets more of its sides; area grows with displaced volume to the two thirds.
	var wetted_area := design.wetted_area * pow(_load_ratio(), 2.0 / 3.0)
	var friction := 0.5 * WATER_DENSITY * wetted_area * HULL_FRICTION * (1.0 + fouling) * surge * absf(surge)
	var ratio := absf(surge) / design.hull_speed()
	# Below hull speed the bow wave grows with the fourth power of speed; past it the hull is
	# climbing its own wave and the resistance turns into a wall.
	var wave := mass() * GRAVITY * WAVE_RESISTANCE * pow(ratio, 4.0) * pow(maxf(ratio, 1.0), 8.0)
	return friction + wave * signf(surge)


## Side force that heels the ship a radian. Cargo low in the hold works like ballast.
func _heel_stiffness() -> float:
	return design.heel_stiffness * _load_ratio()


## The side the sails swing to: away from the wind.
func _leeward_sign() -> float:
	var across := apparent_wind.dot(starboard())
	if absf(across) < 0.01:
		return signf(sail_angle) if sail_angle != 0.0 else 1.0
	return signf(across)


## How far from dead aft a free sail would stream with the apparent wind, so the farthest a
## fore-and-aft sail can swing before it just flaps.
func _free_sail_angle() -> float:
	if apparent_wind.length_squared() < 0.0001:
		return design.sail_angle_maximum
	return absf((-forward()).angle_to(apparent_wind))


func _trim_sails(delta: float) -> void:
	var magnitude: float
	if automatic_trim:
		_steps_since_trim += 1
		if _steps_since_trim >= AUTOMATIC_TRIM_INTERVAL:
			_steps_since_trim = 0
			_automatic_trim_angle = _best_trim_angle()
		magnitude = _automatic_trim_angle
		sheet = inverse_lerp(design.sail_angle_minimum, design.sail_angle_maximum, magnitude)
	else:
		magnitude = lerpf(design.sail_angle_minimum, design.sail_angle_maximum, sheet)
	if design.rig == ShipDesign.Rig.FORE_AND_AFT:
		# A sheet only stops the boom swinging out. Ease it past where the wind would carry the
		# sail and the sail just streams like a flag.
		magnitude = minf(magnitude, _free_sail_angle())
	var target := magnitude * _leeward_sign()
	sail_angle = move_toward(sail_angle, target, design.trim_rate * delta)


## The trim that drives the ship forward hardest, tried at evenly spaced angles.
func _best_trim_angle() -> float:
	var best_angle := design.sail_angle_minimum
	var best_drive := -INF
	var free := _free_sail_angle()
	for index in AUTOMATIC_TRIM_SAMPLES:
		var magnitude := lerpf(
			design.sail_angle_minimum,
			design.sail_angle_maximum,
			float(index) / float(AUTOMATIC_TRIM_SAMPLES - 1)
		)
		if design.rig == ShipDesign.Rig.FORE_AND_AFT:
			magnitude = minf(magnitude, free)
		var drive := _sail_force(magnitude * _leeward_sign(), false).dot(forward())
		if drive > best_drive:
			best_drive = drive
			best_angle = magnitude
	return best_angle


## Aerodynamic force on the sails set at an angle from dead aft. Updates the angle of attack
## and luffing readouts when record is true. A sail held aback is pinned against the wind, so
## even a soft one takes the push instead of flapping.
func _sail_force(angle: float, record: bool, held_aback := false) -> Vector2:
	var flow_speed := apparent_wind.length()
	if flow_speed < 0.01 or sail_set <= 0.0:
		if record:
			angle_of_attack = 0.0
			luffing = 0.0
			aback = false
		return Vector2.ZERO
	var flow := apparent_wind / flow_speed
	var side := signf(angle) if angle != 0.0 else _leeward_sign()
	var swing := absf(angle)
	# Chord runs from the luff (leading edge) to the leech; the normal is the leeward face.
	var chord := -forward() * cos(swing) + starboard() * sin(swing) * side
	var normal := forward() * sin(swing) + starboard() * cos(swing) * side
	var attack := atan2(flow.dot(normal), flow.dot(chord))

	var lift: float
	var drag: float
	var is_luffing := false
	if attack < 0.0 and design.rig == ShipDesign.Rig.FORE_AND_AFT and not held_aback:
		# Wind on the wrong face of a soft sail doesn't push it, it collapses it: the sail
		# flaps, giving only drag.
		lift = 0.0
		drag = design.parasitic_drag + 0.15
		is_luffing = true
	else:
		lift = signf(attack) * lift_coefficient(absf(attack), design)
		drag = design.parasitic_drag + design.induced_drag * lift * lift + 1.1 * pow(sin(attack), 2.0)

	var lift_direction := normal - flow * normal.dot(flow)
	if lift_direction.length_squared() > 0.000001:
		lift_direction = lift_direction.normalized()
	else:
		lift_direction = Vector2.ZERO

	if record:
		angle_of_attack = attack
		luffing = 1.0 if is_luffing else clampf(1.0 - absf(attack) / deg_to_rad(4.0), 0.0, 1.0)
		aback = attack < 0.0 and design.rig == ShipDesign.Rig.SQUARE

	# Heeling tips the sails away from the wind, so they catch less of it; cut rigging carries
	# less sail.
	var area := design.sail_area * minf(sail_set, rigging) * cos(heel)
	var dynamic_pressure := 0.5 * AIR_DENSITY * flow_speed * flow_speed
	return dynamic_pressure * area * (lift_direction * lift + flow * drag)


## Lift coefficient of a sail at an angle of attack between 0 and PI. Below the stall it's an
## attached airfoil; past it the flow separates and the sail behaves like a flat plate, which
## still makes some lift until it's square to the wind, then pushes the other way.
static func lift_coefficient(attack: float, ship_design: ShipDesign) -> float:
	var plate := sin(2.0 * attack)
	if attack > PI / 2.0:
		return plate
	var attached: float
	if attack <= ship_design.stall_angle:
		attached = ship_design.lift_maximum * sin(PI / 2.0 * attack / ship_design.stall_angle)
	else:
		attached = ship_design.lift_maximum * exp(-(attack - ship_design.stall_angle) / deg_to_rad(12.0))
	return maxf(attached, plate)
