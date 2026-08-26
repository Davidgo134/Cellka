# Cellka MVP — план работ

Чек-лист отслеживания прогресса. Отмечаем `[x]` по мере выполнения.

**Критерий готовности MVP:** установил APK → видишь спутниковую карту, свою соту, записал трек, экспортнул GeoJSON.

## Фаза 0. Фундамент
- [x] Репозиторий создан
- [x] README, ARCHITECTURE.md, DESIGN.md
- [x] Скелет Flutter-проекта (`main.dart`, модели)
- [x] Android-обвязка запушена (manifest, gradle, MainActivity с MapKit, ресурсы). Локально/в CI выполняется `flutter create` для gradle wrapper и иконок
- [x] GitHub Actions: CI-сборка APK (debug) на каждый push
- [x] API-ключ Yandex MapKit получен и добавлен в секреты CI (`YANDEX_MAPKIT_API_KEY`)
- [x] Фикс CI: Java 21 + Gradle 8.14 + AGP 8.11.1 + Kotlin 2.2.20 (нативная библиотека MapKit собрана под class file 65 = Java 21)
- [x] Фикс CI: explicit-зависимость `maps.mobile:4.39.1-lite` (плагин тянет её как implementation и не экспортирует в classpath app-модуля)

## Фаза 1. Telephony-слой
- [x] Android permissions: `ACCESS_FINE_LOCATION`, `READ_PHONE_STATE` в манифесте + рантайм-запрос (`PermissionService`)
- [x] Kotlin: `CellInfoPlugin` (MethodChannel `cellka/telephony`) — чтение `TelephonyManager.getAllCellInfo()` + `getOperatorInfo()`
- [x] Маппинг `CellInfoLte` → модель (TAC, CI, PCI, EARFCN, RSRP/RSRQ/RSSI/SINR, TA, bandwidth)
- [x] Маппинг `CellInfoNr` (5G), `CellInfoWcdma`, `CellInfoGsm` (+ CDMA, TD-SCDMA)
- [x] Dart-слой: `TelephonyService` + polling-стрим (1с) + `BandMapper` (EARFCN→band) с юнит-тестами
- [x] Тест на реальном девайсе: данные приходят, поля не null (LTE B1 · PCI 180 · RSRP −95 · TAC/CI живые, T2 250-20)

## Фаза 2. Карта
- [x] Подключить `yandex_mapkit`, инициализация ключа (через BuildConfig в MainActivity)
- [x] `MapScreen`: слой карты во весь экран, user layer, FAB-стек
- [!] Спутник и гибрид Yandex MapKit недоступны сторонним приложениям («Allowed only for Yandex apps» в нативном SDK) — карта молча падает обратно в вектор

## Фаза 2.5. Смена движка карты (настоящий спутник)
- [x] Переход на flutter_map (чистый Dart, XYZ-тайлы) + latlong2
- [x] Подложки циклом: Esri World Imagery (спутник) → Esri + Reference labels (гибрид) → OSM (схема); атрибуция на карте
- [x] Маркеры вышек — tappable точки фиксированного размера; heatmap и круг точности — CircleMarker в метрах; линия к вышке — Polyline
- [x] Позиция пользователя — свой маркер из geolocator-стрима
- [ ] Удалить yandex_mapkit из зависимостей + MapKit init из MainActivity (cleanup, нативная сторона)

## Фаза 3. Signal strip + текущая сота
- [x] Виджет signal strip: технология, band, PCI, RSRP с цветовой индикацией
- [x] Индикаторы статуса: GPS-fix, запись трека
- [x] Тап по strip → экран Cell Details с таблицей параметров
- [x] Список соседних сот на экране деталей

## Фаза 3.5. Про-параметры соты (по мотивам CellMapper)
- [x] eNodeB + сектор из 28-битного LTE CI (ci>>8 / ci&0xFF)
- [x] Дуплекс TDD/FDD, частоты RX/TX (формулы EARFCN, TS 36.101), имя диапазона — BandMapper
- [x] RSSI в модели и на экране деталей (маппится плагином с Фазы 1)
- [x] Cell Details: секции Идентификация / Радио / Сигнал
- [ ] Скорость соединения, CA-агрегации — после MVP (отдельная история)

## Фаза 4. Запись треков + БД
- [x] `sqflite`: схема `tracks` + `measurements` + `handovers` (FK с каскадом)
- [x] Foreground-запись точек через geolocator FGS с уведомлением
- [x] Batch-insert транзакциями: флаш каждые 50 точек или 10 с
- [x] Логика «запись реже при неподвижности»: пропуск, если сдвиг <5 м, сота та же и прошло <15 с
- [x] FAB start/stop записи + SnackBar со статистикой
- [x] Логирование handover-событий (смена serving-соты)
- [x] Фикс: рантайм-запрос POST_NOTIFICATIONS перед стартом записи (Android 13+)

## Фаза 4.5. Линия к вышке (OpenCelliD)
- [x] `TowerService`: кэш → локальный дамп → API `cell/get`; диагностика статусов на девайсе
- [x] Ключ OpenCelliD: секрет `OPENCELLID_API_KEY` в CI + `--dart-define` в workflow
- [!] OpenCelliD: `cell/get`/`getInArea` — только для белых ключей; ключ белеет через вклад замерами
- [x] Фикс UX: линия стирается сразу при смене соты; постоянный чип статуса («нет в базе · оценка после ≥5 замеров» / «оценка, n замеров») над signal strip

## Фаза 4.6. Своё определение позиции вышки + вклад в OpenCelliD
- [x] `CellEstimator`: взвешенный центроид по нашим замерам (вес 10^(RSRP/10), accuracy ≤ 50 м), таблица `cell_estimates`
- [x] Оценочная позиция на карте, когда соты нет в OpenCelliD: белый контур + линия, показ от ≥5 замеров
- [x] Опт-in отправка трека в OpenCelliD: диалог при первой записи, `measure/uploadJson`; при 403 — фолбэк на `measure/add`; текст ошибки в UI

## Фаза 4.7. Слой вышек по операторам
- [x] Схема БД v4: таблица `towers` + индексы
- [x] `TowerDownloadService`: дамп MCC 250 стримом → gunzip → CSV → batch; зеркало через workflow `towers_db.yml` → GitHub Release `towers-db` (приложение качает с GitHub, OpenCelliD — фолбэк)
- [x] `TowerLayerSheet`: мастер-переключатель, чекбоксы операторов, статус базы, атрибуция OpenCelliD (CC BY-SA)
- [x] Вьюпорт-загрузка с анти-мерцанием: гистерезис зума 12/11, пропуск внутри покрытого bbox, дебаунс камеры
- [x] Тап по вышке → карточка Tower Info (оператор, radio, Cell ID, TAC, радиус, samples, обновлена, координаты, «К вышке»)
- [ ] Кластеризация маркеров с счётчиком — после MVP
- [ ] Band/частоты у вышки из собственных замеров — после MVP

## Фаза 5. Отображение треков
- [x] Экран History: список треков, удаление свайпом с подтверждением
- [x] Просмотр трека: полилиния + точки по RSRP, авто-fit камеры
- [x] Heatmap-слой «Мои замеры» на основной карте

## Фаза 6. Экспорт
- [x] Экспорт трека в GeoJSON и CSV
- [x] Share-интент из History и просмотра трека (share_plus)

## Фаза 7. Релиз MVP
- [ ] Иконка приложения
- [ ] Release-сборка APK через CI
- [ ] GitHub Release v0.1.0 с APK
- [ ] Скриншоты в README
