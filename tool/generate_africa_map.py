#!/usr/bin/env python3
"""Generates the Africa tile map for Harita.

Rasterises a simplified Africa (+ Madagascar) coastline onto a square grid.
Every land cell becomes one territory ("minik kare"). Cells are assigned to
the nearest country anchor (nameKey `region_<country>`), real cities become
bases, and 4-neighbour adjacency is computed (Madagascar is linked to the
mainland by a single sea bridge).

Writes:
  assets/maps/territory_graph.json
  lib/infrastructure/map/territory_graph_data.dart

Usage: python3 tool/generate_africa_map.py
"""

import json
import math
import os
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CELL_DEG = 3.4  # grid resolution in degrees
TILE = 24.0  # world units per tile

# Simplified coastline (lon, lat), clockwise from Tangier.
AFRICA = [
    (-5.9, 35.8), (-2.0, 35.1), (3.0, 36.8), (10.2, 37.2), (11.0, 35.0),
    (10.1, 33.9), (11.5, 33.1), (15.2, 32.3), (19.0, 30.3), (20.1, 32.1),
    (23.0, 32.6), (25.0, 31.6), (29.9, 31.2), (32.3, 31.3), (32.6, 29.9),
    (35.5, 24.0), (37.2, 19.6), (39.5, 15.5), (43.3, 12.5), (43.1, 11.6),
    (51.2, 11.8), (51.0, 10.4), (49.0, 6.0), (45.3, 2.0), (42.0, -1.0),
    (40.0, -3.0), (39.3, -6.8), (40.5, -10.5), (40.6, -15.0), (37.0, -17.8),
    (35.3, -22.0), (35.5, -24.0), (32.6, -25.9), (32.9, -28.5), (31.0, -29.9),
    (27.9, -33.0), (25.6, -33.9), (20.0, -34.8), (18.4, -34.3), (18.4, -33.9),
    (17.9, -31.0), (16.5, -28.6), (15.2, -26.6), (14.5, -22.9), (13.2, -20.0),
    (11.8, -17.2), (12.0, -15.0), (13.6, -12.4), (13.2, -8.8), (12.2, -6.0),
    (12.0, -5.0), (9.6, -1.0), (9.4, 0.4), (9.8, 3.0), (9.0, 4.0),
    (8.5, 4.5), (6.0, 4.3), (3.4, 6.4), (1.2, 6.1), (-0.2, 5.5),
    (-2.0, 4.8), (-4.0, 5.2), (-7.5, 4.4), (-9.0, 5.0), (-10.8, 6.3),
    (-13.2, 8.5), (-15.0, 10.9), (-16.7, 12.5), (-17.5, 14.7), (-16.5, 16.5),
    (-16.0, 18.0), (-17.0, 21.0), (-16.0, 23.7), (-14.5, 26.0), (-13.2, 27.7),
    (-10.0, 29.0), (-9.8, 31.5), (-8.6, 33.3), (-6.8, 34.0),
]

MADAGASCAR = [
    (49.3, -12.0), (50.5, -15.5), (49.8, -17.0), (48.4, -21.0), (47.1, -24.9),
    (45.2, -25.5), (43.7, -23.5), (43.3, -21.5), (44.4, -19.5), (44.0, -17.0),
    (44.4, -16.2), (46.3, -15.7), (47.9, -13.6),
]

# (key, lon, lat) — nearest anchor wins.
REGIONS = [
    ("morocco", -7.0, 31.0), ("algeria", 3.0, 28.0), ("tunisia", 9.5, 34.0),
    ("libya", 17.0, 27.0), ("egypt", 30.0, 26.0), ("mauritania", -11.0, 20.0),
    ("mali", -2.0, 17.0), ("niger", 9.0, 17.0), ("chad", 18.5, 15.0),
    ("sudan", 30.0, 16.0), ("ethiopia", 39.0, 9.0), ("somalia", 46.0, 5.0),
    ("senegal", -14.5, 14.0), ("guinea", -10.0, 10.0),
    ("ivory_coast", -5.5, 7.5), ("ghana", -1.0, 8.0), ("nigeria", 8.0, 9.5),
    ("cameroon", 12.5, 5.0), ("central_africa", 20.5, 6.5),
    ("south_sudan", 30.0, 7.0), ("gabon", 11.5, -1.0), ("congo", 23.0, -3.0),
    ("kenya", 37.5, 0.5), ("tanzania", 35.0, -6.0), ("angola", 17.5, -12.0),
    ("zambia", 27.5, -14.0), ("mozambique", 36.0, -17.0),
    ("namibia", 17.0, -22.0), ("botswana", 24.0, -22.0),
    ("zimbabwe", 30.0, -19.0), ("south_africa", 24.0, -30.0),
    ("madagascar", 46.5, -19.0),
]

# (lon, lat, type, capacity). The first and last entries are the start bases.
BASES = [
    (-7.6, 33.6, "smallBase", 100),  # Casablanca — player start
    (18.4, -33.9, "smallBase", 100),  # Cape Town — bot start
    (31.2, 30.0, "bigBase", 150),  # Cairo
    (3.4, 6.5, "bigBase", 150),  # Lagos
    (15.3, -4.3, "bigBase", 150),  # Kinshasa
    (36.8, -1.3, "bigBase", 150),  # Nairobi
    (28.0, -26.2, "bigBase", 150),  # Johannesburg
    (3.0, 36.7, "smallBase", 75),  # Algiers
    (13.2, 32.9, "smallBase", 75),  # Tripoli
    (-17.4, 14.7, "smallBase", 75),  # Dakar
    (32.5, 15.6, "smallBase", 75),  # Khartoum
    (38.7, 9.0, "smallBase", 75),  # Addis Ababa
    (-4.0, 5.3, "smallBase", 75),  # Abidjan
    (13.2, -8.8, "smallBase", 75),  # Luanda
    (39.3, -6.8, "smallBase", 75),  # Dar es Salaam
    (28.3, -15.4, "smallBase", 75),  # Lusaka
    (47.5, -18.9, "smallBase", 75),  # Antananarivo
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


def land_fraction(lon0, lat0):
    hits = 0
    n = 4
    for a in range(n):
        for b in range(n):
            x = lon0 + (a + 0.5) * CELL_DEG / n
            y = lat0 - (b + 0.5) * CELL_DEG / n
            if inside(AFRICA, x, y) or inside(MADAGASCAR, x, y):
                hits += 1
    return hits / (n * n)


def main():
    lons = [p[0] for p in AFRICA + MADAGASCAR]
    lats = [p[1] for p in AFRICA + MADAGASCAR]
    min_lon, max_lon = min(lons), max(lons)
    min_lat, max_lat = min(lats), max(lats)
    cols = math.ceil((max_lon - min_lon) / CELL_DEG)
    rows = math.ceil((max_lat - min_lat) / CELL_DEG)

    cells = {}
    for r in range(rows):
        for c in range(cols):
            lon0 = min_lon + c * CELL_DEG
            lat0 = max_lat - r * CELL_DEG
            if land_fraction(lon0, lat0) >= 0.4:
                cells[(c, r)] = (lon0 + CELL_DEG / 2, lat0 - CELL_DEG / 2)

    # Keep only connected components with at least 3 cells.
    def neighbours(cell):
        c, r = cell
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c + d[0], r + d[1])
            if n in cells:
                yield n

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
            for n in neighbours(cur):
                if n not in seen:
                    seen.add(n)
                    q.append(n)
        components.append(comp)
    components = [c for c in components if len(c) >= 3]
    components.sort(key=len, reverse=True)
    keep = set(cell for comp in components for cell in comp)
    cells = {k: v for k, v in cells.items() if k in keep}

    # Trim empty border rows / columns.
    c0 = min(c for c, _ in cells)
    r0 = min(r for _, r in cells)
    cells = {(c - c0, r - r0): v for (c, r), v in cells.items()}
    components = [[(c - c0, r - r0) for c, r in comp] for comp in components]
    cols = max(c for c, _ in cells) + 1
    rows = max(r for _, r in cells) + 1

    # Re-index in reading order (top-left → bottom-right).
    ordered = sorted(cells, key=lambda k: (k[1], k[0]))
    index = {cell: i for i, cell in enumerate(ordered)}

    adjacency = {i: set() for i in range(len(ordered))}
    for cell in ordered:
        for n in neighbours(cell):
            if n in index:
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

    def region_of(lon, lat):
        return min(
            REGIONS, key=lambda r: (r[1] - lon) ** 2 + (r[2] - lat) ** 2
        )[0]

    def nearest_cell(lon, lat, taken):
        return min(
            (cell for cell in ordered if cell not in taken),
            key=lambda k: (cells[k][0] - lon) ** 2 + (cells[k][1] - lat) ** 2,
        )

    base_of = {}
    for lon, lat, typ, cap in BASES:
        cell = nearest_cell(lon, lat, base_of)
        base_of[cell] = (typ, cap)

    territories = []
    for cell in ordered:
        i = index[cell]
        lon, lat = cells[cell]
        typ, cap = base_of.get(cell, ("normal", None))
        territories.append({
            "id": i,
            "nameKey": "region_" + region_of(lon, lat),
            "type": typ,
            "adjacentIds": sorted(adjacency[i]),
            "baseCapacity": cap,
            "col": cell[0],
            "row": cell[1],
            "x": cell[0] * TILE + TILE / 2,
            "y": cell[1] * TILE + TILE / 2,
        })

    player_start = index[nearest_cell(BASES[0][0], BASES[0][1], set())]
    bot_start = index[nearest_cell(BASES[1][0], BASES[1][1], set())]

    data = {
        "cols": cols,
        "rows": rows,
        "tileSize": TILE,
        "playerStartId": player_start,
        "botStartId": bot_start,
        "territories": territories,
    }

    lines = ["{"]
    for key in ("cols", "rows", "tileSize", "playerStartId", "botStartId"):
        lines.append(f'  "{key}": {json.dumps(data[key])},')
    lines.append('  "territories": [')
    for i, t in enumerate(territories):
        comma = "," if i < len(territories) - 1 else ""
        lines.append("    " + json.dumps(t, ensure_ascii=False) + comma)
    lines.append("  ]")
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
          f"player start {player_start}, bot start {bot_start}")
    for r in range(rows):
        print("".join(
            ("B" if (c, r) in base_of else "#") if (c, r) in cells else "."
            for c in range(cols)
        ))


if __name__ == "__main__":
    main()
