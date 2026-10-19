# Felterra: Nine Seas

A pirate sailing game set on Felterra, an Earth where cats are the apex species. Sailors have
seven seas and cats have nine lives, so a world of cats has nine seas.

Inspired by Tradewinds, but turned toward the pirate's side of the trade, and built around
sailing that behaves like the real thing: true and apparent wind, points of sail, ships that
can't sail into the wind, square-riggers that can't point as high as a sloop, and a bow wave
that won't let a hull go much past its hull speed.

**Status:** a prototype. The first of the nine seas (the Nusantara seas, from Aceh to Makassar)
in one view you can zoom from the whole chart to the deck, two ships, merchant and navy traffic,
and no cats yet.

## The world map

The chart is the real coastline and seafloor of the Nusantara seas, one kilometer to a pixel:
Sumatra, the Malay Peninsula, Java, Borneo and the islands between, the shallow Sunda Shelf,
and the deep water beyond it. The winds are the real monsoons. From December to March they
blow from the northeast north of the equator and from the northwest over the Java Sea; from
June to September they reverse; in between they're light and wander. The game starts at dawn
on the 15th of January in Batavia.

Click anywhere on the sea, or on a port, and your crew sails there: around the land and,
when the wind is against you, beating to windward. Press A or D (or the arrow keys) to take
the helm yourself; that cancels the course. Zoom with the mouse wheel or minus and equals, from
the whole chart down to the deck, where every ship is drawn at its true size with its sails set
to the real wind. The clock runs at an hour a second, the same for everyone.

Merchants trade between the ports and navy squadrons patrol their stations, all sailing the
same physics as you, so a merchant bound east into the July monsoon zigzags up the coast just
as a real one did. Sails within 20 kilometers are reported as sighted.

Click a ship to give chase. Close to 3 kilometers and a battle bubble opens: the view zooms in,
time inside runs four times faster than real, and the full sailing physics takes over. You
handle the rudder, sails and trim yourself; merchants run, using the wind as well as they can,
and hulls that meet collide with all the momentum they carry. Sail more than 6 kilometers clear
and the bubble closes. The world outside doesn't wait: a bubble's minutes are the world's
hours, as they'd have to be with other players sharing it.

Coastlines and depths come from [Natural Earth](https://www.naturalearthdata.com), which is
in the public domain. To rebuild the chart, download `ne_10m_land`, `ne_10m_minor_islands`,
`ne_10m_bathymetry_K_200` and `ne_10m_bathymetry_I_2000` from the `geojson` directory of
[natural-earth-vector](https://github.com/nvkelso/natural-earth-vector) into one directory, then:

```bash
python3 tools/build_world_map.py <that directory> world/nusantara.png
```

## Controls

| Keys and mouse | Gamepad | Does |
| --- | --- | --- |
| Click the sea or a port | | Your crew sails there |
| Click a ship | | Give chase |
| A and D, or the left and right arrows | Left stick | Take the helm and steer |
| Mouse wheel, or minus and equals | Up and down on the directional pad | Zoom |
| Tab | Back | Switch between the sloop and the brig |
| W and S (in a bubble) | Shoulder buttons | Set or take in sail |
| Q and E (in a bubble) | Triggers | Sheet in or ease the sails |
| T (in a bubble) | Y | Automatic or manual trim |
| Hold B (in a bubble) | X | Back the headsails, to get out of irons |
| F11 | | Full screen |
| H or F1 | Guide | Help |

## How the sailing works

The simulation lives in `simulation/` and doesn't depend on anything on screen:

- `wind.gd`: a trade wind from the east-northeast, with gusts that drift downwind and a
  direction that wanders.
- `ship.gd`: apparent wind, lift and drag on the sails, keel and hull resistance, heel, and a
  rudder that only works while water flows past it. The comment at the top walks through the
  model.
- `ship_design.gd`: the numbers that make a sloop a sloop and a brig a brig.
- `polar.gd`: each ship's steady speed at every angle to the wind.

Everything is in real units (meters, kilograms, newtons), stepped 60 times per second of game
time. Speeding up time runs more steps, never longer ones, so a ship sails the same at any
speed.

The views in `game/` draw the ships from the simulation instead of from sprites, onto a
640 by 360 screen scaled up by whole numbers, so the sails always show their real trim and
every pixel stays the same size.

## Development

```bash
# Run the tests (import once first on a fresh checkout)
godot --headless --path . --import
godot --headless --path . --script tests/run_tests.gd

# Print the speed polars, for tuning
godot --headless --path . --script tools/print_polar.gd

# Rebuild the polar table the world map sails by (after any change to the sailing model)
godot --headless --path . --script tools/build_polars.gd
```

The tests check behavior a sailor would recognize: the sloop's best angle upwind is about 45°,
the brig's about 60°, nothing sails into the wind, a stopped ship can't steer, and so on.

## License

The code is free software under the [GNU General Public License, version 3](LICENSE): you can
read it, change it and share it, and anything you build from it stays open too.

The names Felterra and Nine Seas, and the game's icon, aren't covered by that license. They're
how players know the game is ours, so please give a fork its own name.

The chart is built from [Natural Earth](https://www.naturalearthdata.com) data, which is in the
public domain.
