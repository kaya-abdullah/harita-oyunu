#!/usr/bin/env python3
"""Generates the Africa country-and-city map for Harita.

Africa is drawn with its real countries (tool/data/africa_geo.json, extracted
from Natural Earth by tool/extract_africa_geo.py). Every country holds four
real cities (the smallest countries two or three) and is split between them:
each city owns the part of its country that is closer to it than to the
country's other cities (Voronoi cells clipped to the country). These city
areas are the territories of the game — there is no land without a city.

Cities whose areas share a border are neighbours; Madagascar is linked to the
mainland by a single sea route. For drawing, the file also keeps every
country outline and every border line between two neighbouring city areas
(and the coast line of each area), so the game can draw the frontier of each
army.

The map background is NASA's Blue Marble (topography + bathymetry, Dec 2004,
public domain). It is plate carrée like this map, so a crop of it lines up
with the cities exactly. The world frame (TILE units per CELL_DEG degrees,
origin and size) is the same as the old tile map, so the existing
assets/images/africa_satellite.jpg keeps fitting. Each city's terrain (rain
forest / savanna / steppe / desert) is read from the picture's colours.

Writes:
  assets/maps/territory_graph.json
  lib/infrastructure/map/territory_graph_data.dart
  the "city_*" names in assets/locales/tr.json and en.json
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
from collections import OrderedDict, deque

import numpy as np
from PIL import Image
from scipy.spatial import Voronoi
from shapely.geometry import (LineString, MultiLineString, MultiPolygon,
                              Point, Polygon)
from shapely.ops import linemerge, nearest_points, unary_union

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CELL_DEG = 1.5  # degrees per world "tile" (frame of the satellite picture)
TILE = 24.0  # world units per CELL_DEG
SAMPLES = 4  # land samples per cell side (frame computation)
SAT_MARGIN = 3  # tiles of satellite picture around the map on every side
SAT_PX_PER_DEG = 32  # satellite resolution kept in the game
SATELLITE = os.path.join(ROOT, "assets/images/africa_satellite.jpg")
MIN_PIECE_DEG2 = 0.03  # smaller bits of a city area are dropped
MIN_SHARED_BORDER_DEG = 0.15  # shorter contacts do not make neighbours
LINE_SIMPLIFY_DEG = 0.01
MOROCCO_SOUTH_LAT = 27.667  # Morocco / Western Sahara border

# Country → cities: (lon, lat, Turkish name, English name, kind). The first
# city of a country is its capital (or best-known city). kind "gold" marks a
# gold mine (a big capital that pays out when captured).
COUNTRY_CITIES = OrderedDict([
    ("morocco", [
        (-7.6, 33.6, "Kazablanka", "Casablanca", "gold"),
        (-5.0, 34.03, "Fas", "Fez", ""),
        (-1.91, 34.68, "Ujda", "Oujda", ""),
        (-8.0, 31.63, "Marakeş", "Marrakesh", ""),
    ]),
    ("western_sahara", [
        (-13.2, 27.15, "Layun", "Laayoune", ""),
        (-9.07, 27.43, "Mahbes", "Mahbes", ""),
        (-12.65, 25.13, "Guelta Zemmur", "Guelta Zemmur", ""),
        (-15.93, 23.7, "Dahla", "Dakhla", ""),
    ]),
    ("algeria", [
        (3.06, 36.75, "Cezayir", "Algiers", "gold"),
        (-2.22, 31.62, "Beşar", "Bechar", ""),
        (5.33, 31.95, "Vergile", "Ouargla", ""),
        (5.52, 22.79, "Temenrasat", "Tamanrasset", ""),
    ]),
    ("tunisia", [
        (10.18, 36.8, "Tunus", "Tunis", ""),
        (10.76, 34.74, "Sfaks", "Sfax", ""),
        (8.78, 34.42, "Gafsa", "Gafsa", ""),
        (10.45, 32.93, "Tataouine", "Tataouine", ""),
    ]),
    ("libya", [
        (13.19, 32.89, "Trablus", "Tripoli", "gold"),
        (20.07, 32.12, "Bingazi", "Benghazi", ""),
        (14.43, 27.04, "Sebha", "Sabha", ""),
        (23.31, 24.18, "Kufra", "Kufra", ""),
    ]),
    ("egypt", [
        (31.24, 30.04, "Kahire", "Cairo", "gold"),
        (25.52, 29.2, "Siva", "Siwa", ""),
        (30.55, 25.45, "Harga", "Kharga", ""),
        (32.9, 24.09, "Asvan", "Aswan", ""),
    ]),
    ("mauritania", [
        (-15.98, 18.09, "Nuakşot", "Nouakchott", ""),
        (-12.48, 22.73, "Zuerat", "Zouerat", ""),
        (-11.4, 16.62, "Kiffa", "Kiffa", ""),
        (-7.25, 16.62, "Nema", "Nema", ""),
    ]),
    ("mali", [
        (-8.0, 12.64, "Bamako", "Bamako", ""),
        (-3.0, 16.77, "Timbuktu", "Timbuktu", ""),
        (-0.04, 16.27, "Gao", "Gao", ""),
        (-3.98, 22.68, "Taudeni", "Taoudenni", ""),
    ]),
    ("niger", [
        (2.11, 13.51, "Niamey", "Niamey", ""),
        (8.99, 13.8, "Zinder", "Zinder", ""),
        (7.99, 16.97, "Agadez", "Agadez", ""),
        (12.92, 18.69, "Bilma", "Bilma", ""),
    ]),
    # Chad keeps only its north: America (below) takes the south.
    ("chad", [
        (19.1, 17.92, "Faya", "Faya", ""),
        (21.58, 17.18, "Fada", "Fada", ""),
        (16.99, 21.36, "Bardai", "Bardai", ""),
    ]),
    # "Ortaya Amerika ekle, Amerika biz olalım; Amerika'da 4 şehir olsun":
    # a round country in the middle of Africa (see AMERICA_CENTRE), the
    # player's America, with four American cities in a square.
    ("america", [
        (17.2, 12.8, "Vaşington", "Washington", "gold"),
        (19.8, 12.8, "New York", "New York", ""),
        (17.2, 10.2, "Şikago", "Chicago", ""),
        (19.8, 10.2, "Los Angeles", "Los Angeles", ""),
    ]),
    ("sudan", [
        (32.53, 15.59, "Hartum", "Khartoum", "gold"),
        (37.22, 19.62, "Port Sudan", "Port Sudan", ""),
        (30.48, 19.17, "Dongola", "Dongola", ""),
        (25.35, 13.63, "El Faşir", "El Fasher", ""),
    ]),
    ("south_sudan", [
        (31.58, 4.85, "Cuba", "Juba", ""),
        (27.99, 7.7, "Vau", "Wau", ""),
        (31.66, 9.53, "Malakal", "Malakal", ""),
        (33.13, 6.8, "Pibor", "Pibor", ""),
    ]),
    ("eritrea", [
        (38.93, 15.33, "Asmara", "Asmara", ""),
        (36.66, 15.11, "Teseney", "Tessenei", ""),
        (40.95, 14.68, "Tio", "Tio", ""),
        (42.74, 13.0, "Asab", "Assab", ""),
    ]),
    ("djibouti", [
        (43.15, 11.59, "Cibuti", "Djibouti", ""),
        (42.37, 11.1, "Dikhil", "Dikhil", ""),
    ]),
    ("ethiopia", [
        (38.75, 9.03, "Addis Ababa", "Addis Ababa", "gold"),
        (39.47, 13.5, "Mekele", "Mekelle", ""),
        (43.55, 5.95, "Gode", "Gode", ""),
        (36.83, 7.67, "Cimma", "Jimma", ""),
    ]),
    ("somalia", [
        (45.34, 2.05, "Mogadişu", "Mogadishu", ""),
        (44.06, 9.56, "Hargeysa", "Hargeisa", ""),
        (49.18, 11.28, "Bosaso", "Bosaso", ""),
        (47.43, 6.77, "Galkayo", "Galkayo", ""),
    ]),
    ("senegal", [
        (-17.3, 14.72, "Dakar", "Dakar", "gold"),
        (-16.49, 16.02, "Saint-Louis", "Saint-Louis", ""),
        (-13.67, 13.77, "Tambakunda", "Tambacounda", ""),
        (-16.27, 12.58, "Ziguinşor", "Ziguinchor", ""),
    ]),
    ("gambia", [
        (-16.58, 13.45, "Banjul", "Banjul", ""),
        (-14.21, 13.31, "Basse", "Basse", ""),
    ]),
    ("guinea_bissau", [
        (-15.6, 11.86, "Bissau", "Bissau", ""),
        (-14.22, 12.28, "Gabu", "Gabu", ""),
    ]),
    ("guinea", [
        (-13.71, 9.51, "Konakri", "Conakry", ""),
        (-12.28, 11.32, "Labe", "Labe", ""),
        (-9.31, 10.39, "Kankan", "Kankan", ""),
        (-8.82, 7.76, "Nzerekore", "Nzerekore", ""),
    ]),
    ("sierra_leone", [
        (-13.23, 8.48, "Freetown", "Freetown", ""),
        (-11.74, 7.96, "Bo", "Bo", ""),
        (-11.55, 9.59, "Kabala", "Kabala", ""),
    ]),
    ("liberia", [
        (-10.8, 6.3, "Monrovia", "Monrovia", ""),
        (-9.47, 7.0, "Gbarnga", "Gbarnga", ""),
        (-8.13, 6.07, "Zwedru", "Zwedru", ""),
        (-7.72, 4.38, "Harper", "Harper", ""),
    ]),
    ("ivory_coast", [
        (-5.28, 6.82, "Yamusukro", "Yamoussoukro", ""),
        (-4.01, 5.35, "Abidjan", "Abidjan", ""),
        (-5.63, 9.46, "Korhogo", "Korhogo", ""),
        (-7.55, 7.41, "Man", "Man", ""),
    ]),
    ("burkina_faso", [
        (-1.52, 12.37, "Vagadugu", "Ouagadougou", ""),
        (-4.3, 11.18, "Bobo-Diulasso", "Bobo-Dioulasso", ""),
        (-0.03, 14.03, "Dori", "Dori", ""),
        (0.35, 12.06, "Fada Ngurma", "Fada N'gourma", ""),
    ]),
    ("ghana", [
        (-0.19, 5.6, "Akra", "Accra", ""),
        (-1.62, 6.69, "Kumasi", "Kumasi", ""),
        (-0.85, 9.4, "Tamale", "Tamale", ""),
        (-2.5, 10.06, "Wa", "Wa", ""),
    ]),
    ("togo", [
        (1.22, 6.13, "Lome", "Lome", ""),
        (1.13, 7.53, "Atakpame", "Atakpame", ""),
        (1.19, 9.55, "Kara", "Kara", ""),
    ]),
    ("benin", [
        (2.42, 6.37, "Kotonu", "Cotonou", ""),
        (2.63, 9.34, "Parakou", "Parakou", ""),
        (1.38, 10.3, "Natitingu", "Natitingou", ""),
        (2.94, 11.13, "Kandi", "Kandi", ""),
    ]),
    ("nigeria", [
        (3.39, 6.45, "Lagos", "Lagos", "gold"),
        (7.49, 9.06, "Abuja", "Abuja", ""),
        (8.52, 12.0, "Kano", "Kano", ""),
        (7.0, 4.82, "Port Harcourt", "Port Harcourt", ""),
    ]),
    ("cameroon", [
        (11.5, 3.87, "Yaunde", "Yaounde", ""),
        (9.7, 4.05, "Duala", "Douala", ""),
        (13.58, 7.32, "Ngaundere", "Ngaoundere", ""),
        (14.32, 10.59, "Marua", "Maroua", ""),
    ]),
    ("central_africa", [
        (18.56, 4.36, "Bangui", "Bangui", ""),
        (15.79, 4.26, "Berberati", "Berberati", ""),
        (21.99, 6.54, "Bria", "Bria", ""),
        (22.79, 10.29, "Birao", "Birao", ""),
    ]),
    ("eq_guinea", [
        (9.77, 1.86, "Bata", "Bata", ""),
        (11.33, 1.9, "Ebebiyin", "Ebebiyin", ""),
    ]),
    ("gabon", [
        (9.45, 0.39, "Librevil", "Libreville", ""),
        (11.58, 1.6, "Oyem", "Oyem", ""),
        (13.58, -1.63, "Franceville", "Franceville", ""),
        (11.03, -2.85, "Tchibanga", "Tchibanga", ""),
    ]),
    ("congo_brazzaville", [
        (15.28, -4.27, "Brazavil", "Brazzaville", ""),
        (11.86, -4.78, "Pointe-Noire", "Pointe-Noire", ""),
        (15.9, -0.48, "Owando", "Owando", ""),
        (16.05, 1.61, "Ouesso", "Ouesso", ""),
    ]),
    ("congo", [
        (15.31, -4.33, "Kinşasa", "Kinshasa", "gold"),
        (25.2, 0.52, "Kisangani", "Kisangani", ""),
        (22.42, -5.9, "Kananga", "Kananga", ""),
        (27.48, -11.66, "Lubumbaşi", "Lubumbashi", ""),
    ]),
    ("uganda", [
        (32.58, 0.35, "Kampala", "Kampala", ""),
        (32.3, 2.78, "Gulu", "Gulu", ""),
        (30.66, -0.61, "Mbarara", "Mbarara", ""),
        (34.18, 1.08, "Mbale", "Mbale", ""),
    ]),
    ("kenya", [
        (36.82, -1.29, "Nairobi", "Nairobi", "gold"),
        (39.67, -4.04, "Mombasa", "Mombasa", ""),
        (35.6, 3.12, "Lodvar", "Lodwar", ""),
        (39.66, -0.45, "Garissa", "Garissa", ""),
    ]),
    ("rwanda", [
        (30.06, -1.95, "Kigali", "Kigali", ""),
        (29.74, -2.6, "Huye", "Huye", ""),
    ]),
    ("burundi", [
        (29.36, -3.38, "Bujumbura", "Bujumbura", ""),
        (30.34, -2.85, "Muyinga", "Muyinga", ""),
    ]),
    ("tanzania", [
        (35.74, -6.17, "Dodoma", "Dodoma", ""),
        (39.28, -6.82, "Darüsselam", "Dar es Salaam", "gold"),
        (32.9, -2.52, "Mwanza", "Mwanza", ""),
        (33.46, -8.9, "Mbeya", "Mbeya", ""),
    ]),
    ("angola", [
        (13.23, -8.84, "Luanda", "Luanda", "gold"),
        (15.74, -12.78, "Huambo", "Huambo", ""),
        (20.39, -9.66, "Saurimo", "Saurimo", ""),
        (17.69, -14.66, "Menongue", "Menongue", ""),
    ]),
    ("zambia", [
        (28.28, -15.42, "Lusaka", "Lusaka", ""),
        (28.64, -12.97, "Ndola", "Ndola", ""),
        (23.13, -15.25, "Mongu", "Mongu", ""),
        (31.18, -10.21, "Kasama", "Kasama", ""),
    ]),
    ("malawi", [
        (33.79, -13.96, "Lilongve", "Lilongwe", ""),
        (35.0, -15.79, "Blantyre", "Blantyre", ""),
        (34.02, -11.46, "Mzuzu", "Mzuzu", ""),
        (33.93, -9.93, "Karonga", "Karonga", ""),
    ]),
    ("mozambique", [
        (32.59, -25.97, "Maputo", "Maputo", ""),
        (34.84, -19.84, "Beira", "Beira", ""),
        (33.59, -16.16, "Tete", "Tete", ""),
        (39.27, -15.12, "Nampula", "Nampula", ""),
    ]),
    ("zimbabwe", [
        (31.05, -17.83, "Harare", "Harare", ""),
        (28.58, -20.15, "Bulawayo", "Bulawayo", ""),
        (26.5, -18.36, "Hwange", "Hwange", ""),
        (30.83, -20.07, "Masvingo", "Masvingo", ""),
    ]),
    ("namibia", [
        (17.08, -22.56, "Windhuk", "Windhoek", ""),
        (15.69, -17.79, "Oshakati", "Oshakati", ""),
        (19.77, -17.92, "Rundu", "Rundu", ""),
        (18.13, -26.58, "Keetmanshoop", "Keetmanshoop", ""),
    ]),
    ("botswana", [
        (25.91, -24.65, "Gaborone", "Gaborone", ""),
        (23.42, -19.98, "Maun", "Maun", ""),
        (27.51, -21.17, "Francistown", "Francistown", ""),
        (21.78, -21.7, "Ganzi", "Ghanzi", ""),
    ]),
    ("south_africa", [
        (28.05, -26.2, "Johannesburg", "Johannesburg", "gold"),
        (18.42, -33.92, "Cape Town", "Cape Town", ""),
        (31.02, -29.86, "Durban", "Durban", ""),
        (21.25, -28.45, "Upington", "Upington", ""),
    ]),
    ("lesotho", [
        (27.48, -29.31, "Maseru", "Maseru", ""),
        (29.07, -29.29, "Mokhotlong", "Mokhotlong", ""),
    ]),
    ("eswatini", [
        (31.25, -25.96, "Piggs Peak", "Piggs Peak", ""),
        (31.2, -27.11, "Nhlangano", "Nhlangano", ""),
    ]),
    ("madagascar", [
        (47.52, -18.91, "Antananarivo", "Antananarivo", ""),
        (43.67, -23.35, "Toliara", "Toliara", ""),
        (46.32, -15.72, "Mahajanga", "Mahajanga", ""),
        (49.29, -12.28, "Antsiranana", "Antsiranana", ""),
    ]),
])

# America: a circle (lon, lat, radius in degrees) cut out of the middle of
# Africa — mostly Chad's south, a little of its neighbours.
AMERICA_CENTRE = (18.5, 11.5)
AMERICA_RADIUS = 4.0

# The player starts in America; the six bots start in the countries closest
# to it ("bot şehirler çok yakın olsun"), chosen by the generator.
PLAYER_COUNTRY = "america"
BOTS = 6

# Diamond mines: real diamond fields. Each marks the city area it lies in.
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


def main():
    geo = json.load(open(os.path.join(ROOT, "tool/data/africa_geo.json")))
    country_rings = geo["countries"]
    assert set(country_rings) | {"america"} == set(COUNTRY_CITIES), (
        (set(country_rings) | {"america"}) ^ set(COUNTRY_CITIES))
    rings = [ring for rs in country_rings.values() for ring in rs]
    shapes = country_shapes(country_rings)

    # ── World frame (identical to the old tile map) ───────────────────────
    origin_lon, origin_lat, cols, rows = world_frame(rings)

    def to_world(lon, lat):
        return ((lon - origin_lon) / CELL_DEG * TILE,
                (origin_lat - lat) / CELL_DEG * TILE)

    def flat(coords):
        return [round(v, 1) for p in coords for v in to_world(*p)]

    # ── City areas: Voronoi cells of a country's cities, clipped to it ────
    cities = []  # (lon, lat, tr, en, kind, country)
    areas = []
    for country, clist in COUNTRY_CITIES.items():
        shape = shapes[country]
        pts = np.array([(c[0], c[1]) for c in clist])
        far = [(-200, -200), (-200, 200), (200, -200), (200, 200)]
        vor = Voronoi(np.vstack([pts, far]))
        for i, city in enumerate(clist):
            verts = vor.regions[vor.point_region[i]]
            assert -1 not in verts, city
            cell = Polygon([vor.vertices[v] for v in verts])
            area = keep_pieces(cell.intersection(shape))
            if area.is_empty:
                raise SystemExit(f"{city[3]} has no land")
            if area.distance(Point(city[0], city[1])) > 0.12:
                raise SystemExit(f"{city[3]} lies outside {country}")
            cities.append((*city, country))
            areas.append(area)
    n = len(cities)

    # ── Adjacency: a shared border of real length ─────────────────────────
    adjacency = {i: set() for i in range(n)}
    borders = []  # [a, b, line] for every shared border
    shared_of = {i: [] for i in range(n)}
    for a in range(n):
        for b in range(a + 1, n):
            if not areas[a].buffer(0.01).intersects(areas[b]):
                continue
            shared = areas[a].boundary.intersection(areas[b].buffer(1e-6))
            shared = lines_of(shared)
            if shared.length < MIN_SHARED_BORDER_DEG:
                continue
            adjacency[a].add(b)
            adjacency[b].add(a)
            shared_of[a].append(shared)
            shared_of[b].append(shared)
            for line in parts_of(shared):
                borders.append([a, b, flat(line.coords)])

    # The coast of every area: its outline minus all shared borders.
    for i in range(n):
        coast = areas[i].boundary
        if shared_of[i]:
            coast = coast.difference(unary_union(shared_of[i]).buffer(1e-5))
        for line in parts_of(lines_of(coast)):
            if line.length > 0.05:
                borders.append([i, -1, flat(line.coords)])

    # Sea route: every separate component (Madagascar) joins the mainland
    # at its closest pair of cities.
    sea_links = []
    components = connected(adjacency, n)
    components.sort(key=len, reverse=True)
    mainland = components[0]
    for comp in components[1:]:
        a, b = min(
            ((a, b) for a in comp for b in mainland),
            key=lambda ab: (cities[ab[0]][0] - cities[ab[1]][0]) ** 2
            + (cities[ab[0]][1] - cities[ab[1]][1]) ** 2,
        )
        adjacency[a].add(b)
        adjacency[b].add(a)
        sea_links.append([a, b])
    assert len(connected(adjacency, n)) == 1

    # ── Mines ─────────────────────────────────────────────────────────────
    def area_at(lon, lat):
        p = Point(lon, lat)
        return min(range(n), key=lambda i: areas[i].distance(p))

    mines = {area_at(lon, lat) for lon, lat in MINES}

    # ── Start countries: America, then the countries nearest to it ───────
    def cities_of(country):
        return [i for i in range(n) if cities[i][5] == country]

    player = cities_of(PLAYER_COUNTRY)
    steps = bfs(adjacency, player, n)
    ax, ay = AMERICA_CENTRE
    others = [c for c in COUNTRY_CITIES if c != PLAYER_COUNTRY]
    # Countries touching America first, then by how close their nearest
    # city lies.
    others.sort(key=lambda c: (
        min(steps[i] for i in cities_of(c)),
        min(math.hypot(cities[i][0] - ax, cities[i][1] - ay)
            for i in cities_of(c)),
    ))
    start_countries = [PLAYER_COUNTRY] + others[:BOTS]
    starts = [cities_of(c) for c in start_countries]
    country_of = [c[5] for c in cities]
    for x, gx in enumerate(starts):
        assert connected_within(adjacency, gx), start_countries[x]

    # ── Satellite picture (only re-cut when a Blue Marble path is given) ──
    if len(sys.argv) > 1:
        cut_satellite(sys.argv[1], origin_lon, origin_lat, cols, rows)
    sat = Image.open(SATELLITE).convert("RGB")
    sat_ppd = sat.width / ((cols + 2 * SAT_MARGIN) * CELL_DEG)
    sat_lon0 = origin_lon - SAT_MARGIN * CELL_DEG
    sat_lat0 = origin_lat + SAT_MARGIN * CELL_DEG

    def terrain_of(area):
        """Rain forest / woodland / savanna / steppe / desert, from the mean
        colour of the satellite pixels inside the city area."""
        x0, y0, x1, y1 = area.bounds
        step = 0.25
        pixels = []
        lat = y0 + step / 2
        while lat < y1:
            lon = x0 + step / 2
            while lon < x1:
                if area.contains(Point(lon, lat)):
                    px = sat.getpixel((
                        min(sat.width - 1, int((lon - sat_lon0) * sat_ppd)),
                        min(sat.height - 1, int((sat_lat0 - lat) * sat_ppd)),
                    ))
                    if not (px[2] > px[0] + 8 and px[2] >= px[1]):
                        pixels.append(px)
                lon += step
            lat += step
        if not pixels:
            p = area.representative_point()
            pixels = [sat.getpixel((int((p.x - sat_lon0) * sat_ppd),
                                    int((sat_lat0 - p.y) * sat_ppd)))]
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

    # ── Output ───────────────────────────────────────────────────────────
    territories = []
    for i, (lon, lat, tr, en, kind, country) in enumerate(cities):
        x, y = to_world(*marker_of(areas[i], lon, lat))
        t = {
            "id": i,
            "nameKey": "city_" + slug(en),
            "country": country,
            "type": "bigBase" if kind == "gold" else "normal",
            "adjacentIds": sorted(adjacency[i]),
            "x": round(x, 1),
            "y": round(y, 1),
            "terrain": terrain_of(areas[i]),
        }
        if i in mines:
            t["diamondMine"] = True
        t["outline"] = [flat(list(p.exterior.coords)[:-1])
                        for p in polygons(areas[i])]
        territories.append(t)

    outlines = {
        key: [flat(list(p.exterior.coords)[:-1]) for p in polygons(shape)]
        for key, shape in sorted(shapes.items())
    }

    lines = ["{"]
    lines.append(f'  "cols": {cols},')
    lines.append(f'  "rows": {rows},')
    lines.append(f'  "tileSize": {TILE},')
    lines.append(f'  "satelliteMargin": {SAT_MARGIN},')
    lines.append(f'  "startCities": {json.dumps(starts)},')
    lines.append(f'  "seaLinks": {json.dumps(sea_links)},')
    lines.append('  "outlines": {')
    for i, (key, rs) in enumerate(outlines.items()):
        comma = "," if i < len(outlines) - 1 else ""
        lines.append(f'    "{key}": {json.dumps(rs, separators=(",", ":"))}'
                     + comma)
    lines.append("  },")
    lines.append('  "borders": [')
    for i, b in enumerate(borders):
        comma = "," if i < len(borders) - 1 else ""
        lines.append("    " + json.dumps(b, separators=(",", ":")) + comma)
    lines.append("  ],")
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

    write_city_names(cities)

    degrees = [len(adjacency[i]) for i in range(n)]
    sizes = sorted((areas[i].area, cities[i][3]) for i in range(n))
    print(f"frame {cols}x{rows}, {n} cities in {len(COUNTRY_CITIES)} "
          f"countries, {len(mines)} mines, sea links {sea_links}, "
          f"{len(borders)} border lines, neighbours min {min(degrees)} "
          f"max {max(degrees)}, start {start_countries} {starts}")
    print("smallest areas:", [(round(a, 2), c) for a, c in sizes[:6]])
    print("largest areas:", [(round(a, 1), c) for a, c in sizes[-4:]])
    lonely = [cities[i][3] for i in range(n) if degrees[i] < 2]
    if lonely:
        print("cities with < 2 neighbours:", lonely)
    del country_of


def country_shapes(country_rings):
    """Every country as one (multi)polygon. Natural Earth draws most of
    Western Sahara inside Morocco; the part south of 27°40' N (the real
    border) is given back to Western Sahara."""
    shapes = {
        key: unary_union([Polygon(r).buffer(0) for r in rs])
        for key, rs in country_rings.items()
    }
    south = Polygon([(-30, 0), (0, 0), (0, MOROCCO_SOUTH_LAT),
                     (-30, MOROCCO_SOUTH_LAT)])
    cut = shapes["morocco"].intersection(south)
    shapes["morocco"] = keep_pieces(shapes["morocco"].difference(south))
    shapes["western_sahara"] = keep_pieces(
        unary_union([shapes["western_sahara"], cut]).buffer(1e-9))
    # America: a round country cut out of the middle.
    circle = Point(*AMERICA_CENTRE).buffer(AMERICA_RADIUS, 64)
    for key in list(shapes):
        shapes[key] = keep_pieces(shapes[key].difference(circle))
    shapes["america"] = circle
    return shapes


def write_city_names(cities):
    """Adds every "city_*" key to the Turkish and English locale files
    (replacing the old ones)."""
    for lang, col in (("tr", 2), ("en", 3)):
        path = os.path.join(ROOT, f"assets/locales/{lang}.json")
        data = json.load(open(path), object_pairs_hook=OrderedDict)
        data = OrderedDict(
            (k, v) for k, v in data.items() if not k.startswith("city_"))
        for c in cities:
            data["city_" + slug(c[3])] = c[col]
        with open(path, "w") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")


def keep_pieces(geom):
    parts = [g for g in polygons(geom) if g.area >= MIN_PIECE_DEG2]
    return unary_union(parts) if parts else Polygon()


def polygons(geom):
    geoms = list(geom.geoms) if hasattr(geom, "geoms") else [geom]
    return [g for g in geoms if isinstance(g, Polygon) and not g.is_empty]


def lines_of(geom):
    """The line parts of [geom], merged into as few lines as possible."""
    geoms = list(geom.geoms) if hasattr(geom, "geoms") else [geom]
    segs = []
    for g in geoms:
        if isinstance(g, LineString):
            segs.append(g)
        elif isinstance(g, MultiLineString):
            segs.extend(g.geoms)
        elif hasattr(g, "geoms"):
            segs.extend(x for x in g.geoms if isinstance(x, LineString))
    segs = [g for g in segs if not g.is_empty and g.length > 0]
    if not segs:
        return MultiLineString()
    merged = linemerge(segs)
    return merged.simplify(LINE_SIMPLIFY_DEG)


def parts_of(lines):
    if lines.is_empty:
        return []
    return list(lines.geoms) if hasattr(lines, "geoms") else [lines]


def marker_of(area, lon, lat):
    """Where the city is drawn: the city itself, or — for a port just off
    the simplified coastline — a point a little inland."""
    p = Point(lon, lat)
    inner = area.buffer(-0.3)
    if inner.is_empty:
        inner = area.buffer(-0.1)
    if inner.is_empty:
        inner = area
    if inner.contains(p):
        return lon, lat
    q = nearest_points(inner, p)[0]
    return q.x, q.y


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


def bfs(adjacency, sources, n):
    """Steps from every city to the nearest of [sources]."""
    dist = [1 << 20] * n
    q = deque(sources)
    for s in sources:
        dist[s] = 0
    while q:
        cur = q.popleft()
        for nb in adjacency[cur]:
            if dist[nb] > dist[cur] + 1:
                dist[nb] = dist[cur] + 1
                q.append(nb)
    return dist


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
