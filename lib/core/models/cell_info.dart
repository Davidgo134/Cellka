/// Модель информации о базовой станции сотовой сети,
/// полученной через TelephonyManager (Android).
class CellInfo {
  final String technology; // GSM / UMTS / LTE / NR / TDSCDMA / CDMA
  final bool registered; // true — обслуживающая сота, false — соседняя
  final int? mcc;
  final int? mnc;
  final int? lac; // LAC (GSM/UMTS)
  final int? tac; // TAC (LTE/NR)
  final int? ci; // Cell ID
  final int? nci; // NR Cell Identity (5G)
  final int? pci; // Physical Cell ID (LTE/NR)
  final int? psc; // Primary Scrambling Code (UMTS)
  final int? bsic; // Base Station Identity Code (GSM)
  final int? earfcn; // LTE
  final int? nrarfcn; // NR
  final int? uarfcn; // UMTS
  final int? arfcn; // GSM
  final int? band; // вычисляется BandMapper'ом на Dart-стороне
  final int? bandwidth; // Гц (LTE, API 28+)
  final int? rsrp;
  final int? rsrq;
  final int? rssi;
  final int? sinr;
  final int? dbm;
  final int? asu;
  final int? ta; // Timing Advance
  final DateTime timestamp;
  final double? latitude; // заполняется при записи трека
  final double? longitude;

  const CellInfo({
    required this.technology,
    this.registered = false,
    this.mcc,
    this.mnc,
    this.lac,
    this.tac,
    this.ci,
    this.nci,
    this.pci,
    this.psc,
    this.bsic,
    this.earfcn,
    this.nrarfcn,
    this.uarfcn,
    this.arfcn,
    this.band,
    this.bandwidth,
    this.rsrp,
    this.rsrq,
    this.rssi,
    this.sinr,
    this.dbm,
    this.asu,
    this.ta,
    required this.timestamp,
    this.latitude,
    this.longitude,
  });

  /// Из данных MethodChannel (платформенная сторона Android).
  factory CellInfo.fromMap(Map<String, dynamic> map) => CellInfo(
        technology: map['technology'] as String? ?? 'UNKNOWN',
        registered: map['registered'] as bool? ?? false,
        mcc: _int(map['mcc']),
        mnc: _int(map['mnc']),
        lac: _int(map['lac']),
        tac: _int(map['tac']),
        ci: _int(map['ci']),
        nci: _int(map['nci']),
        pci: _int(map['pci']),
        psc: _int(map['psc']),
        bsic: _int(map['bsic']),
        earfcn: _int(map['earfcn']),
        nrarfcn: _int(map['nrarfcn']),
        uarfcn: _int(map['uarfcn']),
        arfcn: _int(map['arfcn']),
        bandwidth: _int(map['bandwidth']),
        rsrp: _int(map['rsrp']),
        rsrq: _int(map['rsrq']),
        rssi: _int(map['rssi']),
        sinr: _int(map['sinr']),
        dbm: _int(map['dbm']),
        asu: _int(map['asu']),
        ta: _int(map['ta']),
        timestamp: DateTime.now(),
      );

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  CellInfo copyWith({
    int? band,
    double? latitude,
    double? longitude,
  }) =>
      CellInfo(
        technology: technology,
        registered: registered,
        mcc: mcc,
        mnc: mnc,
        lac: lac,
        tac: tac,
        ci: ci,
        nci: nci,
        pci: pci,
        psc: psc,
        bsic: bsic,
        earfcn: earfcn,
        nrarfcn: nrarfcn,
        uarfcn: uarfcn,
        arfcn: arfcn,
        band: band ?? this.band,
        bandwidth: bandwidth,
        rsrp: rsrp,
        rsrq: rsrq,
        rssi: rssi,
        sinr: sinr,
        dbm: dbm,
        asu: asu,
        ta: ta,
        timestamp: timestamp,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
      );

  Map<String, dynamic> toJson() => {
        'technology': technology,
        'registered': registered,
        'mcc': mcc,
        'mnc': mnc,
        'lac': lac,
        'tac': tac,
        'ci': ci,
        'nci': nci,
        'pci': pci,
        'psc': psc,
        'bsic': bsic,
        'earfcn': earfcn,
        'nrarfcn': nrarfcn,
        'uarfcn': uarfcn,
        'arfcn': arfcn,
        'band': band,
        'bandwidth': bandwidth,
        'rsrp': rsrp,
        'rsrq': rsrq,
        'rssi': rssi,
        'sinr': sinr,
        'dbm': dbm,
        'asu': asu,
        'ta': ta,
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
      };

  factory CellInfo.fromJson(Map<String, dynamic> json) => CellInfo(
        technology: json['technology'] as String,
        registered: json['registered'] as bool? ?? false,
        mcc: json['mcc'] as int?,
        mnc: json['mnc'] as int?,
        lac: json['lac'] as int?,
        tac: json['tac'] as int?,
        ci: json['ci'] as int?,
        nci: json['nci'] as int?,
        pci: json['pci'] as int?,
        psc: json['psc'] as int?,
        bsic: json['bsic'] as int?,
        earfcn: json['earfcn'] as int?,
        nrarfcn: json['nrarfcn'] as int?,
        uarfcn: json['uarfcn'] as int?,
        arfcn: json['arfcn'] as int?,
        band: json['band'] as int?,
        bandwidth: json['bandwidth'] as int?,
        rsrp: json['rsrp'] as int?,
        rsrq: json['rsrq'] as int?,
        rssi: json['rssi'] as int?,
        sinr: json['sinr'] as int?,
        dbm: json['dbm'] as int?,
        asu: json['asu'] as int?,
        ta: json['ta'] as int?,
        timestamp: DateTime.parse(json['timestamp'] as String),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );
}
