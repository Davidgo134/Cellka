import 'package:flutter/widgets.dart';

/// Абстракция картографического провайдера.
/// Позволяет переключаться между Yandex MapKit и Google Maps
/// без изменения логики приложения.
abstract class MapProvider {
  Widget buildMap({
    required double centerLat,
    required double centerLon,
    required double zoom,
  });
}
