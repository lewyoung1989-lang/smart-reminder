import '../domain/inventory_batch.dart';
import '../domain/medicine_models.dart';
import 'medicine_cabinet_api.dart';
import 'medicine_repository.dart';

class ApiMedicineRepository implements MedicineRepository {
  ApiMedicineRepository(this._source);

  factory ApiMedicineRepository.fromLoader(InventoryBatchLoader loader) =>
      ApiMedicineRepository(_LoaderDataSource(loader));

  final MedicineCabinetDataSource _source;
  Map<String, MedicineDetail> _details = const {};

  @override
  Future<MedicineCollection> load({
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
  }) async {
    final page = await _source.listBatches(scope: scope);
    final grouped = <(String, String, String), List<InventoryBatch>>{};
    for (final batch in page.batches) {
      final key = (batch.medicineId, batch.medicineName, batch.specification);
      (grouped[key] ??= []).add(batch);
    }

    final details = <String, MedicineDetail>{};
    for (final entry in grouped.entries) {
      final (medicineId, name, specification) = entry.key;
      final batches = entry.value;
      final summary = MedicineSummary(
        id: _summaryId(medicineId, name, specification),
        name: name,
        specification: specification,
        manufacturer: batches.first.manufacturer,
        photoUrl: batches.first.photoUrl,
        totalQuantity:
            batches.fold(0, (total, batch) => total + batch.quantity),
        nearestExpiry: _nearestExpiry(batches),
        status: _mostSevereStatus(batches),
      );
      details[summary.id] = MedicineDetail(
        summary: summary,
        batches: batches
            .map(
              (batch) => MedicineBatch(
                id: batch.id,
                batchNumber: batch.batchNumber,
                specification: batch.specification,
                productionDate: batch.productionDate,
                expiresOn: batch.expiryDate,
                quantity: batch.quantity,
                sourceLabel: batch.scope.label,
                canDelete: batch.canDelete,
                version: batch.version,
              ),
            )
            .toList(growable: false),
      );
    }

    final immutableDetails = Map<String, MedicineDetail>.unmodifiable(details);
    _details = immutableDetails;
    return MedicineCollection(
      items: immutableDetails.values
          .map((detail) => detail.summary)
          .toList(growable: false),
      isTruncated: page.nextPage != null,
      loadedBatchCount: page.batches.length,
    );
  }

  @override
  Future<MedicineDetail> getById(String id) async {
    final detail = _details[id];
    if (detail == null) throw StateError('Medicine has not been loaded: $id');
    return detail;
  }

  static String _summaryId(
    String medicineId,
    String medicineName,
    String specification,
  ) =>
      [medicineId, medicineName, specification]
          .map(Uri.encodeComponent)
          .join('/');

  static DateTime? _nearestExpiry(List<InventoryBatch> batches) {
    final expiries = batches
        .map((batch) => batch.expiryDate)
        .whereType<DateTime>()
        .toList(growable: false);
    if (expiries.isEmpty) return null;
    return expiries
        .reduce((first, second) => first.isBefore(second) ? first : second);
  }

  static MedicineStatus _mostSevereStatus(List<InventoryBatch> batches) {
    if (batches.any(
      (batch) => batch.expiryStatus == InventoryExpiryStatus.expired,
    )) {
      return MedicineStatus.expired;
    }
    if (batches.any(
      (batch) => batch.expiryStatus == InventoryExpiryStatus.expiringSoon,
    )) {
      return MedicineStatus.expiring;
    }
    if (batches.any(
      (batch) => batch.expiryStatus == InventoryExpiryStatus.unknown,
    )) {
      return MedicineStatus.unknown;
    }
    return MedicineStatus.active;
  }
}

class _LoaderDataSource implements MedicineCabinetDataSource {
  const _LoaderDataSource(this._loader);

  final InventoryBatchLoader _loader;

  @override
  Future<InventoryBatch> createBatch({
    required String medicineName,
    String specification = '',
    String manufacturer = '',
    List<int>? photoBytes,
    String batchNumber = '',
    DateTime? productionDate,
    DateTime? expiryDate,
    int quantity = 1,
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
  }) =>
      Future.error(UnsupportedError('Batch creation is not configured.'));

  @override
  Future<void> deleteBatch(String batchId) =>
      Future.error(UnsupportedError('Batch deletion is not configured.'));

  @override
  Future<InventoryBatch> correctExpiryDate(
    String batchId, {
    required DateTime expiryDate,
  }) =>
      Future.error(
        UnsupportedError('Batch expiry correction is not configured.'),
      );

  @override
  Future<InventoryBatchPage> listBatches({
    String query = '',
    Uri? pageUrl,
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
  }) =>
      _loader(query: query, pageUrl: pageUrl);
}
