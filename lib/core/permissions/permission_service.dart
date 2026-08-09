import 'package:permission_handler/permission_handler.dart';

/// Запрос рантайм-разрешений, необходимых для чтения CellInfo и GPS.
///
/// Доступ к идентификаторам сот (CID/PCI/TAC) на Android требует
/// ACCESS_FINE_LOCATION; данные оператора — READ_PHONE_STATE.
class PermissionService {
  Future<bool> get hasTelephonyPermissions async =>
      await Permission.locationWhenInUse.isGranted &&
      await Permission.phone.isGranted;

  /// Запрашивает разрешения. Возвращает true, если всё выдано.
  Future<bool> ensureTelephonyPermissions() async {
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.phone,
    ].request();

    return statuses[Permission.locationWhenInUse]?.isGranted == true &&
        statuses[Permission.phone]?.isGranted == true;
  }

  /// Пользователь навсегда запретил разрешение — предложить открыть настройки.
  Future<bool> get isPermanentlyDenied async =>
      await Permission.locationWhenInUse.isPermanentlyDenied ||
      await Permission.phone.isPermanentlyDenied;

  Future<void> openSettings() => openAppSettings();
}
