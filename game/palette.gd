class_name Palette
extends RefCounted
## Every color the game draws with. A small fixed palette is what keeps pixel art looking like
## one piece; add to it deliberately, never inline a color somewhere else.

# Water
const DEEP_WATER := Color("1d3b53")
const SWELL := Color("21465f")
const WATER := Color("24506b")
const RIPPLE := Color("2f6a85")
const FOAM := Color("cfe6ea")
const FOAM_FADING := Color("7fb0c0")

# The chart: coasts, shallows and land, seen from far above.
const SHALLOWS := Color("2e7b84")
const SHALLOWS_LIGHT := Color("3f9a96")
const SAND := Color("d9c58f")
const GRASS := Color("6f9a4a")
const FOREST := Color("4c7a3a")
const FOREST_DARK := Color("35592c")
const HIGHLAND := Color("6e6a45")

# Ships
const HULL := Color("5a3a29")
const HULL_SHADOW := Color("3b2519")
const DECK := Color("9a6b45")
const DECK_LIGHT := Color("b98a5c")
const SPAR := Color("6b4a33")
const SAIL := Color("efe6d2")
const SAIL_SHADOW := Color("c9bca0")

# Marks
const BUOY := Color("c8443a")
const BUOY_LIGHT := Color("f2f2f2")

# The player's colors: Itrium's pastel pink, with deep rose where it needs an edge.
const PLAYER := Color("febfca")
const PLAYER_EDGE := Color("c46475")

# Other ships' flags.
const NAVY := Color("4a6fb5")
const MERCHANT := Color("d9a441")

# Heads-up display, in Rhodonite.
const PANEL := Color("2b2b2b")
const TEXT := Color("f2f2f2")
const TEXT_MUTED := Color("aaaaaa")
