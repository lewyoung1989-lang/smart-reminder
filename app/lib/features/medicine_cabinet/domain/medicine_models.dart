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
    required this.nearestExpiry,
    required this.status,
  });

  final String id;
  final String name;
  final String specification;
  final String manufacturer;
  final String? photoUrl;
  final int totalQuantity;
  final DateTime? nearestExpiry;
  final MedicineStatus status;
}

class MedicineBatch {
  const MedicineBatch({
    required this.id,
    required this.batchNumber,
    required this.specification,
    required this.productionDate,
    required this.expiresOn,
    required this.quantity,
    required this.sourceLabel,
  });

  final String id;
  final String batchNumber;
  final String specification;
  final DateTime? productionDate;
  final DateTime? expiresOn;
  final int quantity;
  final String sourceLabel;
}

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
