class_name ShipDesign
extends RefCounted
## The fixed numbers that make one class of ship sail the way it does. Everything is in SI units:
## meters, kilograms, newtons, radians.

enum Rig {
	## Sails that run fore and aft along the centerline (sloops, schooners). The boom swings
	## freely to leeward, so the sail can be sheeted in close and points high into the wind.
	FORE_AND_AFT,
	## Sails hung from yards across the ship (brigs, frigates, galleons). The yards can only be
	## braced so far before they hit the rigging, which is why these ships can't point high.
	SQUARE,
}

## Stable key for saved data and tables; never shown.
var id: String
var display_name: String
var rig: Rig
var length_overall: float
var waterline_length: float
var beam: float
var mass: float
## Area of all plain sail set.
var sail_area: float
## How close to the centerline the sails can be trimmed, measured from dead aft. A square rig's
## limit is set by how far its yards can be braced around.
var sail_angle_minimum: float
var sail_angle_maximum: float
var lift_maximum: float
var stall_angle: float
## Drag of the sail at zero lift: rigging, sail shape, everything that isn't the airfoil.
var parasitic_drag: float
## Extra drag per unit of lift squared; low-aspect sails pay more.
var induced_drag: float
## Hull and rigging area the wind pushes on even with the sails furled.
var windage_area: float
## How far forward of the keel's center the wind pushes on that area, in meters. Bowsprits and
## forecastles put it forward, so a ship stopped head to wind has its bow blown off.
var windage_center: float
var wetted_area: float
## Area of keel and hull that resists sliding sideways.
var lateral_area: float
## How well that area turns leeway into sideways force. A deep keel is near 2, a shallow
## full-bodied hull lower.
var lateral_lift_slope: float
## Share of the sail area in the headsails: the jib, or everything on the foremast.
var headsail_fraction: float
## Where the headsails' force acts, in meters forward of the keel's center.
var headsail_center: float
## How far from dead aft the headsails sit when held out against the wind.
var backed_headsail_angle: float
## Turning circle radius at full rudder, in ship lengths.
var turning_radius: float
## Seconds the hull takes to settle into a turn at cruising speed.
var yaw_response: float
## Side force from the sails that heels the ship by one radian.
var heel_stiffness: float
## How fast the crew sets or takes in sail, as a fraction of all plain sail per second.
var sail_handling_rate: float
## How fast the sails swing to a new trim, in radians per second.
var trim_rate: float
## Mast positions along the hull, in meters forward of midships.
var masts: PackedFloat32Array
## Tons of cargo the hold carries.
var cargo_capacity: float
## Sailors needed to handle all plain sail, and the most the ship can berth.
var crew_minimum: int
var crew_maximum: int
## What a shipyard asks for one, in reals.
var price: int
## Gun ports, both sides together; each broadside is half of them.
var gun_ports: int

## A six-pounder on its carriage, with its tackle and shot: about a ton, and it weighs the ship
## down like cargo.
const GUN_MASS := 900.0
const GUN_PRICE := 120


## The speed where a displacement hull starts climbing its own bow wave: a Froude number of
## about 0.4, the same as the old rule of thumb of 1.34 times the square root of the waterline
## length in feet, in knots.
func hull_speed() -> float:
	return 0.4 * sqrt(9.81 * waterline_length)


## A Jamaica sloop: small, overcanvassed, and quick to windward. The pirate's favorite.
static func sloop() -> ShipDesign:
	var design := ShipDesign.new()
	design.id = "sloop"
	design.display_name = "Sloop"
	design.rig = Rig.FORE_AND_AFT
	design.length_overall = 20.0
	design.waterline_length = 16.0
	design.beam = 5.6
	design.mass = 60000.0
	design.sail_area = 300.0
	# The headsail can't be sheeted much closer than this without fouling the shrouds.
	design.sail_angle_minimum = deg_to_rad(10.0)
	design.sail_angle_maximum = deg_to_rad(85.0)
	design.lift_maximum = 1.35
	design.stall_angle = deg_to_rad(20.0)
	design.parasitic_drag = 0.1
	design.induced_drag = 0.07
	design.windage_area = 18.0
	design.windage_center = 2.0
	design.headsail_fraction = 0.3
	design.headsail_center = 9.0
	design.backed_headsail_angle = deg_to_rad(35.0)
	design.wetted_area = 110.0
	design.lateral_area = 14.0
	design.lateral_lift_slope = 2.0
	design.turning_radius = 2.5
	design.yaw_response = 1.5
	design.heel_stiffness = 90000.0
	design.sail_handling_rate = 0.35
	design.trim_rate = deg_to_rad(60.0)
	design.masts = PackedFloat32Array([1.5])
	design.cargo_capacity = 30.0
	# Pirate sloops sailed crammed: a big crew wins boarding fights.
	design.crew_minimum = 8
	design.crew_maximum = 75
	design.price = 3000
	design.gun_ports = 10
	return design


## A two-masted square-rigged brig: heavier, faster off the wind, hopeless close to it.
static func brig() -> ShipDesign:
	var design := ShipDesign.new()
	design.id = "brig"
	design.display_name = "Brig"
	design.rig = Rig.SQUARE
	design.length_overall = 34.0
	design.waterline_length = 28.0
	design.beam = 9.0
	design.mass = 280000.0
	design.sail_area = 1000.0
	# Yards braced up to 55 degrees from square leave the sail 35 degrees off the centerline.
	design.sail_angle_minimum = deg_to_rad(35.0)
	design.sail_angle_maximum = deg_to_rad(90.0)
	design.lift_maximum = 1.05
	design.stall_angle = deg_to_rad(18.0)
	design.parasitic_drag = 0.12
	design.induced_drag = 0.1
	design.windage_area = 60.0
	design.windage_center = 3.0
	design.headsail_fraction = 0.45
	design.headsail_center = 7.0
	design.backed_headsail_angle = deg_to_rad(60.0)
	design.wetted_area = 380.0
	design.lateral_area = 40.0
	design.lateral_lift_slope = 1.5
	design.turning_radius = 3.5
	design.yaw_response = 3.0
	design.heel_stiffness = 500000.0
	design.sail_handling_rate = 0.15
	design.trim_rate = deg_to_rad(20.0)
	design.masts = PackedFloat32Array([7.0, -5.0])
	design.cargo_capacity = 150.0
	design.crew_minimum = 25
	design.crew_maximum = 140
	design.price = 14000
	design.gun_ports = 16
	return design


static func all() -> Array[ShipDesign]:
	return [sloop(), brig()]
