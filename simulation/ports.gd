class_name Ports
extends RefCounted
## Harbors of the Nusantara seas, at their historical positions and under their real names:
## Felterra is Earth, so its ports are Earth's. What each produced and wanted follows the
## trade of around 1700, simplified.

const HARBORS: Array[Array] = [
	# Name, latitude, longitude, goods it produces, goods it wants.
	["Aceh", 5.56, 95.32, ["pepper"], ["cloth", "porcelain", "rice"]],
	["Patani", 6.87, 101.25, ["porcelain"], ["pepper", "cloth"]],
	["Malacca", 2.19, 102.25, ["cloth", "tin"], ["pepper", "spices", "sugar"]],
	["Singapura", 1.27, 103.85, ["timber"], ["rice", "salt", "cloth"]],
	["Palembang", -2.4, 104.9, ["tin", "pepper"], ["cloth", "salt", "rice"]],
	["Banten", -6.0, 106.15, ["pepper"], ["cloth", "porcelain", "rice"]],
	["Batavia", -6.1, 106.81, ["porcelain", "sugar"], ["pepper", "spices", "tin", "timber", "rice"]],
	["Cirebon", -6.7, 108.56, ["rice", "salt"], ["cloth", "porcelain"]],
	["Semarang", -6.94, 110.42, ["timber", "rice"], ["cloth", "salt"]],
	["Surabaya", -7.2, 112.74, ["salt", "rice"], ["cloth", "porcelain", "timber"]],
	# Banjarmasin itself is up the Barito; ships reached it from the river mouth.
	["Banjarmasin", -3.5, 114.45, ["pepper"], ["salt", "rice", "cloth"]],
	["Pontianak", -0.03, 109.2, ["timber"], ["salt", "rice", "cloth"]],
	["Kuching", 1.65, 110.4, ["timber"], ["salt", "cloth", "rice"]],
	["Brunei", 4.95, 114.9, ["timber"], ["cloth", "rice", "porcelain"]],
	["Makassar", -5.13, 119.38, ["spices", "rice"], ["cloth", "porcelain", "tin"]],
]


## Each harbor as {name, position, produces, wants}, moved onto the nearest water so a ship
## can reach it.
static func on(chart: Chart) -> Array[Dictionary]:
	var ports: Array[Dictionary] = []
	for harbor in HARBORS:
		var charted := Chart.position_of(harbor[1], harbor[2])
		ports.append({
			"name": harbor[0], "position": chart.nearest_water(charted),
			"produces": harbor[3], "wants": harbor[4],
		})
	return ports
