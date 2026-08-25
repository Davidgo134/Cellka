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

## Фаза 5. Отображение треков
- [ ] Экран History: список треков (дата, дистанция, точки, оператор)
- [ ] Отрисовка трека на карте, точки с цветом по RSRP
- [ ] Heatmap-точки поверх спутника

## Фаза 6. Экспорт
- [ ] Экспорт трека в GeoJSON
- [ ] Экспорт в CSV
- [ ] Share-интент (отправить файл)

## Фаза 7. Релиз MVP
- [ ] Иконка приложения
- [ ] Release-сборка APK через CI
- [ ] GitHub Release v0.1.0 с APK
- [ ] Скриншоты в README
