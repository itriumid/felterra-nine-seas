class_name Goods
extends RefCounted
## What the Nusantara seas traded around 1700, with a typical price per ton in reals: the
## Spanish silver coin that Asian trade ran on. Each port's market moves its own prices around
## these by supply and demand.

const CATALOG: Array[Array] = [
	# Identifier, name, typical price per ton.
	["rice", "Rice", 25],
	["salt", "Salt", 15],
	["timber", "Teak", 30],
	["sugar", "Sugar", 70],
	["tin", "Tin", 140],
	["pepper", "Pepper", 180],
	["cloth", "Indian cloth", 260],
	["porcelain", "Porcelain", 380],
	["spices", "Cloves and nutmeg", 900],
]


static func ids() -> Array[String]:
	var all: Array[String] = []
	for good in CATALOG:
		all.append(good[0])
	return all


static func display_name(id: String) -> String:
	for good in CATALOG:
		if good[0] == id:
			return good[1]
	return id


static func typical_price(id: String) -> float:
	for good in CATALOG:
		if good[0] == id:
			return good[2]
	return 0.0
