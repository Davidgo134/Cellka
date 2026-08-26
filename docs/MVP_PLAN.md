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
- [x] `MapScreen`: слой карты во весь экран
- [x] User location layer (точка + авто-зум)
- [x] FAB: центрирование на GPS
- [x] Переключатель слоёв: спутник / гибрид
- [!] Спутник и гибрид Yandex MapKit недоступны сторонним приложениям («Allowed only for Yandex apps» в нативном SDK) — карта молча падает обратно в вектор. Решение движка отдельно: вариант MapLibre + Esri World Imagery (Фаза 2.5)

## Фаза 3. Signal strip + текущая сота
- [x] Виджет signal strip: технология, band, PCI, RSRP с цветовой индикацией
- [x] Индикаторы статуса: GPS-fix, запись трека
- [x] Тап по strip → экран Cell Details с таблицей параметров
- [x] Список соседних сот на экране деталей

## Фаза 4. Запись треков + БД
- [x] `sqflite`: схема `tracks` + `measurements` + `handovers` (FK с каскадом)
- [x] Foreground-запись точек через geolocator FGS с уведомлением (интервал 2с; экран настроек — после MVP)
- [x] Batch-insert транзакциями: флаш каждые 50 точек или 10 с
- [x] Логика «запись реже при неподвижности»: пропуск, если сдвиг <5 м, сота та же и прошло <15 с
- [x] FAB start/stop записи + SnackBar со статистикой
- [x] Логирование handover-событий (смена serving-соты)
- [x] Фикс: рантайм-запрос POST_NOTIFICATIONS перед стартом записи (Android 13+, иначе FGS геолокации мог не стартовать)

## Фаза 4.5. Линия к вышке (OpenCelliD)
- [x] `TowerService`: OpenCelliD `cell/get` + sqflite-кэш `tower_cache` (схема БД v2)
- [x] Линия пользователь→вышка + маркер-круг на карте, цвет по RSRP, обновление при handover
- [x] Диагностика статусов lookup на девайсе: нет ключа / 401 / 403 / не найдена / ошибка сети (SnackBar один раз на статус)
- [x] Ключ OpenCelliD: секрет `OPENCELLID_API_KEY` в CI + `--dart-define` в workflow
- [!] OpenCelliD: `cell/get` и `getInArea` — только для белых ключей; ключ белеет автоматически, когда приложение делится замерами. `getInArea`: 1 сота = 1 кредит, лимит 1000/день → полный слой вышек делать из bulk-дампа страны, а не из живого API

## Фаза 4.6. Своё определение позиции вышки + вклад в OpenCelliD
- [x] `CellEstimator`: взвешенный центроид по нашим замерам (вес 10^(RSRP/10), только accuracy ≤ 50 м), таблица `cell_estimates` (схема БД v3)
- [x] Оценочная позиция на карте, когда соты нет в OpenCelliD: белый контур + линия, показ от ≥5 замеров
- [x] Опт-in отправка трека в OpenCelliD: диалог при первой записи, `measure/uploadJson` (multipart, один JSON на трек), настройка в таблице `settings`
- [x] Аплоадер возвращает текст ошибки (HTTP-код/ответ/таймаут); при 403 — фолбэк на точечный `measure/add` (белый ключ не нужен)

## Фаза 4.7. Слой вышек по операторам
- [x] Схема БД v4: таблица `towers` (radio/mcc/mnc/area/cell + координаты + samples), индексы по lat/lon
- [x] `TowerDownloadService`: скачивание дампа MCC 250 стримом → gunzip на лету → парсинг CSV → batch-вставка по 1000, прогресс в UI
- [x] `TowerLayerSheet`: мастер-переключатель, чекбоксы операторов РФ с цветами, статус базы, атрибуция OpenCelliD (CC BY-SA)
- [x] Вьюпорт-загрузка: `onCameraPositionChanged(finished)` → `getVisibleRegion` + запас 25% → кружки по цвету оператора
- [x] Анти-мерцание слоя: гистерезис зума (показ ≥12, скрытие <11), пропуск перезагрузки внутри уже покрытого bbox
- [x] Тап по вышке → карточка Tower Info (оператор, radio, Cell ID, TAC, радиус, samples, обновлена, координаты, «К вышке»)
- [x] Зеркало базы: workflow `towers_db.yml` → GitHub Release `towers-db`; приложение качает с GitHub, OpenCelliD — фолбэк
- [ ] Кластеризация маркеров с счётчиком (как у CellMapper) — после MVP
- [ ] Band/частоты у вышки из собственных замеров (в дампе OpenCelliD их нет) — после MVP

## Фаза 5. Отображение треков
- [x] Экран History: список треков (дата, дистанция, точки, оператор, длительность), удаление свайпом с подтверждением
- [x] Просмотр трека: полилиния маршрута + точки с цветом по RSRP, авто-зум по bbox трека
- [x] Heatmap-слой «Мои замеры» на основной карте: точки из measurements по цвету сигнала, вьюпорт-загрузка, переключатель в шите слоёв

## Фаза 6. Экспорт
- [x] Экспорт трека в GeoJSON (FeatureCollection: LineString маршрута + Point'ы с параметрами сети)
- [x] Экспорт в CSV (все поля замеров)
- [x] Share-интент: системный Share Sheet из History и просмотра трека (share_plus, файлы во временной директории)

## Фаза 7. Релиз MVP
- [ ] Иконка приложения
- [ ] Release-сборка APK через CI
- [ ] GitHub Release v0.1.0 с APK
- [ ] Скриншоты в README
