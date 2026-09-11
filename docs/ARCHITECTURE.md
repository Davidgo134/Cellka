# Архитектура Cellka

Документ отражает реальное состояние кода (после миграции с Yandex MapKit на flutter_map).

## Слой карт

Ранее планировалась абстракция `MapProvider` (Yandex/Google) — от неё отказались: Yandex ограничил спутниковые тайлы собственными приложениями, и проект использует `flutter_map` напрямую (`lib/core/map/map_provider.dart` — тонкий конфиг слоёв, не абстракция движка).

- Движок: `flutter_map` ^7 + `latlong2`
- Подложки циклом: Esri World Imagery (спутник) → гибрид (Esri + подписи) → OSM (схема); атрибуция рендерится на карте (лицензионно обязательна)
- Маркеры: позиция пользователя из geolocator-стрима + `CircleMarker` точности в метрах; маркеры вышек; линия к обслуживающей соте — `Polyline`
- Кластеризация слоя вышек: `flutter_map_marker_cluster` (`MarkerClusterLayerWidget`), пузырь-счётчик, тап по кластеру приближает карту
- Вьюпорт-загрузка вышек: `TowersRepository.inBbox` — гистерезис зума (показ с 12, скрытие ниже 11), дебаунс камеры, пропуск уже покрытого bbox

## Получение данных о соте

Android: Kotlin-плагин `CellInfoPlugin` (MethodChannel `cellka/telephony`), чтение `TelephonyManager.getAllCellInfo()` + `getOperatorInfo()`. Требуются `ACCESS_FINE_LOCATION` и `READ_PHONE_STATE`; на Android 13+ добавлен рантайм-запрос `POST_NOTIFICATIONS` (`PermissionService`).

Dart: `TelephonyService` + polling-стрим раз в 1 с; `BandMapper` (`bandFor` с именованными параметрами, EARFCN/NRArfcn → band) покрыт юнит-тестами.

Модель данных:

```dart
class CellInfo {
  final String technology; // GSM/UMTS/LTE/NR (+ CDMA, TD-SCDMA)
  final int? mcc;
  final int? mnc;
  final int? lac; // или TAC для LTE/NR
  final int? cid;
  final int? pci;
  final int? band;
  final int? rsrp;
  final int? rsrq;
  final int? rssi;
  final int? sinr;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
}
```

Про-вычисления поверх сырых полей: eNodeB и сектор из CI, дуплекс TDD/FDD, частоты RX/TX из EARFCN, имя диапазона.

## Хранилище

`sqflite`:

- `tracks` + `measurements` + `handovers` (FK с каскадным удалением) — треки записи, точки, события хэндовера
- `towers` (схема v4) + индексы — локальная база вышек из дампа OpenCelliD (MCC 250). Дамп зеркалируется CI-workflow в GitHub Release, приложение скачивает его при первом запуске и автообновляет раз в 7 дней

ForeGround-запись: batch-insert транзакциями (флаш каждые 50 точек или 10 с), пропуск точек при неподвижности (<5 м, та же сота, <15 с).

Экспорт треков в GeoJSON и CSV — совместимость с QGIS, SAS.Planet и т.п.; шаринг через `share_plus`.

## Вышки: позиция и краудсорсинг

`TowerService` разрешает позицию соты в порядке: кэш → локальный дамп → OpenCelliD API `cell/get`. Ключ API — секрет в CI + `--dart-define`; `cell/get`/`getInArea` доступны только «белым» ключам, ключ белеет за вклад замерами.

`CellEstimator` — собственная оценка позиции при отсутствии соты в базе: взвешенный центроид по замерам (вес 10^(RSRP/10), только точки с accuracy ≤ 50 м), оценка показывается на карте от ≥5 замеров. Опт-in выгрузка трека в OpenCelliD (`measure/uploadJson`, фолбэк `measure/add`).

## Heatmap

Слой «Мои замеры»: градиент по RSRP (зелёный > -80 dBm, жёлтый -80..-100, красный < -100) поверх карты; просмотр трека — полилиния с точками, окрашенными по RSRP, авто-fit камеры.

## CI/CD

GitHub Actions:

- CI на каждый push: analyze + тесты + debug APK (Java 21, Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20)
- `release.yml`: релиз по тегу `v*` или вручную; автоверсия из тега (versionCode = major·10000 + minor·100 + patch); подпись keystore из секретов (PKCS#12, RSA-2048), фолбэк — одноразовый CI-ключ
- Иконка генерируется в CI (`tools/gen_icons.py`, PIL)
- Зеркало дампа OpenCelliD → GitHub Release (отдельный workflow)

## Открытые вопросы

- iOS: доступ к cell info через CoreTelephony сильно ограничен — фокус Android-first, iOS отложен
- При росте локальной базы вышек: pre-clustered векторные тайлы (MBTiles), собираемые тем же CI-зеркалом, вместо отрисовки тысяч маркеров на клиенте
