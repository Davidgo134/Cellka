# Архитектура Cellka

## Слой карт (MapProvider)

Чтобы не завязываться жёстко на один картографический движок, вводится абстракция:

```dart
abstract class MapProvider {
  Widget buildMap({
    required CameraPosition initialPosition,
    required List<CellMarker> markers,
    required List<HeatmapPoint> heatmapPoints,
  });
}

class YandexMapProvider implements MapProvider { ... }
class GoogleMapProvider implements MapProvider { ... } // fallback / другие регионы
```

Выбор провайдера — через `AppConfig.mapProvider` (enum `yandex` / `google`), настраивается в настройках приложения.

## Получение данных о соте

Android: `TelephonyManager.getAllCellInfo()` + `PhoneStateListener` / `TelephonyCallback` (API 31+) для отслеживания смены соты в реальном времени. Доступ к точным идентификаторам (CID, PCI, TAC) требует разрешений `ACCESS_FINE_LOCATION` и `READ_PHONE_STATE`.

Модель данных:

```dart
class CellInfo {
  final String technology; // GSM/UMTS/LTE/NR
  final int? mcc;
  final int? mnc;
  final int? lac; // или tac для LTE/NR
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

## Хранилище

`sqflite` с таблицами `measurements` и `cells`. Экспорт в GeoJSON для совместимости с внешними ГИС-инструментами (QGIS, SAS.Planet и т.п.).

## Heatmap

Построение полигонов/точек с градиентом цвета по RSRP (например: зелёный > -80 dBm, жёлтый -80..-100, красный < -100), рендерится поверх спутникового слоя карты.

## Открытые вопросы

- Лицензирование API-ключа Yandex MapKit для community-сборок (каждый пользователь генерирует свой ключ, либо используется серверный прокси).
- Поддержка iOS (доступ к cell info на iOS сильно ограничен системой, потребуется CoreTelephony workaround или отказ от части функций).