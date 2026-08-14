import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/data/api_medicine_repository.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/data/medicine_cabinet_api.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/inventory_batch.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/medicine_models.dart';

void main() {
  test(
      'loads the first inventory page and aggregates matching medicine batches',
      () async {
    final source = _InventorySource(
      InventoryBatchPage(
        batches: [
          batch(
            id: 'batch-expired',
            medicineId: 'medicine-1',
            name: '布洛芬胶囊',
            specification: '0.3g*20粒',
            quantity: 2,
            expiryStatus: InventoryExpiryStatus.expired,
            productionDate: DateTime(2026, 1, 1),
            expiryDate: DateTime(2026, 7, 1),
          ),
          batch(
            id: 'batch-soon',
            medicineId: 'medicine-1',
            name: '布洛芬胶囊',
            specification: '0.3g*20粒',
            quantity: 5,
            expiryStatus: InventoryExpiryStatus.expiringSoon,
            productionDate: DateTime(2026, 2, 1),
            expiryDate: DateTime(2026, 8, 20),
          ),
          batch(
            id: 'batch-other-spec',
            medicineId: 'medicine-1',
            name: '布洛芬胶囊',
            specification: '0.2g*24粒',
            quantity: 1,
            expiryStatus: InventoryExpiryStatus.valid,
            expiryDate: DateTime(2027, 1, 1),
          ),
        ],
        nextPage: Uri.parse('https://api.invalid/inventory?cursor=next'),
      ),
    );

    final collection = await ApiMedicineRepository(source).load();

    expect(source.calls, 1);
    expect(source.lastQuery, '');
    expect(source.lastPageUrl, isNull);
    expect(collection.isTruncated, isTrue);
    expect(collection.loadedBatchCount, 3);
    expect(collection.items, hasLength(2));
    final ibuprofen = collection.items.singleWhere(
      (item) => item.specification == '0.3g*20粒',
    );
    expect(ibuprofen.name, '布洛芬胶囊');
    expect(ibuprofen.totalQuantity, 7);
    expect(ibuprofen.nearestExpiry, DateTime(2026, 7, 1));
    expect(ibuprofen.status, MedicineStatus.expired);
  });

  test('returns immutable cached batch detail with its source fields',
      () async {
    final repository = ApiMedicineRepository(
      _InventorySource(
        InventoryBatchPage(
          batches: [
            batch(
              id: 'batch-a',
              medicineId: 'medicine-1',
              name: '布洛芬胶囊',
              specification: '0.3g*20粒',
              batchNumber: 'LOT-A',
              quantity: 2,
              expiryStatus: InventoryExpiryStatus.valid,
              productionDate: DateTime(2026, 1, 1),
              expiryDate: DateTime(2027, 1, 1),
            ),
            batch(
              id: 'batch-b',
              medicineId: 'medicine-1',
              name: '布洛芬胶囊',
              specification: '0.3g*20粒',
              batchNumber: 'LOT-B',
              quantity: 4,
              expiryStatus: InventoryExpiryStatus.unknown,
              productionDate: null,
              expiryDate: null,
            ),
          ],
          nextPage: null,
        ),
      ),
    );

    final collection = await repository.load();
    final detail = await repository.getById(collection.items.single.id);

    expect(detail.batches, hasLength(2));
    expect(detail.batches.first.batchNumber, 'LOT-A');
    expect(detail.batches.first.quantity, 2);
    expect(detail.batches.first.productionDate, DateTime(2026, 1, 1));
    expect(detail.batches.first.expiresOn, DateTime(2027, 1, 1));
    expect(detail.batches.first.sourceLabel, '个人药箱');
    expect(detail.batches.last.batchNumber, 'LOT-B');
    expect(detail.batches.last.productionDate, isNull);
    expect(detail.batches.last.expiresOn, isNull);
    expect(
      () => detail.batches.add(detail.batches.first),
      throwsUnsupportedError,
    );
  });

  test('propagates inventory API failures without replacing them', () async {
    final failure = StateError('inventory unavailable');
    final repository = ApiMedicineRepository(_InventorySource.error(failure));

    await expectLater(repository.load(), throwsA(same(failure)));
  });

  test('maps batches without a known expiry to a neutral unknown status',
      () async {
    final collection = await ApiMedicineRepository(
      _InventorySource(
        InventoryBatchPage(
          batches: [
            batch(
              id: 'batch-unknown',
              medicineId: 'medicine-unknown',
              name: '有效期未录入药品',
              specification: '10mg',
              quantity: 1,
              expiryStatus: InventoryExpiryStatus.unknown,
            ),
          ],
          nextPage: null,
        ),
      ),
    ).load();

    expect(collection.items.single.nearestExpiry, isNull);
    expect(collection.items.single.status, MedicineStatus.unknown);
  });
}

InventoryBatch batch({
  required String id,
  required String medicineId,
  required String name,
  required String specification,
  required int quantity,
  required InventoryExpiryStatus expiryStatus,
  String batchNumber = '',
  DateTime? productionDate,
  DateTime? expiryDate,
}) =>
    InventoryBatch(
      id: id,
      medicineId: medicineId,
      medicineName: name,
      specification: specification,
      batchNumber: batchNumber,
      productionDate: productionDate,
      expiryDate: expiryDate,
      quantity: quantity,
      expiryStatus: expiryStatus,
      daysUntilExpiry: null,
    );

class _InventorySource implements MedicineCabinetDataSource {
  _InventorySource(this.page) : error = null;

  _InventorySource.error(this.error) : page = null;

  final InventoryBatchPage? page;
  final Object? error;
  var calls = 0;
  String? lastQuery;
  Uri? lastPageUrl;

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
    String packageUnit = '',
    double? unitsPerPackage,
    String unitName = '',
    double looseUnits = 0,
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
  }) =>
      Future.error(UnsupportedError('unused'));

  @override
  Future<void> deleteBatch(String batchId) => Future.error(
        UnsupportedError('unused'),
      );

  @override
  Future<InventoryBatch> correctExpiryDate(
    String batchId, {
    required DateTime expiryDate,
  }) =>
      Future.error(UnsupportedError('unused'));

  @override
  Future<InventoryBatchPage> listBatches({
    String query = '',
    Uri? pageUrl,
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
  }) {
    calls += 1;
    lastQuery = query;
    lastPageUrl = pageUrl;
    if (error case final Object value) return Future.error(value);
    return Future.value(page!);
  }
}
