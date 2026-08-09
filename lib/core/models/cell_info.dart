/// Модель информации о базовой станции сотовой сети,
/// полученной через TelephonyManager (Android).
class CellInfo {
  final String technology; // GSM / UMTS / LTE / NR
  final int? mcc;
  final int? mnc;
  final int? lac; // LAC (2G/3G) или TAC (LTE/NR)
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

  const CellInfo({
    required this.technology,
    this.mcc,
    this.mnc,
    this.lac,
    this.cid,
    this.pci,
    this.band,
    this.rsrp,
    this.rsrq,
    this.rssi,
    this.sinr,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'technology': technology,
        'mcc': mcc,
        'mnc': mnc,
        'lac': lac,
        'cid': cid,
        'pci': pci,
        'band': band,
        'rsrp': rsrp,
        'rsrq': rsrq,
        'rssi': rssi,
        'sinr': sinr,
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
      };

  factory CellInfo.fromJson(Map<String, dynamic> json) => CellInfo(
        technology: json['technology'] as String,
        mcc: json['mcc'] as int?,
        mnc: json['mnc'] as int?,
        lac: json['lac'] as int?,
        cid: json['cid'] as int?,
        pci: json['pci'] as int?,
        band: json['band'] as int?,
        rsrp: json['rsrp'] as int?,
        rsrq: json['rsrq'] as int?,
        rssi: json['rssi'] as int?,
        sinr: json['sinr'] as int?,
        timestamp: DateTime.parse(json['timestamp'] as String),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}
