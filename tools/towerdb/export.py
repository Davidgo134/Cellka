#!/usr/bin/env python3
"""Cellka towerdb: экспорт компактной базы для приложения (cellka_towers.sqlite).

Пример:
  python export.py towers.db --out cellka_towers.sqlite
"""

import argparse
import os
import sqlite3
import time

ATTRIBUTION = (
    'Contains data from OpenCelliD (CC BY-SA 4.0, https://opencellid.org), '
    'radiocells.org/openBmap (ODbL, https://radiocells.org), '
    'Mozilla Location Service archive (CC0). '
    'Derived database must be shared under CC BY-SA 4.0.'
)

APP_SCHEMA = """
CREATE TABLE towers (
  radio TEXT NOT NULL,
  mcc INTEGER NOT NULL,
  mnc INTEGER NOT NULL,
  area INTEGER NOT NULL,
  cell INTEGER NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  range_m INTEGER,
  confidence REAL NOT NULL,
  PRIMARY KEY (radio, mcc, mnc, area, cell)
) WITHOUT ROWID;
CREATE INDEX idx_towers_mcc_mnc ON towers(mcc, mnc);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('db', help='путь к towers.db')
    ap.add_argument('--out', required=True, help='куда записать базу для приложения')
    args = ap.parse_args()

    src = sqlite3.connect(args.db)
    if os.path.exists(args.out):
        os.remove(args.out)
    dst = sqlite3.connect(args.out)
    dst.executescript(APP_SCHEMA)
    dst.execute('PRAGMA journal_mode=WAL')

    rows = src.execute(
        'SELECT radio, mcc, mnc, area, cell, lat, lon, range_m, confidence'
        ' FROM towers_merged')
    total = 0
    batch = []
    for row in rows:
        batch.append(row)
        if len(batch) >= 10_000:
            dst.executemany('INSERT INTO towers VALUES (?,?,?,?,?,?,?,?,?)', batch)
            total += len(batch)
            batch.clear()
    if batch:
        dst.executemany('INSERT INTO towers VALUES (?,?,?,?,?,?,?,?,?)', batch)
        total += len(batch)

    counts = dict(src.execute(
        'SELECT source, COUNT(*) FROM raw_towers GROUP BY source'))
    dst.executemany('INSERT INTO meta VALUES (?,?)', [
        ('generated_at', str(int(time.time()))),
        ('attribution', ATTRIBUTION),
        ('source_counts', ','.join(f'{k}:{v}' for k, v in sorted(counts.items()))),
        ('total_towers', str(total)),
    ])
    dst.commit()
    dst.execute('VACUUM')
    print(f'OK: {total} сот → {args.out} '
          f'({os.path.getsize(args.out) / 1e6:.1f} МБ)')


if __name__ == '__main__':
    main()
