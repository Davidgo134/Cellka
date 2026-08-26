import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Локальная БД Cellka (sqflite).
/// Схема v3: tracks + measurements + handovers + tower_cache
/// + cell_estimates + settings.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'cellka.db';
  static const _dbVersion = 3;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tracks(
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            point_count INTEGER NOT NULL DEFAULT 0,
            distance_m REAL NOT NULL DEFAULT 0,
            operator TEXT,
            note TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE measurements(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            ts TEXT NOT NULL,
            lat REAL,
            lon REAL,
            accuracy REAL,
            speed REAL,
            bearing REAL,
            technology TEXT,
            registered INTEGER NOT NULL DEFAULT 0,
            mcc INTEGER,
            mnc INTEGER,
            tac INTEGER,
            lac INTEGER,
            ci INTEGER,
            nci INTEGER,
            pci INTEGER,
            psc INTEGER,
            bsic INTEGER,
            earfcn INTEGER,
            nrarfcn INTEGER,
            uarfcn INTEGER,
            arfcn INTEGER,
            band INTEGER,
            bandwidth INTEGER,
            rsrp INTEGER,
            rsrq INTEGER,
            rssi INTEGER,
            sinr INTEGER,
            dbm INTEGER,
            asu INTEGER,
            ta INTEGER
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_measurements_track ON measurements(track_id)',
        );
        await db.execute('''
          CREATE TABLE handovers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            ts TEXT NOT NULL,
            from_key TEXT,
            to_key TEXT,
            from_pci INTEGER,
            to_pci INTEGER,
            from_band INTEGER,
            to_band INTEGER,
            technology TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_handovers_track ON handovers(track_id)',
        );
        await _createTowerCache(db);
        await _createV3Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTowerCache(db);
        }
        if (oldVersion < 3) {
          await _createV3Tables(db);
        }
      },
    );
  }

  Future<void> _createTowerCache(Database db) {
    return db.execute('''
      CREATE TABLE IF NOT EXISTS tower_cache(
        cell_key TEXT PRIMARY KEY,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        range_m INTEGER,
        samples INTEGER,
        fetched_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createV3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cell_estimates(
        cell_key TEXT PRIMARY KEY,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        weight REAL NOT NULL DEFAULT 0,
        samples INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings(
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
