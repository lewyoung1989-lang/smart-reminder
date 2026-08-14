class MedicineDescriptionDraft {
  const MedicineDescriptionDraft({
    this.medicineName,
    this.specification,
    this.manufacturer,
    this.batchNumber,
    this.productionDate,
    this.expiryDate,
    this.quantity,
    this.packageUnit,
    this.unitsPerPackage,
    this.unitName,
    this.looseUnits,
    this.ambiguities = const [],
  });

  factory MedicineDescriptionDraft.fromJson(Map<String, dynamic> json) =>
      MedicineDescriptionDraft(
        medicineName: json['medicine_name'] as String?,
        specification: json['specification'] as String?,
        manufacturer: json['manufacturer'] as String?,
        batchNumber: json['batch_number'] as String?,
        productionDate: _parseDate(json['production_date']),
        expiryDate: _parseDate(json['expiry_date']),
        quantity: json['quantity'] as int?,
        packageUnit: json['package_unit'] as String?,
        unitsPerPackage: _parseNumber(json['units_per_package']),
        unitName: json['unit_name'] as String?,
        looseUnits: _parseNumber(json['loose_units']),
        ambiguities:
            (json['ambiguities'] as List<dynamic>? ?? const []).cast<String>(),
      );

  final String? medicineName;
  final String? specification;
  final String? manufacturer;
  final String? batchNumber;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  final int? quantity;
  final String? packageUnit;
  final double? unitsPerPackage;
  final String? unitName;
  final double? looseUnits;
  final List<String> ambiguities;

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static double? _parseNumber(Object? value) => switch (value) {
        num number => number.toDouble(),
        String text => double.tryParse(text),
        _ => null,
      };
}
