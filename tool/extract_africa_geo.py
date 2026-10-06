#!/usr/bin/env python3
"""Extracts simplified African country outlines from Natural Earth data.

Input: the `world-atlas` TopoJSON (Natural Earth 1:50m, public domain), e.g.
  curl -L -o countries-50m.json \
    https://cdn.jsdelivr.net/npm/world-atlas@2/countries-50m.json

Shared borders are simplified once per TopoJSON arc (Douglas-Peucker), so
neighbouring countries keep matching borders. Tiny islands are dropped.

Writes tool/data/africa_geo.json: {"countries": {key: [[[lon, lat], ...]]}},
which tool/generate_africa_map.py turns into the game map.

Usage: python3 tool/extract_africa_geo.py path/to/countries-50m.json
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TOLERANCE = 0.06  # degrees
MIN_RING_AREA = 0.2  # square degrees; smaller islands are dropped

# Natural Earth name → region key (several names may share one key).
COUNTRIES = {
    "Morocco": "morocco", "W. Sahara": "western_sahara", "Algeria": "algeria",
    "Tunisia": "tunisia", "Libya": "libya", "Egypt": "egypt",
    "Mauritania": "mauritania", "Mali": "mali", "Niger": "niger",
    "Chad": "chad", "Sudan": "sudan", "S. Sudan": "south_sudan",
    "Eritrea": "eritrea", "Djibouti": "djibouti", "Ethiopia": "ethiopia",
    "Somalia": "somalia", "Somaliland": "somalia", "Senegal": "senegal",
    "Gambia": "gambia", "Guinea-Bissau": "guinea_bissau", "Guinea": "guinea",
    "Sierra Leone": "sierra_leone", "Liberia": "liberia",
    "Côte d'Ivoire": "ivory_coast", "Burkina Faso": "burkina_faso",
    "Ghana": "ghana", "Togo": "togo", "Benin": "benin",
    "Nigeria": "nigeria", "Cameroon": "cameroon",
    "Central African Rep.": "central_africa", "Eq. Guinea": "eq_guinea",
    "Gabon": "gabon", "Congo": "congo_brazzaville",
    "Dem. Rep. Congo": "congo", "Uganda": "uganda", "Kenya": "kenya",
    "Rwanda": "rwanda", "Burundi": "burundi", "Tanzania": "tanzania",
    "Angola": "angola", "Zambia": "zambia", "Malawi": "malawi",
    "Mozambique": "mozambique", "Zimbabwe": "zimbabwe",
    "Namibia": "namibia", "Botswana": "botswana",
    "South Africa": "south_africa", "Lesotho": "lesotho",
    "eSwatini": "eswatini", "Madagascar": "madagascar",
}


def simplify(points, tol):
    """Douglas-Peucker; keeps both end points."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        norm = (dx * dx + dy * dy) ** 0.5
        best, best_i = -1.0, -1
        for i in range(a + 1, b):
            px, py = points[i]
            if norm == 0:
                d = ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
            else:
                d = abs(dy * px - dx * py + bx * ay - by * ax) / norm
            if d > best:
                best, best_i = d, i
        if best > tol:
            keep[best_i] = True
            stack += [(a, best_i), (best_i, b)]
    return [p for p, k in zip(points, keep) if k]


def ring_area(ring):
    s = 0.0
    for i in range(len(ring)):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % len(ring)]
        s += x1 * y2 - x2 * y1
    return abs(s) / 2


def main():
    topo = json.load(open(sys.argv[1]))
    sx, sy = topo["transform"]["scale"]
    tx, ty = topo["transform"]["translate"]

    arcs = []
    for arc in topo["arcs"]:
        x = y = 0
        pts = []
        for qx, qy in arc:
            x += qx
            y += qy
            pts.append((x * sx + tx, y * sy + ty))
        arcs.append(simplify(pts, TOLERANCE))

    def ring_from(arc_ids):
        ring = []
        for i in arc_ids:
            pts = arcs[i] if i >= 0 else arcs[~i][::-1]
            ring.extend(pts if not ring else pts[1:])
        return ring

    countries = {}
    for geo in topo["objects"]["countries"]["geometries"]:
        key = COUNTRIES.get(geo["properties"]["name"])
        if key is None:
            continue
        polys = geo["arcs"] if geo["type"] == "MultiPolygon" else [geo["arcs"]]
        for poly in polys:
            outer = ring_from(poly[0])  # holes are ignored
            if ring_area(outer) < MIN_RING_AREA or len(outer) < 4:
                continue
            countries.setdefault(key, []).append(
                [[round(x, 3), round(y, 3)] for x, y in outer[:-1]]
            )

    out = os.path.join(ROOT, "tool/data/africa_geo.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        json.dump(
            {
                "source": "Natural Earth 1:50m (public domain) via world-atlas",
                "countries": dict(sorted(countries.items())),
            },
            f,
            separators=(",", ":"),
        )
    points = sum(len(r) for rings in countries.values() for r in rings)
    print(f"{len(countries)} countries, {points} points -> {out}")


if __name__ == "__main__":
    main()
