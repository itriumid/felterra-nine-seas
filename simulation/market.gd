class_name Market
extends RefCounted
## One port's market. Each good has a stock in the port's warehouses, and its price rises as the
## stock runs low and falls as it piles up. Buying and selling move the stock, and with it the
## price, so a good trade gets worse the more of it you do; over the following days stocks
## drift back to where they settle.
##
## Where they settle comes from geography: a good costs what it costs where it's produced, plus
## the cost of carrying it to this port by sea. So neighboring ports keep close prices, as
## merchants hopping between them would make them, and the money is in the long hauls.

## The stock, in tons, at which a good sells at its typical price.
const TYPICAL_STOCK := 150.0
## A good's price where it's produced, against its typical price.
const PRODUCER_PRICE := 0.5
## How much carrying a good a thousand kilometers by sea adds to its price, as a share of the
## producer's price: freight, wages, risk and the merchant's due.
const MARKUP_PER_THOUSAND_KILOMETERS := 0.6
## A little more where a good is especially wanted.
const WANTED_PREMIUM := 1.15
## Days for a stock to get most of the way back to where it settles.
const RECOVERY_DAYS := 10.0
## A merchant's margin: buy from the port above its price, sell to it below.
const MARGIN := 0.05
const LOWEST_PRICE := 0.35
const HIGHEST_PRICE := 3.0

var stock := {}
var settled := {}


## A market whose stocks settle where they give these prices, by good identifier.
func _init(settled_prices: Dictionary) -> void:
	for id in Goods.ids():
		var ratio: float = Goods.typical_price(id) / settled_prices[id]
		settled[id] = TYPICAL_STOCK * ratio * ratio
		stock[id] = settled[id]


## Where a good's price settles at a port: from the cheapest producer, counting the carrying.
## Distances are in meters, by "port>port" key.
static func regional_price(id: String, port: Dictionary, ports: Array[Dictionary], distances: Dictionary) -> float:
	var producer_price := Goods.typical_price(id) * PRODUCER_PRICE
	var best := INF
	for producer in ports:
		if not id in producer.produces:
			continue
		var meters: float = 0.0 if producer == port else distances.get("%s>%s" % [producer.name, port.name], INF)
		best = minf(best, producer_price * (1.0 + MARKUP_PER_THOUSAND_KILOMETERS * meters / 1000000.0))
	if id in port.wants:
		best *= WANTED_PREMIUM
	return clampf(best, Goods.typical_price(id) * LOWEST_PRICE, Goods.typical_price(id) * HIGHEST_PRICE)


## The port's price for a ton at its present stock, before the margin.
func price(id: String) -> float:
	return _price_at(id, stock[id])


## What the port charges for the next ton, and what it pays for one.
func buying_price(id: String) -> float:
	return price(id) * (1.0 + MARGIN)


func selling_price(id: String) -> float:
	return price(id) * (1.0 - MARGIN)


## What buying some tons would cost, ton by ton as the price climbs. Each ton is priced at the
## middle of the stock it moves through, so buying and selling the same tons back costs exactly
## the margin both ways.
func cost_to_buy(id: String, tons: int) -> float:
	var total := 0.0
	for ton in tons:
		total += _price_at(id, stock[id] - ton - 0.5) * (1.0 + MARGIN)
	return total


## What selling some tons would bring, ton by ton as the price falls.
func proceeds_from_selling(id: String, tons: int) -> float:
	var total := 0.0
	for ton in tons:
		total += _price_at(id, stock[id] + ton + 0.5) * (1.0 - MARGIN)
	return total


func take(id: String, tons: int) -> void:
	stock[id] -= tons


func put(id: String, tons: int) -> void:
	stock[id] += tons


## Stocks drift back toward where they settle as the days pass.
func advance(seconds: float) -> void:
	var days := seconds / Calendar.SECONDS_PER_DAY
	var drift := 1.0 - exp(-days / RECOVERY_DAYS)
	for id in stock:
		stock[id] += (settled[id] - stock[id]) * drift


func _price_at(id: String, tons_in_stock: float) -> float:
	var scarcity := sqrt(TYPICAL_STOCK / maxf(tons_in_stock, 1.0))
	return Goods.typical_price(id) * clampf(scarcity, LOWEST_PRICE, HIGHEST_PRICE)
