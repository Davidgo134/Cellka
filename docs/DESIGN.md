# Cellka — Дизайн-документ

## Концепция

Главный экран — спутниковая карта во весь экран. Пользователь сразу видит:
- свою геопозицию;
- маркер текущей обслуживающей соты и линию-связку до неё;
- компактный signal strip с параметрами текущего сигнала.

Никаких онбордингов — ценность в данных с первой секунды.

## Экраны

### 1. Map Screen (главный)

```
┌─────────────────────────────┐
│  [спутниковая карта]        │
│      📍 ты ——— 📡 сота      │
│  🔥 heatmap-точки трека     │
│           [🎯][▶] FAB-стек  │
├─────────────────────────────┤
│ LTE B7 · PCI 142 · -87 dBm  │ ← signal strip
│ MTS 250-01 · TAC 12345      │
└─────────────────────────────┘
```

- **Линия от пользователя до текущей соты** — киллер-фича: на спутнике видно, к какой физической вышке ты подключён.
- **Signal strip**: технология, band, PCI, RSRP с цветовой индикацией, живой мини-график уровня.
- **FAB-стек**: центрирование GPS, запись трека (play/pause), переключатель слоёв (спутник/гибрид/heatmap).
- Тап по пину соседней соты → bottom sheet с параметрами.

### 2. Cell Details

- Верхняя треть — мини-карта со спутника, пин соты + позиция пользователя.
- Таблица: MCC/MNC, TAC, CI, eNB ID, PCI, EARFCN, band, RSRP/RSRQ/RSSI/SINR.
- График RSRP за последние N минут.
- Список соседних сот с сортировкой по уровню.

### 3. Tracks / History

- Список треков: дата, дистанция, число точек, оператор.
- Тап → трек на карте, точки окрашены по RSRP.
- Свайп → экспорт GeoJSON/CSV, удаление.
- (Post-MVP) Timeline-скраббер: двигаешь ползунок — точка едет по треку, strip показывает параметры сети в тот момент.

### 4. Settings

- Провайдер карты: Yandex / Google (через MapProvider).
- Слой по умолчанию: спутник / гибрид.
- Интервал логирования: 1с / 5с / 10с.
- Пороговые цвета heatmap.
- Экспорт/импорт БД.
- Тема (тёмная по умолчанию).

## Цикл сбора данных

```
Foreground Service (Android):
  каждые N секунд:
    1. TelephonyManager.getAllCellInfo()
    2. Geolocator → lat/lon/accuracy/speed
    3. merge → MeasurementPoint
    4. → sqflite (batch insert, транзакции по 50–100 точек)
    5. → event bus → UI
  + TelephonyCallback → мгновенное событие при handover
```

- Запись реже при неподвижности (скорость < 1 км/ч и сота не менялась) — экономия батареи.
- Handover-события логируются отдельным типом записи.

## Визуальный язык

- Тёмная тема по умолчанию.
- Акцент: deepOrange (читается на спутниковой подложке).
- Маркеры сот по технологии: LTE — оранжевый, NR — фиолетовый, UMTS — голубой, GSM — серый.
- Heatmap: градиент зелёный (> -80 dBm) → красный (< -110 dBm), прозрачность 60%.
- Моноширинный шрифт для числовых значений.

## Схема БД

```sql
CREATE TABLE measurements (
  id INTEGER PRIMARY KEY,
  track_id INTEGER REFERENCES tracks(id),
  timestamp INTEGER NOT NULL,
  lat REAL NOT NULL, lon REAL NOT NULL,
  accuracy REAL, speed REAL,
  technology TEXT, mcc INTEGER, mnc INTEGER,
  tac INTEGER, ci INTEGER, pci INTEGER,
  earfcn INTEGER, band INTEGER,
  rsrp INTEGER, rsrq INTEGER, rssi INTEGER, sinr INTEGER,
  is_registered INTEGER,
  event TEXT  -- null | 'handover' | 'cell_change'
);

CREATE TABLE tracks (
  id INTEGER PRIMARY KEY,
  started_at INTEGER, ended_at INTEGER,
  distance_m REAL, point_count INTEGER,
  operator TEXT
);
```

## MVP scope

Делаем: карта-спутник + текущая сота + signal strip + запись трека + экспорт GeoJSON.
Откладываем: графики, timeline-скраббер, community-базу сот, iOS.
