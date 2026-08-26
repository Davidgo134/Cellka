/// Модель соты из TelephonyManager (через CellInfoPlugin).
class CellInfo {
  /// LTE, NR, WCDMA, GSM, CDMA, TD-SCDMA.
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
  final int? pci;
  final int? earfcn;

  final int? rsrp;
  final int? rsrq;

  /// Широкополосный RSSI (API 29+, может быть null на старых).
  final int? rssi;
  final int? sinr;

  /// Timing advance.
  final int? ta;

  /// Ширина канала, кГц.
  final int? bandwidth;

  final String? operator;

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
    this.earfcn,
    this.rsrp,
    this.rsrq,
    this.rssi,
    this.sinr,
    this.ta,
    this.bandwidth,
    this.operator,
  });

  factory CellInfo.fromMap(Map<dynamic, dynamic> map) {
    int? toInt(Object? v) =>
        v is int ? v : int.tryParse(v?.toString() ?? '');
    return CellInfo(
      technology: map['type']?.toString() ?? 'unknown',
      registered: map['registered'] == true,
      mcc: toInt(map['mcc']),
      mnc: toInt(map['mnc']),
      tac: toInt(map['tac']),
      lac: toInt(map['lac']),
      ci: toInt(map['ci']),
      nci: toInt(map['nci']),
      pci: toInt(map['pci']),
      earfcn: toInt(map['earfcn']),
      rsrp: toInt(map['rsrp']),
      rsrq: toInt(map['rsrq']),
      rssi: toInt(map['rssi']),
      sinr: toInt(map['sinr']),
      ta: toInt(map['ta']),
      bandwidth: toInt(map['bandwidth']),
      operator: map['operator']?.toString(),
    );
  }

  /// Основной уровень сигнала для цветовой индикации.
  int? get dbm => rsrp ?? rssi;

  /// eNodeB ID из LTE CI (старшие 20 бит), как у CellMapper.
  int? get eNbId =>
      technology == 'LTE' && ci != null ? ci! >> 8 : null;

  /// Номер сектора из LTE CI (младшие 8 бит).
  int? get sectorId =>
      technology == 'LTE' && ci != null ? ci! & 0xFF : null;
}
