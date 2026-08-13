enum InventoryExpiryStatus { expired, expiringSoon, valid, unknown }

enum MedicineCabinetScope { personal, family }

extension MedicineCabinetScopeValue on MedicineCabinetScope {
  String get apiValue => name;
  String get label => this == MedicineCabinetScope.personal ? '个人药箱' : '家庭药箱';
}

class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.medicineId,
    required this.medicineName,
    required this.specification,
    this.manufacturer = '',
    this.photoUrl,
    required this.batchNumber,
    required this.productionDate,
    required this.expiryDate,
    required this.quantity,
    required this.expiryStatus,
    required this.daysUntilExpiry,
    this.scope = MedicineCabinetScope.personal,
    this.canDelete = true,
    this.version = 1,
  });

  factory InventoryBatch.fromJson(Map<String, dynamic> json) => InventoryBatch(
        id: json['id'] as String,
        medicineId: json['medicine_id'] as String,
        medicineName: json['medicine_name'] as String,
        specification: json['specification'] as String? ?? '',
        manufacturer: json['manufacturer'] as String? ?? '',
        photoUrl: json['photo_url'] as String?,
        batchNumber: json['batch_number'] as String? ?? '',
        productionDate: _parseDate(json['production_date']),
        expiryDate: _parseDate(json['expiry_date']),
        quantity: json['quantity'] as int,
        expiryStatus: _parseStatus(json['expiry_status'] as String?),
        daysUntilExpiry: json['days_until_expiry'] as int?,
        scope: json['scope'] == 'family'
            ? MedicineCabinetScope.family
            : MedicineCabinetScope.personal,
        canDelete: json['can_delete'] as bool? ?? true,
        version: json['version'] as int? ?? 1,
      );

  final String id;
  final String medicineId;
  final String medicineName;
  final String specification;
  final String manufacturer;
  final String? photoUrl;
  final String batchNumber;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  final int quantity;
  final InventoryExpiryStatus expiryStatus;
  final int? daysUntilExpiry;
  final MedicineCabinetScope scope;
  final bool canDelete;
  final int version;

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
