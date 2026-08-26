#!/usr/bin/env python3
"""Cellka towerdb: инжест сырых выгрузок в нормализованную SQLite-таблицу raw_towers.

Источники:
  opencellid — дамп OpenCelliD (CSV, CC BY-SA 4.0)
  mls        — архивный экспорт Mozilla Location Service (CSV, CC0)
  openbmap   — radiocells.org cells dump (CSV с ';', ODbL)

Пример:
  python ingest.py --source opencellid towers.db data/opencellid.csv.gz
"""

import argparse
import csv
import gzip
import os
import sqlite3
import sys

RADIO_MAP = {
    'GSM': 'GSM',
    'UMTS': 'UMTS',
    'WCDMA': 'UMTS',
    'LTE': 'LTE',
    'NR': 'NR',
    'NBIOT': 'LTE',
    'CDMA': 'CDMA',
}

SCHEMA_PATH = os.path.join(os.path.dirname(__file__), 'schema.sql')
BATCH = 10_000


def norm_radio(raw):
    return RADIO_MAP.get((raw or '').strip().upper())


def open_maybe_gzip(path):
    if path.endswith('.gz'):
        return gzip.open(path, 'rt', newline='', encoding='utf-8', errors='replace')
    return open(path, newline='', encoding='utf-8', errors='replace')


def to_int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return None


def to_float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def iter_opencellid_like(path):
    """Формат OpenCelliD/MLS:
    radio,mcc,net,area,cell,unit,lon,lat,range,samples,changeable,created,updated,averageSignal
    """
    with open_maybe_gzip(path) as f:
        for row in csv.DictReader(f):
            radio = norm_radio(row.get('radio'))
            lat, lon = to_float(row.get('lat')), to_float(row.get('lon'))
            mcc, mnc = to_int(row.get('mcc')), to_int(row.get('net'))
            area, cell = to_int(row.get('area')), to_int(row.get('cell'))
            if None in (radio, lat, lon, mcc, mnc, area, cell):
                continue
            yield dict(radio=radio, mcc=mcc, mnc=mnc, area=area, cell=cell,
                       lat=lat, lon=lon,
                       range_m=to_int(row.get('range')),
                       samples=to_int(row.get('samples')),
                       created_at=to_int(row.get('created')),
                       updated_at=to_int(row.get('updated')))


def iter_openbmap(path):
    """radiocells.org: lat;lon;mcc;mnc;lac;cellid (исторически в основном GSM)."""
    with open_maybe_gzip(path) as f:
        reader = csv.reader(f, delimiter=';')
        for row in reader:
            if len(row) < 6 or row[0].strip().lower() in ('lat', 'latitude'):
                continue
            lat, lon = to_float(row[0]), to_float(row[1])
            mcc, mnc = to_int(row[2]), to_int(row[3])
            area, cell = to_int(row[4]), to_int(row[5])
            if None in (lat, lon, mcc, mnc, area, cell):
                continue
            yield dict(radio='UNKNOWN', mcc=mcc, mnc=mnc, area=area, cell=cell,
                       lat=lat, lon=lon,
                       range_m=None, samples=None,
                       created_at=None, updated_at=None)


ITERATORS = {
    'opencellid': iter_opencellid_like,
    'mls': iter_opencellid_like,
    'openbmap': iter_openbmap,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source', required=True, choices=sorted(ITERATORS))
    ap.add_argument('db', help='путь к towers.db')
    ap.add_argument('dump', help='путь к CSV/CSV.GZ дампу')
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)
    with open(SCHEMA_PATH, encoding='utf-8') as f:
        conn.executescript(f.read())
    conn.execute('PRAGMA journal_mode=WAL')
    conn.execute('PRAGMA synchronous=OFF')

    it = ITERATORS[args.source](args.dump)
    total, skipped_radio = 0, 0
    batch = []

    for rec in it:
        if args.source == 'openbmap' and rec['radio'] is None:
            skipped_radio += 1
            continue
        batch.append((args.source, rec['radio'], rec['mcc'], rec['mnc'],
                      rec['area'], rec['cell'], rec['lat'], rec['lon'],
                      rec['range_m'], rec['samples'],
                      rec['created_at'], rec['updated_at']))
        if len(batch) >= BATCH:
            conn.executemany(
                'INSERT INTO raw_towers (source, radio, mcc, mnc, area, cell,'
                ' lat, lon, range_m, samples, created_at, updated_at)'
                ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', batch)
            total += len(batch)
            batch.clear()
            print(f'  {total} записей...', flush=True)

    if batch:
        conn.executemany(
            'INSERT INTO raw_towers (source, radio, mcc, mnc, area, cell,'
            ' lat, lon, range_m, samples, created_at, updated_at)'
            ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', batch)
        total += len(batch)

    conn.commit()
    print(f'OK: {args.source} → {total} записей в {args.db}')
    if skipped_radio:
        print(f'  пропущено без radio: {skipped_radio}', file=sys.stderr)


if __name__ == '__main__':
    main()
