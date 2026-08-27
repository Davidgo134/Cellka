/// Модель соты из TelephonyManager (через CellInfoPlugin).
class CellInfo {
  /// LTE, NR, UMTS (WCDMA), GSM, CDMA, TDSCDMA.
  final String technology;
  final bool registered;

  final int? mcc;
  final int? mnc;
  final int? tac;
  final int? lac;

  /// 28-битный LTE Cell Identity.
  final int? ci;

  /// 36-битный NR Cell Identity.
  final int? nci;

  /// LTE/NR physical cell id.
  final int? pci;

  /// WCDMA primary scrambling code.
  final int? psc;

  /// GSM BSIC.
  final int? bsic;

  /// Канал по технологии: LTE EARFCN, NR NRARFCN, WCDMA UARFCN, GSM ARFCN.
  final int? earfcn;
  final int? nrarfcn;
  final int? uarfcn;
  final int? arfcn;

  /// Номер band, вычисляется TelephonyService через BandMapper.
  final int? band;

  final int? rsrp;
  final int? rsrq;

  /// Широкополосный RSSI (API 29+, может быть null на старых).
  final int? rssi;
  final int? sinr;

  /// Timing advance.
  final int? ta;

  /// Уровень в ASU.
  final int? asu;

  /// Ширина канала, кГц.
  final int? bandwidth;

  /// Уровень в dBm, как его отдал модем (плагин шлёт для всех технологий).
  final int? dbm;

  final String? operator;

  /// Время снятия замера.
  final DateTime? timestamp;

  const CellInfo({
    required this.technology,
    required this.registered,
    this.mcc,
    this.mnc,
    this.tac,
    this.lac,
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
    this.rsrp,
    this.rsrq,
    this.rssi,
    this.sinr,
    this.ta,
    this.asu,
    this.bandwidth,
    this.dbm,
    this.operator,
    this.timestamp,
  });

  factory CellInfo.fromMap(Map<dynamic, dynamic> map) {
    int? toInt(Object? v) =>
        v is int ? v : int.tryParse(v?.toString() ?? '');
    return CellInfo(
      technology: map['technology']?.toString() ?? 'unknown',
      registered: map['registered'] == true,
      mcc: toInt(map['mcc']),
      mnc: toInt(map['mnc']),
      tac: toInt(map['tac']),
      lac: toInt(map['lac']),
      ci: toInt(map['ci']),
      nci: toInt(map['nci']),
      pci: toInt(map['pci']),
      psc: toInt(map['psc']),
      bsic: toInt(map['bsic']),
      earfcn: toInt(map['earfcn']),
      nrarfcn: toInt(map['nrarfcn']),
      uarfcn: toInt(map['uarfcn']),
      arfcn: toInt(map['arfcn']),
      rsrp: toInt(map['rsrp']),
      rsrq: toInt(map['rsrq']),
      rssi: toInt(map['rssi']),
      sinr: toInt(map['sinr']),
      ta: toInt(map['ta']),
      asu: toInt(map['asu']),
      bandwidth: toInt(map['bandwidth']),
      dbm: toInt(map['dbm']) ?? toInt(map['rsrp']) ?? toInt(map['rssi']),
      operator: map['operator']?.toString(),
      timestamp: DateTime.now(),
    );
  }

  CellInfo copyWith({
    String? technology,
    bool? registered,
    int? mcc,
    int? mnc,
    int? tac,
    int? lac,
    int? ci,
    int? nci,
    int? pci,
    int? psc,
    int? bsic,
    int? earfcn,
    int? nrarfcn,
    int? uarfcn,
    int? arfcn,
    int? band,
    int? rsrp,
    int? rsrq,
    int? rssi,
    int? sinr,
    int? ta,
    int? asu,
    int? bandwidth,
    int? dbm,
    String? operator,
    DateTime? timestamp,
  }) {
    return CellInfo(
      technology: technology ?? this.technology,
      registered: registered ?? this.registered,
      mcc: mcc ?? this.mcc,
      mnc: mnc ?? this.mnc,
      tac: tac ?? this.tac,
      lac: lac ?? this.lac,
      ci: ci ?? this.ci,
      nci: nci ?? this.nci,
      pci: pci ?? this.pci,
      psc: psc ?? this.psc,
      bsic: bsic ?? this.bsic,
      earfcn: earfcn ?? this.earfcn,
      nrarfcn: nrarfcn ?? this.nrarfcn,
      uarfcn: uarfcn ?? this.uarfcn,
      arfcn: arfcn ?? this.arfcn,
      band: band ?? this.band,
      rsrp: rsrp ?? this.rsrp,
      rsrq: rsrq ?? this.rsrq,
      rssi: rssi ?? this.rssi,
      sinr: sinr ?? this.sinr,
      ta: ta ?? this.ta,
      asu: asu ?? this.asu,
      bandwidth: bandwidth ?? this.bandwidth,
      dbm: dbm ?? this.dbm,
      operator: operator ?? this.operator,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Канал независимо от технологии.
  int? get channel => earfcn ?? nrarfcn ?? uarfcn ?? arfcn;

  /// eNodeB ID из LTE CI (старшие 20 бит), как у CellMapper.
  int? get eNbId =>
      technology == 'LTE' && ci != null ? ci! >> 8 : null;

  /// Номер сектора из LTE CI (младшие 8 бит).
  int? get sectorId =>
      technology == 'LTE' && ci != null ? ci! & 0xFF : null;
}
