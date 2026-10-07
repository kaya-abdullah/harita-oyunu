#!/usr/bin/env python3
"""Generates the Africa tile map for Harita.

Real country outlines (tool/data/africa_geo.json, extracted from Natural
Earth by tool/extract_africa_geo.py) are rasterised onto a fine square grid.
Every land cell becomes one tiny territory ("minik kare") that belongs to the
country covering most of it. Real cities become bases, some cells hold
diamond mines, and 4-neighbour adjacency is computed (Madagascar is linked to
the mainland by a single sea bridge).

The country outlines are also exported in map world units so the game can
draw borders over the satellite picture.

The map background is NASA's Blue Marble (topography + bathymetry, Dec 2004,
public domain). It is plate carrée like this map, so a crop of it lines up
with the tiles exactly. Each tile's terrain (rain forest / savanna /
steppe / desert) is read from the picture's colours — it is shown to the
player but does not change the game.

Writes:
  assets/maps/territory_graph.json
  lib/infrastructure/map/territory_graph_data.dart
  assets/images/africa_satellite.jpg   (only when a Blue Marble path is given)

Usage:
  python3 tool/generate_africa_map.py [world.topo.bathy.200412.3x21600x10800.jpg]
(download: https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73909/
 world.topo.bathy.200412.3x21600x10800.jpg). Without the argument the
existing assets/images/africa_satellite.jpg is reused for terrain.
"""

import json
import math
import os
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CELL_DEG = 1.5  # grid resolution in degrees
TILE = 24.0  # world units per tile
SAMPLES = 4  # land samples per cell side
SAT_MARGIN = 3  # tiles of satellite picture around the grid on every side
SAT_PX_PER_DEG = 32  # satellite resolution kept in the game
SATELLITE = os.path.join(ROOT, "assets/images/africa_satellite.jpg")

# (lon, lat, type, capacity). The first seven are the start bases, in the
# order players are added: you, then bot 1 … bot 6.
BASES = [
    (-7.6, 33.6, "smallBase", 100),  # Casablanca — player start
    (18.6, -33.9, "smallBase", 100),  # Cape Town — bot 1
    (31.2, 30.0, "bigBase", 150),  # Cairo — bot 2
    (3.4, 6.5, "bigBase", 150),  # Lagos — bot 3
    (45.3, 2.1, "smallBase", 100),  # Mogadishu — bot 4
    (15.3, -4.3, "bigBase", 150),  # Kinshasa — bot 5
    (-17.2, 14.7, "smallBase", 100),  # Dakar — bot 6
    (36.8, -1.3, "bigBase", 150),  # Nairobi
    (28.0, -26.2, "bigBase", 150),  # Johannesburg
    (3.0, 36.7, "smallBase", 75),  # Algiers
    (13.2, 32.9, "smallBase", 75),  # Tripoli
    (32.5, 15.6, "smallBase", 75),  # Khartoum
    (38.7, 9.0, "smallBase", 75),  # Addis Ababa
    (-4.0, 5.3, "smallBase", 75),  # Abidjan
    (13.2, -8.8, "smallBase", 75),  # Luanda
    (39.3, -6.8, "smallBase", 75),  # Dar es Salaam
    (28.3, -15.4, "smallBase", 75),  # Lusaka
    (47.5, -18.9, "smallBase", 75),  # Antananarivo
    (-8.0, 12.6, "smallBase", 75),  # Bamako
    (15.0, 12.1, "smallBase", 75),  # N'Djamena
    (17.1, -22.6, "smallBase", 75),  # Windhoek
    (32.6, 0.3, "smallBase", 75),  # Kampala
]
START_COUNT = 7

# Diamond mines (lon, lat): real diamond fields plus a few more so every
# corner of the continent has one to fight over.
MINES = [
    (24.7, -24.6),  # Jwaneng, Botswana
    (25.4, -21.3),  # Orapa, Botswana
    (24.8, -28.7),  # Kimberley, South Africa
    (16.4, -28.3),  # Oranjemund, Namibia
    (32.4, -19.9),  # Marange, Zimbabwe
    (23.6, -6.1),  # Mbuji-Mayi, DR Congo
    (20.3, -9.4),  # Catoca, Angola
    (33.6, -3.6),  # Williamson, Tanzania
    (-11.0, 8.6),  # Kono, Sierra Leone
    (-6.7, 8.0),  # Séguéla, Côte d'Ivoire
    (-0.8, 6.0),  # Akwatia, Ghana
    (15.9, 4.9),  # Carnot, Central African Republic
    (-5.5, 31.5),  # Atlas, Morocco
    (33.5, 25.0),  # Eastern Desert, Egypt
    (5.5, 23.0),  # Hoggar, Algeria
    (8.0, 18.0),  # Aïr, Niger
    (-6.0, 15.0),  # Mali
    (38.5, 6.5),  # Ethiopia
    (46.5, -20.5),  # Madagascar
    (14.0, 27.0),  # Fezzan, Libya
    (29.0, 12.5),  # Kordofan, Sudan
    (11.5, -0.5),  # Gabon
]


def inside(poly, x, y):
    result = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            result = not result
        j = i
    return result


def main():
    geo = json.load(open(os.path.join(ROOT, "tool/data/africa_geo.json")))
    countries = geo["countries"]
    rings = [(key, ring) for key, rs in countries.items() for ring in rs]
    boxes = [
        (min(p[0] for p in r), max(p[0] for p in r),
         min(p[1] for p in r), max(p[1] for p in r))
        for _, r in rings
    ]

    def country_at(x, y):
        for (key, ring), (x0, x1, y0, y1) in zip(rings, boxes):
            if x0 <= x <= x1 and y0 <= y <= y1 and inside(ring, x, y):
                return key
        return None

    lons = [p[0] for _, r in rings for p in r]
    lats = [p[1] for _, r in rings for p in r]
    min_lon, max_lat = min(lons), max(lats)
    cols = math.ceil((max(lons) - min_lon) / CELL_DEG)
    rows = math.ceil((max_lat - min(lats)) / CELL_DEG)

    cells = {}
    for r in range(rows):
        for c in range(cols):
            lon0 = min_lon + c * CELL_DEG
            lat0 = max_lat - r * CELL_DEG
            votes = {}
            for a in range(SAMPLES):
                for b in range(SAMPLES):
                    k = country_at(lon0 + (a + 0.5) * CELL_DEG / SAMPLES,
                                   lat0 - (b + 0.5) * CELL_DEG / SAMPLES)
                    if k:
                        votes[k] = votes.get(k, 0) + 1
            if sum(votes.values()) >= 0.4 * SAMPLES * SAMPLES:
                region = max(sorted(votes), key=lambda k: votes[k])
                cells[(c, r)] = (lon0 + CELL_DEG / 2, lat0 - CELL_DEG / 2,
                                 region)

    def neighbours(cell, pool):
        c, r = cell
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c + d[0], r + d[1])
            if n in pool:
                yield n

    # Keep only connected components with at least 3 cells.
    seen = set()
    components = []
    for cell in sorted(cells, key=lambda k: (k[1], k[0])):
        if cell in seen:
            continue
        comp = []
        q = deque([cell])
        seen.add(cell)
        while q:
            cur = q.popleft()
            comp.append(cur)
            for n in neighbours(cur, cells):
                if n not in seen:
                    seen.add(n)
                    q.append(n)
        components.append(comp)
    components = [c for c in components if len(c) >= 3]
    components.sort(key=len, reverse=True)
    keep = set(cell for comp in components for cell in comp)
    cells = {k: v for k, v in cells.items() if k in keep}

    # Trim empty border rows / columns (and shift the outlines with them).
    c0 = min(c for c, _ in cells)
    r0 = min(r for _, r in cells)
    cells = {(c - c0, r - r0): v for (c, r), v in cells.items()}
    components = [[(c - c0, r - r0) for c, r in comp] for comp in components]
    cols = max(c for c, _ in cells) + 1
    rows = max(r for _, r in cells) + 1
    origin_lon = min_lon + c0 * CELL_DEG
    origin_lat = max_lat - r0 * CELL_DEG

    def to_world(lon, lat):
        return ((lon - origin_lon) / CELL_DEG * TILE,
                (origin_lat - lat) / CELL_DEG * TILE)

    ordered = sorted(cells, key=lambda k: (k[1], k[0]))
    index = {cell: i for i, cell in enumerate(ordered)}

    # Satellite picture covering the grid plus SAT_MARGIN tiles around it.
    sat_lon0 = origin_lon - SAT_MARGIN * CELL_DEG
    sat_lat0 = origin_lat + SAT_MARGIN * CELL_DEG
    sat_w_deg = (cols + 2 * SAT_MARGIN) * CELL_DEG
    sat_h_deg = (rows + 2 * SAT_MARGIN) * CELL_DEG
    if len(sys.argv) > 1:
        Image.MAX_IMAGE_PIXELS = None
        world = Image.open(sys.argv[1])
        ppd = world.width / 360
        box = (
            round((sat_lon0 + 180) * ppd),
            round((90 - sat_lat0) * ppd),
            round((sat_lon0 + sat_w_deg + 180) * ppd),
            round((90 - sat_lat0 + sat_h_deg) * ppd),
        )
        crop = world.crop(box).resize(
            (round(sat_w_deg * SAT_PX_PER_DEG), round(sat_h_deg * SAT_PX_PER_DEG)),
            Image.LANCZOS,
        )
        crop.convert("RGB").save(SATELLITE, quality=84, optimize=True,
                                 progressive=True)
    sat = Image.open(SATELLITE).convert("RGB")
    px_per_cell = sat.width / (cols + 2 * SAT_MARGIN)

    def terrain_of(cell):
        """Rain forest / woodland / savanna / steppe / desert, from the mean
        colour of the tile's land pixels (sea pixels are bluish)."""
        c, r = cell
        x0 = round((c + SAT_MARGIN) * px_per_cell)
        y0 = round((r + SAT_MARGIN) * px_per_cell)
        x1 = round((c + SAT_MARGIN + 1) * px_per_cell)
        y1 = round((r + SAT_MARGIN + 1) * px_per_cell)
        pixels = [
            p for p in sat.crop((x0, y0, x1, y1)).getdata()
            if not (p[2] > p[0] + 8 and p[2] >= p[1])
        ] or list(sat.crop((x0, y0, x1, y1)).getdata())
        rr = sum(p[0] for p in pixels) / len(pixels)
        gg = sum(p[1] for p in pixels) / len(pixels)
        light = (rr + gg + sum(p[2] for p in pixels) / len(pixels)) / 3
        if light < 45 and gg > rr:
            return "rainforest"
        if light < 75 and gg >= rr * 0.97:
            return "woodland"
        if light < 100:
            return "savanna"
        if light < 125:
            return "steppe"
        return "desert"

    adjacency = {i: set() for i in range(len(ordered))}
    for cell in ordered:
        for n in neighbours(cell, cells):
            adjacency[index[cell]].add(index[n])

    # Bridge every extra component (Madagascar) to its nearest mainland cell.
    mainland = set(components[0])
    for comp in components[1:]:
        best = None
        for a in comp:
            for b in mainland:
                d = (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2
                if best is None or d < best[0]:
                    best = (d, a, b)
        _, a, b = best
        adjacency[index[a]].add(index[b])
        adjacency[index[b]].add(index[a])

    def nearest_cell(lon, lat, taken):
        return min(
            (cell for cell in ordered if cell not in taken),
            key=lambda k: (cells[k][0] - lon) ** 2 + (cells[k][1] - lat) ** 2,
        )

    base_of = {}
    for lon, lat, typ, cap in BASES:
        base_of[nearest_cell(lon, lat, base_of)] = (typ, cap)
    start_ids = [index[c] for c in list(base_of)[:START_COUNT]]

    mines = set()
    for lon, lat in MINES:
        mines.add(nearest_cell(lon, lat, set(base_of) | mines))

    territories = []
    for cell in ordered:
        i = index[cell]
        typ, cap = base_of.get(cell, ("normal", None))
        t = {
            "id": i,
            "nameKey": "region_" + cells[cell][2],
            "type": typ,
            "adjacentIds": sorted(adjacency[i]),
            "baseCapacity": cap,
            "col": cell[0],
            "row": cell[1],
        }
        t["terrain"] = terrain_of(cell)
        if cell in mines:
            t["diamondMine"] = True
        territories.append(t)

    outlines = {}
    for key, rs in countries.items():
        outlines[key] = [
            [round(v, 1) for p in ring for v in to_world(*p)] for ring in rs
        ]

    lines = ["{"]
    lines.append(f'  "cols": {cols},')
    lines.append(f'  "rows": {rows},')
    lines.append(f'  "tileSize": {TILE},')
    lines.append(f'  "satelliteMargin": {SAT_MARGIN},')
    lines.append(f'  "startIds": {json.dumps(start_ids)},')
    lines.append('  "territories": [')
    for i, t in enumerate(territories):
        comma = "," if i < len(territories) - 1 else ""
        lines.append("    " + json.dumps(t, ensure_ascii=False) + comma)
    lines.append("  ],")
    lines.append('  "outlines": {')
    keys = sorted(outlines)
    for i, key in enumerate(keys):
        comma = "," if i < len(keys) - 1 else ""
        lines.append(f'    "{key}": ' + json.dumps(outlines[key],
                                                    separators=(",", ":"))
                     + comma)
    lines.append("  }")
    lines.append("}")
    text = "\n".join(lines) + "\n"

    with open(os.path.join(ROOT, "assets/maps/territory_graph.json"), "w") as f:
        f.write(text)

    dart = (
        "/// Embedded copy of `assets/maps/territory_graph.json`.\n"
        "///\n"
        "/// Generated by `tool/generate_africa_map.py` — do not edit by hand.\n"
        "/// Allows [TerritoryGraph.bundled] to build the map synchronously (e.g.\n"
        "/// when creating a new game's initial state). A test verifies both\n"
        "/// copies are identical.\n"
        "library;\n\n"
        "const String kTerritoryGraphJson = r'''\n" + text + "''';\n"
    )
    with open(
        os.path.join(ROOT, "lib/infrastructure/map/territory_graph_data.dart"),
        "w",
    ) as f:
        f.write(dart)

    regions = sorted(set(t["nameKey"] for t in territories))
    print(f"grid {cols}x{rows}, {len(territories)} tiles, "
          f"{len(components)} components, {len(regions)} regions, "
          f"{len(mines)} mines, starts {start_ids}")
    starts = set(ordered[i] for i in start_ids)
    for r in range(rows):
        print("".join(
            ("S" if (c, r) in starts else "B" if (c, r) in base_of
             else "D" if (c, r) in mines else "#") if (c, r) in cells else "."
            for c in range(cols)
        ))
    terrains = {}
    for t in territories:
        terrains[t["terrain"]] = terrains.get(t["terrain"], 0) + 1
    print("terrain:", terrains, "satellite:", sat.size)
    for r in range(rows):
        print("".join(
            {"rainforest": "F", "woodland": "w", "desert": ".", "steppe": ":",
             "savanna": "s"}[
                territories[index[(c, r)]]["terrain"]] if (c, r) in cells
            else " " for c in range(cols)
        ))
    missing = sorted(set("region_" + k for k in countries) - set(regions))
    if missing:
        print("countries without tiles:", missing)


if __name__ == "__main__":
    main()
