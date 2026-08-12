class MedicineDescriptionDraft {
  const MedicineDescriptionDraft({
    this.medicineName,
    this.specification,
    this.batchNumber,
    this.productionDate,
    this.expiryDate,
    this.quantity,
    this.ambiguities = const [],
  });

  factory MedicineDescriptionDraft.fromJson(Map<String, dynamic> json) =>
      MedicineDescriptionDraft(
        medicineName: json['medicine_name'] as String?,
        specification: json['specification'] as String?,
        batchNumber: json['batch_number'] as String?,
        productionDate: _parseDate(json['production_date']),
        expiryDate: _parseDate(json['expiry_date']),
        quantity: json['quantity'] as int?,
        ambiguities:
            (json['ambiguities'] as List<dynamic>? ?? const []).cast<String>(),
      );

  final String? medicineName;
  final String? specification;
  final String? batchNumber;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  final int? quantity;
  final List<String> ambiguities;

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
