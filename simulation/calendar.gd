class_name Calendar
extends RefCounted
## Game time as a date. There's no year: the seasons are what matter.

const SECONDS_PER_DAY := 86400.0
const DAYS_PER_YEAR := 365
const MONTHS: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]
const MONTH_LENGTHS: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

## Seconds since midnight on the first of January.
var seconds := 0.0


static func starting_on(day_of_year: int, hour: float) -> Calendar:
	var calendar := Calendar.new()
	calendar.seconds = day_of_year * SECONDS_PER_DAY + hour * 3600.0
	return calendar


func advance(delta: float) -> void:
	seconds += delta


## Day of the year, 0 to 364, with the fraction of the day.
func day_of_year() -> float:
	return fmod(seconds / SECONDS_PER_DAY, DAYS_PER_YEAR)


func date_text() -> String:
	var day := int(day_of_year())
	var month := 0
	while day >= MONTH_LENGTHS[month]:
		day -= MONTH_LENGTHS[month]
		month += 1
	var hour := fmod(seconds / 3600.0, 24.0)
	return "%d %s, %02d:%02d" % [day + 1, MONTHS[month], int(hour), int(fmod(hour, 1.0) * 60.0)]
