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

## Фаза 1. Telephony-слой
- [x] Android permissions: `ACCESS_FINE_LOCATION`, `READ_PHONE_STATE` в манифесте + рантайм-запрос (`PermissionService`)
- [x] Kotlin: `CellInfoPlugin` (MethodChannel `cellka/telephony`) — чтение `TelephonyManager.getAllCellInfo()` + `getOperatorInfo()`
- [x] Маппинг `CellInfoLte` → модель (TAC, CI, PCI, EARFCN, RSRP/RSRQ/RSSI/SINR, TA, bandwidth)
- [x] Маппинг `CellInfoNr` (5G), `CellInfoWcdma`, `CellInfoGsm` (+ CDMA, TD-SCDMA)
- [x] Dart-слой: `TelephonyService` + polling-стрим (1с) + `BandMapper` (EARFCN→band) с юнит-тестами
- [ ] Тест на реальном девайсе: данные приходят, поля не null

## Фаза 2. Карта
- [ ] Подключить `yandex_mapkit`, инициализация ключа
- [ ] `MapScreen`: спутниковый слой во весь экран
- [ ] User location layer (точка + точность)
- [ ] FAB: центрирование на GPS
- [ ] Переключатель слоёв: спутник / гибрид

## Фаза 3. Signal strip + текущая сота
- [ ] Виджет signal strip: технология, band, PCI, RSRP с цветовой индикацией
- [ ] Индикаторы статуса: GPS-fix, запись трека
- [ ] Тап по strip → экран Cell Details с таблицей параметров
- [ ] Список соседних сот на экране деталей

## Фаза 4. Запись треков + БД
- [ ] `sqflite`: схема `measurements` + `tracks` (по DESIGN.md)
- [ ] Foreground service: запись точек с интервалом из настроек
- [ ] Batch-insert транзакциями по 50–100 точек
- [ ] Логика «запись реже при неподвижности» (<1 км/ч, сота не менялась)
- [ ] FAB play/pause записи
- [ ] Логирование handover-событий

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
