#!/usr/bin/env python3
"""Cellka towerdb: дедупликация источников в towers_merged с confidence score.

Пример:
  python merge.py towers.db
"""

import argparse
import math
import sqlite3
import time

SOURCE_WEIGHT = {
    'opencellid': 0.30,
    'mls': 0.25,
    'openbmap': 0.35,
}
DEFAULT_WEIGHT = 0.20
AGREEMENT_RADIUS_M = 1000.0
AGREEMENT_BONUS = 0.20
BATCH = 10_000


def haversine_m(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def confidence(source, samples, range_m, updated_at, now):
    c = SOURCE_WEIGHT.get(source, DEFAULT_WEIGHT)
    if samples:
        c += min(math.log10(samples + 1) / 3.0, 0.30)
    if updated_at:
        age_years = max(0.0, (now - updated_at) / 31557600.0)
        c += max(0.0, 0.20 - 0.05 * age_years)
    if range_m and range_m > 5000:
        c -= 0.10
    return min(max(c, 0.05), 0.95)


def merge_group(rows, now):
    """rows: [(source, lat, lon, range_m, samples, updated_at), ...]"""
    scored = [(s, lat, lon, rm, sm, up, confidence(s, sm, rm, up, now))
              for s, lat, lon, rm, sm, up in rows]
    total_w = sum(c for *_x, c in scored)
    lat = sum(lat * c for _s, lat, _l, _r, _sm, _u, c in scored) / total_w
    lon = sum(lon * c for _s, _la, lon, _r, _sm, _u, c in scored) / total_w

    sources = sorted({s for s, *_ in scored})
    max_conf = max(c for *_x, c in scored)

    # Бонус согласия: несколько источников и все точки в пределах радиуса от центроида
    if len(sources) > 1:
        far = any(haversine_m(lat, lon, rlat, rlon) > AGREEMENT_RADIUS_M
                  for _s, rlat, rlon, _r, _sm, _u, _c in scored)
        if not far:
            max_conf = min(max_conf + AGREEMENT_BONUS, 0.95)

    samples_total = sum(sm or 0 for _s, _la, _lo, _r, sm, _u, _c in scored) or None
    ranges = [rm for _s, _la, _lo, rm, _sm, _u, _c in scored if rm]
    updated = max((up for _s, _la, _lo, _r, _sm, up, _c in scored if up),
                  default=None)

    return (round(lat, 7), round(lon, 7), min(ranges) if ranges else None,
            samples_total, updated, ','.join(sources), round(max_conf, 3))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('db', help='путь к towers.db')
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)
    now = int(time.time())
    conn.execute('DELETE FROM towers_merged')

    cur = conn.execute(
        'SELECT radio, mcc, mnc, area, cell, source, lat, lon, range_m, samples, updated_at'
        ' FROM raw_towers ORDER BY radio, mcc, mnc, area, cell')

    out, group, key, total = [], [], None, 0

    def flush():
        nonlocal total, out, group
        if not group:
            return
        lat, lon, rng, samples, updated, sources, conf = merge_group(group, now)
        out.append(key + (lat, lon, rng, samples, updated, sources, conf))
        group = []
        if len(out) >= BATCH:
            conn.executemany(
                'INSERT INTO towers_merged VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', out)
            total += len(out)
            out = []
            print(f'  {total} сот...', flush=True)

    for row in cur:
        k = row[:5]
        if k != key:
            flush()
            key = k
        group.append(row[5:])
    flush()
    if out:
        conn.executemany(
            'INSERT INTO towers_merged VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', out)
        total += len(out)

    conn.commit()
    print(f'OK: {total} уникальных сот в towers_merged')


if __name__ == '__main__':
    main()
