enum MedicineStatus { active, expiring, expired, unknown }

enum MedicineCaptureAvailability {
  ready,
  denied,
  permanentlyDenied,
  unavailable,
}

class MedicineSummary {
  const MedicineSummary({
    required this.id,
    required this.name,
    required this.specification,
    this.manufacturer = '',
    this.photoUrl,
    required this.totalQuantity,
    this.totalRemainingUnits,
    this.unitName = '',
    required this.nearestExpiry,
    required this.status,
  });

  final String id;
  final String name;
  final String specification;
  final String manufacturer;
  final String? photoUrl;
  final int totalQuantity;
  final double? totalRemainingUnits;
  final String unitName;
  final DateTime? nearestExpiry;
  final MedicineStatus status;

  String get inventoryLabel => totalRemainingUnits == null || unitName.isEmpty
      ? '$totalQuantity 件'
      : '${_formatInventoryNumber(totalRemainingUnits!)} $unitName';
}

class MedicineBatch {
  const MedicineBatch({
    required this.id,
    required this.batchNumber,
    required this.specification,
    required this.productionDate,
    required this.expiresOn,
    required this.quantity,
    this.packageUnit = '',
    this.unitsPerPackage,
    this.unitName = '',
    this.looseUnits = 0,
    this.totalRemainingUnits,
    required this.sourceLabel,
    this.canDelete = true,
    this.version = 1,
  });

  final String id;
  final String batchNumber;
  final String specification;
  final DateTime? productionDate;
  final DateTime? expiresOn;
  final int quantity;
  final String packageUnit;
  final double? unitsPerPackage;
  final String unitName;
  final double looseUnits;
  final double? totalRemainingUnits;
  final String sourceLabel;
  final bool canDelete;
  final int version;

  String get inventoryLabel {
    if (unitsPerPackage == null || packageUnit.isEmpty || unitName.isEmpty) {
      return '$quantity 件';
    }
    final packages = '$quantity $packageUnit';
    if (looseUnits <= 0) return packages;
    return '$packages + ${_formatInventoryNumber(looseUnits)} $unitName';
  }
}

String _formatInventoryNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');

class MedicineDetail {
  MedicineDetail({
    required this.summary,
    required List<MedicineBatch> batches,
  }) : batches = List.unmodifiable(batches);

  final MedicineSummary summary;
  final List<MedicineBatch> batches;
}

class MedicineCollection {
  MedicineCollection({
    required List<MedicineSummary> items,
    this.isOffline = false,
    this.isTruncated = false,
    this.loadedBatchCount = 0,
  }) : items = List.unmodifiable(items);

  final List<MedicineSummary> items;
  final bool isOffline;
  final bool isTruncated;
  final int loadedBatchCount;
}
