-- Сырой слой: записи из всех источников без дедупликации
CREATE TABLE IF NOT EXISTS raw_towers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL,        -- opencellid | mls | openbmap
  radio TEXT NOT NULL,         -- GSM | UMTS | LTE | NR | CDMA | UNKNOWN
  mcc INTEGER NOT NULL,
  mnc INTEGER NOT NULL,
  area INTEGER NOT NULL,       -- LAC (GSM/UMTS) или TAC (LTE/NR)
  cell INTEGER NOT NULL,       -- CID / CI / NCI
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  range_m INTEGER,             -- оценка радиуса покрытия/неточности
  samples INTEGER,             -- количество наблюдений
  created_at INTEGER,
  updated_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_raw_key
  ON raw_towers(radio, mcc, mnc, area, cell);

-- Мерж: одна запись на соту, лучшая оценка координаты
CREATE TABLE IF NOT EXISTS towers_merged (
  radio TEXT NOT NULL,
  mcc INTEGER NOT NULL,
  mnc INTEGER NOT NULL,
  area INTEGER NOT NULL,
  cell INTEGER NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  range_m INTEGER,
  samples INTEGER,
  updated_at INTEGER,
  sources TEXT NOT NULL,       -- через запятую: "opencellid,mls"
  confidence REAL NOT NULL,    -- 0.05 .. 0.95
  PRIMARY KEY (radio, mcc, mnc, area, cell)
);
