#!/usr/bin/env python3
"""Generates the Africa city map for Harita.

Africa is divided into regions, one around each real city: the Voronoi cell
of every city is clipped to the real coastline (tool/data/africa_geo.json,
extracted from Natural Earth by tool/extract_africa_geo.py). Regions that
share a border are neighbours; Madagascar is linked to the mainland by a
single sea route. Country borders are not used any more — the cities are
the "countries" of the game.

Every region keeps its outline (in map world units) so the game can draw the
line around each army's land. Some cities are gold mines (the big capitals),
some regions hold diamond mines and three are forests.

The map background is NASA's Blue Marble (topography + bathymetry, Dec 2004,
public domain). It is plate carrée like this map, so a crop of it lines up
with the regions exactly. The world coordinate frame (TILE units per
CELL_DEG degrees, origin and size) is the same as the old tile map, so the
existing assets/images/africa_satellite.jpg keeps fitting.

Writes:
  assets/maps/territory_graph.json
  lib/infrastructure/map/territory_graph_data.dart
  assets/images/africa_satellite.jpg   (only when a Blue Marble path is given)

Usage:
  python3 tool/generate_africa_map.py [world.topo.bathy.200412.3x21600x10800.jpg]
(download: https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73909/
 world.topo.bathy.200412.3x21600x10800.jpg). Needs shapely and scipy.
"""

import json
import math
import os
import sys
from collections import deque

import numpy as np
from PIL import Image
from scipy.spatial import Voronoi
from shapely.geometry import MultiPolygon, Point, Polygon
from shapely.ops import nearest_points, unary_union

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CELL_DEG = 1.5  # degrees per world "tile" (frame of the satellite picture)
TILE = 24.0  # world units per CELL_DEG
SAMPLES = 4  # land samples per cell side (frame computation)
SAT_MARGIN = 3  # tiles of satellite picture around the map on every side
SAT_PX_PER_DEG = 32  # satellite resolution kept in the game
SATELLITE = os.path.join(ROOT, "assets/images/africa_satellite.jpg")
MIN_ISLAND_DEG2 = 4.0  # smaller islands (Canaries, Zanzibar…) are dropped
SIMPLIFY_DEG = 0.12  # outline simplification tolerance
MIN_SHARED_BORDER_DEG = 0.25  # shorter contacts do not make neighbours

# (lon, lat, Turkish name, English name, kind). kind: "gold" = gold mine
# (a big capital, pays out when captured), "" = ordinary city.
CITIES = [
    # ── North-west ──
    (-7.6, 33.6, "Kazablanka", "Casablanca", "gold"),
    (-6.8, 34.0, "Rabat", "Rabat", ""),
    (-5.0, 34.0, "Fas", "Fez", ""),
    (-8.0, 31.6, "Marakeş", "Marrakesh", ""),
    (-5.8, 35.8, "Tanca", "Tangier", ""),
    (-9.6, 30.4, "Agadir", "Agadir", ""),
    (-1.9, 34.7, "Ujda", "Oujda", ""),
    (-13.2, 27.15, "Layun", "Laayoune", ""),
    (-15.9, 23.7, "Dahla", "Dakhla", ""),
    (3.06, 36.75, "Cezayir", "Algiers", "gold"),
    (-0.63, 35.7, "Vahran", "Oran", ""),
    (6.6, 36.4, "Konstantin", "Constantine", ""),
    (5.5, 22.8, "Temenrasat", "Tamanrasset", ""),
    (3.7, 32.5, "Gardaya", "Ghardaia", ""),
    (-2.2, 31.6, "Beşar", "Bechar", ""),
    (-0.3, 27.9, "Adrar", "Adrar", ""),
    (2.5, 27.2, "Ayn Salih", "In Salah", ""),
    (8.5, 26.5, "İllizi", "Illizi", ""),
    (10.2, 36.8, "Tunus", "Tunis", ""),
    (9.5, 30.1, "Gadames", "Ghadames", ""),
    # ── Libya, Egypt ──
    (13.2, 32.9, "Trablus", "Tripoli", "gold"),
    (20.1, 32.1, "Bingazi", "Benghazi", ""),
    (16.6, 31.2, "Sirte", "Sirte", ""),
    (14.4, 27.0, "Sebha", "Sabha", ""),
    (23.3, 24.2, "Kufra", "Kufra", ""),
    (31.2, 30.0, "Kahire", "Cairo", "gold"),
    (29.9, 31.2, "İskenderiye", "Alexandria", ""),
    (32.9, 24.1, "Asvan", "Aswan", ""),
    (25.5, 29.2, "Siva", "Siwa", ""),
    (30.5, 25.4, "Harga", "Kharga", ""),
    # ── Sahel and West Africa ──
    (-15.98, 18.1, "Nuakşot", "Nouakchott", ""),
    (-13.05, 20.5, "Atar", "Atar", ""),
    (-7.25, 16.6, "Nema", "Nema", ""),
    (-17.4, 14.7, "Dakar", "Dakar", ""),
    (-11.4, 14.45, "Kayes", "Kayes", ""),
    (-8.0, 12.6, "Bamako", "Bamako", ""),
    (-3.0, 16.8, "Timbuktu", "Timbuktu", ""),
    (-0.04, 16.3, "Gao", "Gao", ""),
    (1.4, 18.4, "Kidal", "Kidal", ""),
    (2.1, 13.5, "Niamey", "Niamey", ""),
    (8.0, 17.0, "Agadez", "Agadez", ""),
    (9.0, 13.8, "Zinder", "Zinder", ""),
    (12.9, 18.7, "Bilma", "Bilma", ""),
    (15.0, 12.1, "Encamena", "N'Djamena", ""),
    (19.1, 17.9, "Faya", "Faya", ""),
    (20.8, 13.8, "Abeşe", "Abeche", ""),
    (16.1, 8.6, "Mundu", "Moundou", ""),
    (-13.7, 9.5, "Konakri", "Conakry", ""),
    (-10.8, 6.3, "Monrovia", "Monrovia", ""),
    (-4.0, 5.3, "Abidjan", "Abidjan", ""),
    (-1.5, 12.4, "Vagadugu", "Ouagadougou", ""),
    (-0.2, 5.6, "Akra", "Accra", ""),
    (-0.85, 9.4, "Tamale", "Tamale", ""),
    (3.4, 6.5, "Lagos", "Lagos", "gold"),
    (7.5, 9.1, "Abuja", "Abuja", ""),
    (8.5, 12.0, "Kano", "Kano", ""),
    (13.2, 11.8, "Maiduguri", "Maiduguri", ""),
    (7.0, 4.8, "Port Harcourt", "Port Harcourt", ""),
    # ── Sudan, Horn of Africa ──
    (32.5, 15.6, "Hartum", "Khartoum", "gold"),
    (37.2, 19.6, "Port Sudan", "Port Sudan", ""),
    (30.5, 19.2, "Dongola", "Dongola", ""),
    (25.35, 13.6, "El Faşir", "El Fasher", ""),
    (30.2, 13.2, "El Obeyd", "El Obeid", ""),
    (36.4, 15.45, "Kassala", "Kassala", ""),
    (31.6, 4.85, "Cuba", "Juba", ""),
    (28.0, 7.7, "Vau", "Wau", ""),
    (31.65, 9.5, "Malakal", "Malakal", ""),
    (38.9, 15.3, "Asmara", "Asmara", ""),
    (38.7, 9.0, "Addis Ababa", "Addis Ababa", "gold"),
    (37.5, 12.6, "Gondar", "Gondar", ""),
    (43.1, 11.6, "Cibuti", "Djibouti", ""),
    (43.6, 5.95, "Gode", "Gode", ""),
    (45.3, 2.1, "Mogadişu", "Mogadishu", ""),
    (44.1, 9.6, "Hargeysa", "Hargeisa", ""),
    (49.2, 11.3, "Bosaso", "Bosaso", ""),
    (47.4, 6.8, "Galkayo", "Galkayo", ""),
    (42.5, -0.35, "Kismayo", "Kismayo", ""),
    # ── Central Africa ──
    (9.7, 4.05, "Duala", "Douala", ""),
    (11.5, 3.85, "Yaunde", "Yaounde", ""),
    (13.4, 9.3, "Garua", "Garoua", ""),
    (18.6, 4.4, "Bangui", "Bangui", ""),
    (22.0, 6.5, "Bria", "Bria", ""),
    (9.45, 0.4, "Librevil", "Libreville", ""),
    (13.6, -1.6, "Franceville", "Franceville", ""),
    (11.9, -4.8, "Pointe-Noire", "Pointe-Noire", ""),
    (16.0, 1.6, "Ouesso", "Ouesso", ""),
    (15.3, -4.3, "Kinşasa", "Kinshasa", "gold"),
    (18.3, 0.05, "Mbandaka", "Mbandaka", ""),
    (25.2, 0.5, "Kisangani", "Kisangani", ""),
    (30.25, 1.55, "Bunia", "Bunia", ""),
    (29.2, -1.7, "Goma", "Goma", ""),
    (22.4, -5.9, "Kananga", "Kananga", ""),
    (25.9, -2.95, "Kindu", "Kindu", ""),
    (27.5, -11.7, "Lubumbaşi", "Lubumbashi", ""),
    (29.2, -5.9, "Kalemie", "Kalemie", ""),
    (19.0, -5.0, "Kikvit", "Kikwit", ""),
    # ── East Africa ──
    (32.6, 0.3, "Kampala", "Kampala", ""),
    (36.8, -1.3, "Nairobi", "Nairobi", "gold"),
    (39.7, -4.0, "Mombasa", "Mombasa", ""),
    (35.6, 3.1, "Lodvar", "Lodwar", ""),
    (39.6, -0.45, "Garissa", "Garissa", ""),
    (39.3, -6.8, "Darüsselam", "Dar es Salaam", ""),
    (35.7, -6.2, "Dodoma", "Dodoma", ""),
    (32.9, -2.5, "Mwanza", "Mwanza", ""),
    (33.45, -8.9, "Mbeya", "Mbeya", ""),
    # ── Southern Africa ──
    (13.2, -8.8, "Luanda", "Luanda", ""),
    (15.7, -12.8, "Huambo", "Huambo", ""),
    (20.4, -9.65, "Saurimo", "Saurimo", ""),
    (17.7, -14.65, "Menongue", "Menongue", ""),
    (28.3, -15.4, "Lusaka", "Lusaka", ""),
    (23.1, -15.25, "Mongu", "Mongu", ""),
    (31.2, -10.2, "Kasama", "Kasama", ""),
    (33.8, -14.0, "Lilongve", "Lilongwe", ""),
    (31.05, -17.8, "Harare", "Harare", ""),
    (28.6, -20.15, "Bulawayo", "Bulawayo", ""),
    (32.6, -25.95, "Maputo", "Maputo", ""),
    (34.85, -19.8, "Beira", "Beira", ""),
    (39.3, -15.1, "Nampula", "Nampula", ""),
    (33.6, -16.15, "Tete", "Tete", ""),
    (17.1, -22.6, "Windhuk", "Windhoek", ""),
    (19.8, -17.9, "Rundu", "Rundu", ""),
    (15.2, -26.6, "Lüderitz", "Luderitz", ""),
    (25.9, -24.65, "Gaborone", "Gaborone", ""),
    (23.4, -19.98, "Maun", "Maun", ""),
    (28.0, -26.2, "Johannesburg", "Johannesburg", "gold"),
    (18.4, -33.9, "Cape Town", "Cape Town", ""),
    (25.6, -33.96, "Port Elizabeth", "Port Elizabeth", ""),
    (31.0, -29.85, "Durban", "Durban", ""),
    (26.2, -29.1, "Bloemfontein", "Bloemfontein", ""),
    (21.25, -28.45, "Upington", "Upington", ""),
    # ── Madagascar ──
    (47.5, -18.9, "Antananarivo", "Antananarivo", ""),
    (43.7, -23.35, "Toliara", "Toliara", ""),
    (46.3, -15.7, "Mahajanga", "Mahajanga", ""),
]

# Start cities of the human players: four neighbouring cities each.
HUMAN_STARTS = [
    ["Casablanca", "Rabat", "Fez", "Marrakesh"],
    ["Cape Town", "Port Elizabeth", "Upington", "Bloemfontein"],
]

# Diamond mines: real diamond fields, plus a few more so every corner of the
# continent has one to fight over. Each marks the region it lies in.
MINES = [
    (24.7, -24.6),  # Jwaneng, Botswana
    (24.8, -28.7),  # Kimberley, South Africa
    (16.4, -28.3),  # Oranjemund, Namibia
    (32.4, -19.9),  # Marange, Zimbabwe
    (23.6, -6.1),  # Mbuji-Mayi, DR Congo
    (20.3, -9.4),  # Catoca, Angola
    (33.6, -3.6),  # Williamson, Tanzania
    (-11.0, 8.6),  # Kono, Sierra Leone
    (-0.8, 6.0),  # Akwatia, Ghana
    (15.9, 4.9),  # Carnot, Central African Republic
    (5.5, 23.0),  # Hoggar, Algeria
    (29.0, 12.5),  # Kordofan, Sudan
    (46.5, -20.5),  # Madagascar
    (38.5, 6.5),  # Ethiopia
]

# The three forests ("3 orman"): in the rain-forest belt.
FORESTS = ["Kisangani", "Ouesso", "Monrovia"]


def main():
    geo = json.load(open(os.path.join(ROOT, "tool/data/africa_geo.json")))
    countries = geo["countries"]
    rings = [ring for rs in countries.values() for ring in rs]

    # ── World frame (identical to the old tile map) ───────────────────────
    origin_lon, origin_lat, cols, rows = world_frame(rings)

    def to_world(lon, lat):
        return ((lon - origin_lon) / CELL_DEG * TILE,
                (origin_lat - lat) / CELL_DEG * TILE)

    # ── Land: all countries merged, small islands dropped ─────────────────
    land = unary_union([Polygon(r).buffer(0) for r in rings])
    parts = list(land.geoms) if isinstance(land, MultiPolygon) else [land]
    parts = [p for p in parts if p.area >= MIN_ISLAND_DEG2]
    land = unary_union(parts)

    # ── Regions: Voronoi cells of the cities clipped to the land ──────────
    pts = np.array([(c[0], c[1]) for c in CITIES])
    far = [(-200, -200), (-200, 200), (200, -200), (200, 200)]
    vor = Voronoi(np.vstack([pts, far]))
    regions = []
    for i, city in enumerate(CITIES):
        verts = vor.regions[vor.point_region[i]]
        assert -1 not in verts, city
        cell = Polygon([vor.vertices[v] for v in verts])
        region = cell.intersection(land)
        if region.is_empty:
            raise SystemExit(f"{city[3]} lies in the sea")
        regions.append(region)

    # Land pieces that fell into a cell but are cut off from its city (e.g.
    # a cape across a bay) stay with that region; tiny slivers are dropped.
    def polygons(geom):
        geoms = list(geom.geoms) if hasattr(geom, "geoms") else [geom]
        return [g for g in geoms if isinstance(g, Polygon) and g.area > 0.05]

    # ── Adjacency: a shared border of real length ─────────────────────────
    n = len(CITIES)
    adjacency = {i: set() for i in range(n)}
    for a in range(n):
        for b in range(a + 1, n):
            if not regions[a].envelope.intersects(regions[b].envelope):
                continue
            shared = regions[a].boundary.intersection(regions[b].boundary)
            if shared.length >= MIN_SHARED_BORDER_DEG:
                adjacency[a].add(b)
                adjacency[b].add(a)

    # Sea route: every separate component (Madagascar) joins the mainland
    # at its closest pair of cities.
    sea_links = []
    components = connected(adjacency, n)
    components.sort(key=len, reverse=True)
    mainland = components[0]
    for comp in components[1:]:
        a, b = min(
            ((a, b) for a in comp for b in mainland),
            key=lambda ab: (pts[ab[0]][0] - pts[ab[1]][0]) ** 2
            + (pts[ab[0]][1] - pts[ab[1]][1]) ** 2,
        )
        adjacency[a].add(b)
        adjacency[b].add(a)
        sea_links.append([a, b])
    assert len(connected(adjacency, n)) == 1

    # ── Mines and forests ─────────────────────────────────────────────────
    def region_at(lon, lat):
        p = Point(lon, lat)
        for i, r in enumerate(regions):
            if r.contains(p):
                return i
        return min(range(n), key=lambda i: r_dist(regions[i], p))

    mines = set()
    for lon, lat in MINES:
        mines.add(region_at(lon, lat))
    by_name = {c[3]: i for i, c in enumerate(CITIES)}
    forests = {by_name[name] for name in FORESTS}
    human_starts = [[by_name[name] for name in group] for group in HUMAN_STARTS]
    for group in human_starts:
        for a in group[1:]:
            assert connected_within(adjacency, group), group

    # ── Satellite picture (only re-cut when a Blue Marble path is given) ──
    if len(sys.argv) > 1:
        cut_satellite(sys.argv[1], origin_lon, origin_lat, cols, rows)

    # ── Output ───────────────────────────────────────────────────────────
    territories = []
    for i, (lon, lat, tr, en, kind) in enumerate(CITIES):
        x, y = to_world(*marker_of(regions[i], lon, lat))
        outline = []
        for poly in polygons(regions[i].simplify(SIMPLIFY_DEG,
                                                 preserve_topology=True)):
            ring = list(poly.exterior.coords)[:-1]
            outline.append([round(v, 1) for p in ring for v in to_world(*p)])
        t = {
            "id": i,
            "nameKey": "city_" + slug(en),
            "name": {"tr": tr, "en": en},
            "type": "goldMine" if kind == "gold" else "city",
            "adjacentIds": sorted(adjacency[i]),
            "x": round(x, 1),
            "y": round(y, 1),
        }
        if i in mines:
            t["diamondMine"] = True
        if i in forests:
            t["forest"] = True
        t["outline"] = outline
        territories.append(t)

    lines = ["{"]
    lines.append(f'  "cols": {cols},')
    lines.append(f'  "rows": {rows},')
    lines.append(f'  "tileSize": {TILE},')
    lines.append(f'  "satelliteMargin": {SAT_MARGIN},')
    lines.append(f'  "humanStarts": {json.dumps(human_starts)},')
    lines.append(f'  "seaLinks": {json.dumps(sea_links)},')
    lines.append('  "territories": [')
    for i, t in enumerate(territories):
        comma = "," if i < len(territories) - 1 else ""
        lines.append("    " + json.dumps(t, ensure_ascii=False,
                                         separators=(",", ":")) + comma)
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

    degrees = [len(adjacency[i]) for i in range(n)]
    print(f"frame {cols}x{rows}, {n} cities, {len(mines)} mines, "
          f"forests {sorted(forests)}, sea links {sea_links}, "
          f"neighbours min {min(degrees)} max {max(degrees)}, "
          f"human starts {human_starts}")
    lonely = [CITIES[i][3] for i in range(n) if degrees[i] < 2]
    if lonely:
        print("cities with < 2 neighbours:", lonely)


def marker_of(region, lon, lat):
    """Where the city is drawn: the city itself, or — for a port just off
    the simplified coastline — a point a little inland."""
    p = Point(lon, lat)
    inner = region.buffer(-0.35)
    if inner.is_empty:
        inner = region
    if inner.contains(p):
        return lon, lat
    q = nearest_points(inner, p)[0]
    return q.x, q.y


def r_dist(region, p):
    return region.distance(p)


def slug(name):
    out = "".join(ch.lower() if ch.isalnum() else "_" for ch in name)
    return "_".join(filter(None, out.split("_")))


def connected(adjacency, n):
    seen, comps = set(), []
    for s in range(n):
        if s in seen:
            continue
        comp, q = [], deque([s])
        seen.add(s)
        while q:
            cur = q.popleft()
            comp.append(cur)
            for nb in adjacency[cur]:
                if nb not in seen:
                    seen.add(nb)
                    q.append(nb)
        comps.append(comp)
    return comps


def connected_within(adjacency, group):
    group = set(group)
    start = next(iter(group))
    seen, q = {start}, deque([start])
    while q:
        cur = q.popleft()
        for nb in adjacency[cur]:
            if nb in group and nb not in seen:
                seen.add(nb)
                q.append(nb)
    return seen == group


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


def world_frame(rings):
    """Origin (lon, lat) and size (cols, rows of CELL_DEG) of the map —
    computed exactly like the old tile map so the satellite crop fits."""
    boxes = [
        (min(p[0] for p in r), max(p[0] for p in r),
         min(p[1] for p in r), max(p[1] for p in r))
        for r in rings
    ]

    def on_land(x, y):
        for ring, (x0, x1, y0, y1) in zip(rings, boxes):
            if x0 <= x <= x1 and y0 <= y <= y1 and inside(ring, x, y):
                return True
        return False

    lons = [p[0] for r in rings for p in r]
    lats = [p[1] for r in rings for p in r]
    min_lon, max_lat = min(lons), max(lats)
    cols = math.ceil((max(lons) - min_lon) / CELL_DEG)
    rows = math.ceil((max_lat - min(lats)) / CELL_DEG)
    cells = set()
    for r in range(rows):
        for c in range(cols):
            lon0 = min_lon + c * CELL_DEG
            lat0 = max_lat - r * CELL_DEG
            hits = sum(
                on_land(lon0 + (a + 0.5) * CELL_DEG / SAMPLES,
                        lat0 - (b + 0.5) * CELL_DEG / SAMPLES)
                for a in range(SAMPLES) for b in range(SAMPLES)
            )
            if hits >= 0.4 * SAMPLES * SAMPLES:
                cells.add((c, r))

    def neighbours(cell):
        c, r = cell
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nb = (c + d[0], r + d[1])
            if nb in cells:
                yield nb

    seen, keep = set(), set()
    for cell in sorted(cells, key=lambda k: (k[1], k[0])):
        if cell in seen:
            continue
        comp, q = [], deque([cell])
        seen.add(cell)
        while q:
            cur = q.popleft()
            comp.append(cur)
            for nb in neighbours(cur):
                if nb not in seen:
                    seen.add(nb)
                    q.append(nb)
        if len(comp) >= 3:
            keep.update(comp)
    c0 = min(c for c, _ in keep)
    r0 = min(r for _, r in keep)
    cols = max(c for c, _ in keep) - c0 + 1
    rows = max(r for _, r in keep) - r0 + 1
    return min_lon + c0 * CELL_DEG, max_lat - r0 * CELL_DEG, cols, rows


def cut_satellite(path, origin_lon, origin_lat, cols, rows):
    sat_lon0 = origin_lon - SAT_MARGIN * CELL_DEG
    sat_lat0 = origin_lat + SAT_MARGIN * CELL_DEG
    sat_w_deg = (cols + 2 * SAT_MARGIN) * CELL_DEG
    sat_h_deg = (rows + 2 * SAT_MARGIN) * CELL_DEG
    Image.MAX_IMAGE_PIXELS = None
    world = Image.open(path)
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


if __name__ == "__main__":
    main()
