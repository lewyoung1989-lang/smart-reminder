enum InventoryExpiryStatus { expired, expiringSoon, valid, unknown }

class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.medicineId,
    required this.medicineName,
    required this.specification,
    required this.batchNumber,
    required this.productionDate,
    required this.expiryDate,
    required this.quantity,
    required this.expiryStatus,
    required this.daysUntilExpiry,
  });

  factory InventoryBatch.fromJson(Map<String, dynamic> json) => InventoryBatch(
        id: json['id'] as String,
        medicineId: json['medicine_id'] as String,
        medicineName: json['medicine_name'] as String,
        specification: json['specification'] as String? ?? '',
        batchNumber: json['batch_number'] as String? ?? '',
        productionDate: _parseDate(json['production_date']),
        expiryDate: _parseDate(json['expiry_date']),
        quantity: json['quantity'] as int,
        expiryStatus: _parseStatus(json['expiry_status'] as String?),
        daysUntilExpiry: json['days_until_expiry'] as int?,
      );

  final String id;
  final String medicineId;
  final String medicineName;
  final String specification;
  final String batchNumber;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  final int quantity;
  final InventoryExpiryStatus expiryStatus;
  final int? daysUntilExpiry;

  static DateTime? _parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  static InventoryExpiryStatus _parseStatus(String? value) => switch (value) {
        'expired' => InventoryExpiryStatus.expired,
        'expiring_soon' => InventoryExpiryStatus.expiringSoon,
        'valid' => InventoryExpiryStatus.valid,
        _ => InventoryExpiryStatus.unknown,
      };
}

class InventoryBatchPage {
  const InventoryBatchPage({
    required this.batches,
    required this.nextPage,
  });

  final List<InventoryBatch> batches;
  final Uri? nextPage;
}
