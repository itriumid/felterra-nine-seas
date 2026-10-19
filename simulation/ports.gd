class_name Ports
extends RefCounted
## Harbors of the Nusantara seas, at their historical positions and under their real names:
## Felterra is Earth, so its ports are Earth's.

const HARBORS: Array[Array] = [
	["Aceh", 5.56, 95.32],
	["Patani", 6.87, 101.25],
	["Malacca", 2.19, 102.25],
	["Singapura", 1.27, 103.85],
	["Palembang", -2.4, 104.9],
	["Banten", -6.0, 106.15],
	["Batavia", -6.1, 106.81],
	["Cirebon", -6.7, 108.56],
	["Semarang", -6.94, 110.42],
	["Surabaya", -7.2, 112.74],
	# Banjarmasin itself is up the Barito; ships reached it from the river mouth.
	["Banjarmasin", -3.5, 114.45],
	["Pontianak", -0.03, 109.2],
	["Kuching", 1.65, 110.4],
	["Brunei", 4.95, 114.9],
	["Makassar", -5.13, 119.38],
]


## Each harbor as {name, position}, moved onto the nearest water so a ship can reach it.
static func on(chart: Chart) -> Array[Dictionary]:
	var ports: Array[Dictionary] = []
	for harbor in HARBORS:
		var charted := Chart.position_of(harbor[1], harbor[2])
		ports.append({"name": harbor[0], "position": chart.nearest_water(charted)})
	return ports
