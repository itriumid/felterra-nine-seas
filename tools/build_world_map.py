"""Builds the Nusantara chart the game sails on, from Natural Earth's public-domain coastlines.

Usage:
    python3 tools/build_world_map.py <natural earth directory> world/nusantara.png

The directory holds these files from github.com/nvkelso/natural-earth-vector (geojson/):
ne_10m_land, ne_10m_minor_islands, ne_10m_bathymetry_K_200 and ne_10m_bathymetry_I_2000, each
ending in .geojson. The output is one pixel per kilometer, plate carree (accurate enough this
close to the equator):
    red:   255 on land, 0 at sea
    green: distance to the nearest coast in pixels, capped at 255, on both sides of it
    blue:  depth at sea: 0 on the continental shelf, 128 past 200 meters, 255 past 2,000
The game reads red for running aground, and all three for drawing.

Plain Python, no libraries, so anyone can rebuild the map.
"""

import json
import struct
import sys
import zlib

# Keep in step with simulation/chart.gd.
WEST, EAST = 95.0, 120.0
NORTH, SOUTH = 8.0, -9.0
KILOMETERS_PER_DEGREE_LONGITUDE = 111.32
KILOMETERS_PER_DEGREE_LATITUDE = 110.57
WIDTH = round((EAST - WEST) * KILOMETERS_PER_DEGREE_LONGITUDE)
HEIGHT = round((NORTH - SOUTH) * KILOMETERS_PER_DEGREE_LATITUDE)


def to_pixel(longitude, latitude):
    return (
        (longitude - WEST) * KILOMETERS_PER_DEGREE_LONGITUDE,
        (NORTH - latitude) * KILOMETERS_PER_DEGREE_LATITUDE,
    )


def polygons(path):
    with open(path) as file:
        collection = json.load(file)
    for feature in collection["features"]:
        geometry = feature["geometry"]
        if geometry["type"] == "Polygon":
            yield geometry["coordinates"]
        elif geometry["type"] == "MultiPolygon":
            yield from geometry["coordinates"]


def overlaps_chart(rings):
    longitudes = [point[0] for point in rings[0]]
    latitudes = [point[1] for point in rings[0]]
    return not (
        max(longitudes) < WEST or min(longitudes) > EAST
        or max(latitudes) < SOUTH or min(latitudes) > NORTH
    )


def fill(mask, rings):
    """Even-odd scanline fill of one polygon and its holes, sampled at pixel centers."""
    crossings = {}
    for ring in rings:
        points = [to_pixel(longitude, latitude) for longitude, latitude, *_ in ring]
        for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1]):
            if y0 == y1:
                continue
            if y0 > y1:
                x0, y0, x1, y1 = x1, y1, x0, y0
            first_row = max(int(y0 + 0.5 - 1e-9), 0)
            last_row = min(int(y1 - 0.5 + 1e-9), HEIGHT - 1)
            slope = (x1 - x0) / (y1 - y0)
            for row in range(first_row, last_row + 1):
                center = row + 0.5
                if y0 <= center < y1:
                    crossings.setdefault(row, []).append(x0 + (center - y0) * slope)
    for row, xs in crossings.items():
        xs.sort()
        for start, end in zip(xs[0::2], xs[1::2]):
            first = max(int(start + 0.5), 0)
            last = min(int(end - 0.5), WIDTH - 1)
            offset = row * WIDTH
            for column in range(first, last + 1):
                mask[offset + column] = 1


def coast_distances(mask):
    """Distance from every pixel to the nearest pixel on the other side of the coast.

    A chamfer distance (3 for a straight step, 4 for a diagonal one, in thirds of a pixel) in
    two sweeps: close to true distance, so bands along the coast come out rounded instead of
    in the squares and diamonds a simple step count makes.
    """
    unreached = 255 * 3
    distance = [unreached] * (WIDTH * HEIGHT)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            index = y * WIDTH + x
            here = mask[index]
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < WIDTH and 0 <= ny < HEIGHT and mask[ny * WIDTH + nx] != here:
                    distance[index] = 3
                    break
    forward = ((-1, -1, 4), (0, -1, 3), (1, -1, 4), (-1, 0, 3))
    backward = ((1, 1, 4), (0, 1, 3), (-1, 1, 4), (1, 0, 3))
    for neighbors, rows, columns in (
        (forward, range(HEIGHT), range(WIDTH)),
        (backward, range(HEIGHT - 1, -1, -1), range(WIDTH - 1, -1, -1)),
    ):
        for y in rows:
            for x in columns:
                index = y * WIDTH + x
                here = mask[index]
                best = distance[index]
                for dx, dy, cost in neighbors:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < WIDTH and 0 <= ny < HEIGHT:
                        neighbor = ny * WIDTH + nx
                        if mask[neighbor] == here and distance[neighbor] + cost < best:
                            best = distance[neighbor] + cost
                distance[index] = best
    return bytearray(min(round(value / 3), 255) for value in distance)


def write_png(path, mask, distance, depth):
    rows = bytearray()
    for y in range(HEIGHT):
        rows.append(0)
        for x in range(WIDTH):
            index = y * WIDTH + x
            rows += bytes((255 if mask[index] else 0, distance[index], depth[index]))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)
    with open(path, "wb") as file:
        file.write(b"\x89PNG\r\n\x1a\n")
        file.write(chunk(b"IHDR", header))
        file.write(chunk(b"IDAT", zlib.compress(bytes(rows), 9)))
        file.write(chunk(b"IEND", b""))


def rasterize(paths):
    mask = bytearray(WIDTH * HEIGHT)
    for path in paths:
        for rings in polygons(path):
            if overlaps_chart(rings):
                fill(mask, rings)
    return mask


def main():
    directory, output = sys.argv[1:]
    source = lambda name: f"{directory}/{name}.geojson"
    mask = rasterize([source("ne_10m_land"), source("ne_10m_minor_islands")])
    past_200 = rasterize([source("ne_10m_bathymetry_K_200")])
    past_2000 = rasterize([source("ne_10m_bathymetry_I_2000")])
    depth = bytearray(
        0 if mask[index] else (255 if past_2000[index] else (128 if past_200[index] else 0))
        for index in range(WIDTH * HEIGHT)
    )
    write_png(output, mask, coast_distances(mask), depth)
    land = sum(mask)
    print(f"{WIDTH} by {HEIGHT} pixels, {100 * land / len(mask):.1f}% land, written to {output}")


if __name__ == "__main__":
    main()
