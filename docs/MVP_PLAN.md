# Cellka MVP — план работ

Чек-лист отслеживания прогресса. Отмечаем `[x]` по мере выполнения.

**Критерий готовности MVP:** установил APK → видишь спутниковую карту, свою соту, записал трек, экспортнул GeoJSON.

## Фаза 0. Фундамент
- [x] Репозиторий создан
- [x] README, ARCHITECTURE.md, DESIGN.md
- [x] Скелет Flutter-проекта (`main.dart`, модели)
- [x] Android-обвязка запушена (manifest, gradle, MainActivity, ресурсы). Локально/в CI выполняется `flutter create` для gradle wrapper
- [x] GitHub Actions: CI-сборка APK (debug) на каждый push
- [x] Фикс CI: Java 21 + Gradle 8.14 + AGP 8.11.1 + Kotlin 2.2.20

## Фаза 1. Telephony-слой
- [x] Android permissions: `ACCESS_FINE_LOCATION`, `READ_PHONE_STATE` в манифесте + рантайм-запрос (`PermissionService`)
- [x] Kotlin: `CellInfoPlugin` (MethodChannel `cellka/telephony`) — чтение `TelephonyManager.getAllCellInfo()` + `getOperatorInfo()`
- [x] Маппинг `CellInfoLte` → модель (TAC, CI, PCI, EARFCN, RSRP/RSRQ/RSSI/SINR, TA, bandwidth)
- [x] Маппинг `CellInfoNr` (5G), `CellInfoWcdma`, `CellInfoGsm` (+ CDMA, TD-SCDMA)
- [x] Dart-слой: `TelephonyService` + polling-стрим (1с) + `BandMapper` (bandFor с именованными параметрами) с юнит-тестами
- [x] Тест на реальном девайсе: данные приходят, поля не null
- [x] Фикс контракта: регистрация `CellInfoPlugin.registerWith(engine, context)`; fromMap читает ключ `technology`; UMTS/TDSCDMA в bandFor

## Фаза 2. Карта
- [x] ~~yandex_mapkit~~ → flutter_map (Yandex ограничил спутник своими приложениями)
- [x] Подложки циклом: Esri World Imagery (спутник) → гибрид (Esri + подписи) → OSM (схема); атрибуция на карте
- [x] Маркеры вышек: значки-вышки с зума 13, ниже — точки; тап → карточка; heatmap и круг точности — CircleMarker в метрах; линия к вышке — Polyline
- [x] Позиция пользователя — свой маркер из geolocator-стрима
- [x] yandex_mapkit удалён из pubspec и MainActivity (gradle-обвязка maps.mobile — мёртвый груз до чистки build.gradle)

## Фаза 3. Signal strip + текущая сота
- [x] Виджет signal strip: технология, band, PCI, RSRP с цветовой индикацией
- [x] Индикаторы статуса: GPS-fix, запись трека
- [x] Тап по strip → экран Cell Details
- [x] Cell Details простым языком: карточка-резюме уровня сигнала + (i)-объяснения всех параметров
- [x] Про-параметры: eNodeB/сектор из CI, дуплекс TDD/FDD, частоты RX/TX из EARFCN, имя диапазона, RSSI; секции Идентификация/Радио/Сигнал
- [x] Список соседних сот
- [ ] Скорость соединения, CA-агрегации — после MVP

## Фаза 4. Запись треков + БД
- [x] `sqflite`: схема `tracks` + `measurements` + `handovers` (FK с каскадом)
- [x] Foreground-запись точек через geolocator FGS с уведомлением
- [x] Batch-insert транзакциями: флаш каждые 50 точек или 10 с
- [x] Пропуск записи при неподвижности (<5 м, та же сота, <15 с)
- [x] Логирование handover-событий
- [x] Фикс: рантайм-запрос POST_NOTIFICATIONS (Android 13+)

## Фаза 4.5. Линия к вышке (OpenCelliD)
- [x] `TowerService`: кэш → локальный дамп → API `cell/get`; диагностика статусов
- [x] Ключ OpenCelliD: секрет в CI + `--dart-define`
- [!] OpenCelliD: `cell/get`/`getInArea` — только для белых ключей; ключ белеет через вклад замерами
- [x] Фикс UX: линия стирается сразу при смене соты; постоянный чип статуса вышки над signal strip

## Фаза 4.6. Своё определение позиции вышки + вклад в OpenCelliD
- [x] `CellEstimator`: взвешенный центроид по замерам (вес 10^(RSRP/10), accuracy ≤ 50 м)
- [x] Оценочная позиция на карте при отсутствии соты в OpenCelliD (от ≥5 замеров)
- [x] Опт-in отправка трека в OpenCelliD (`measure/uploadJson`, фолбэк `measure/add`)

## Фаза 4.7. Слой вышек по операторам
- [x] Схема БД v4: таблица `towers` + индексы
- [x] `TowerDownloadService`: дамп MCC 250 стримом → импорт; зеркало через workflow → GitHub Release
- [x] Автозагрузка базы при первом запуске + автообновление старше 7 дней (баннер с прогрессом сверху), слой включается сам
- [x] `TowerLayerSheet`: переключатели операторов, статус базы, атрибуция OpenCelliD (CC BY-SA)
- [x] Вьюпорт-загрузка: гистерезис зума, пропуск покрытого bbox, дебаунс камеры
- [x] Тап по вышке → карточка Tower Info + «К вышке»
- [ ] Кластеризация маркеров — после MVP
- [ ] Band/частоты у вышки из собственных замеров — после MVP

## Фаза 5. Отображение треков
- [x] Экран History: список, удаление свайпом
- [x] Просмотр трека: полилиния + точки по RSRP, авто-fit камеры (поверх спутника)
- [x] Heatmap-слой «Мои замеры»

## Фаза 6. Экспорт
- [x] Экспорт трека в GeoJSON и CSV
- [x] Share-интент из History и просмотра трека

## Фаза 7. Релиз MVP
- [x] Иконка приложения — генерация в CI (`tools/gen_icons.py`, PIL: столбики сигнала)
- [x] Release-сборка APK через CI (`.github/workflows/release.yml`, `flutter build apk --release`)
- [x] GitHub Release по тегу `v*` или ручному запуску с версией
- [x] Автоверсия из тега: v0.1.1 → versionName 0.1.1, versionCode 101 (major·10000 + minor·100 + patch)
- [x] Настоящий keystore (PKCS#12, RSA-2048, 30 лет): секреты KEYSTORE_BASE64/KEYSTORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD; без них — фолбэк на одноразовый CI-ключ
- [ ] Скриншоты в README
