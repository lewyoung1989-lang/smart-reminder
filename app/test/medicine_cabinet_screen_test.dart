import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/data/medicine_repository.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/medicine_models.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/presentation/medicine_cabinet_screen.dart';

void main() {
  testWidgets('deletes a batch and reloads the cabinet only after success',
      (tester) async {
    final repository = _Repository();
    final deleted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MedicineCabinetScreen(
          repository: repository,
          onDeleteBatch: (batch) async => deleted.add(batch.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('布洛芬胶囊'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medicine-delete-batch-batch-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(deleted, ['batch-a']);
    expect(repository.loadCalls, 2);
  });

  testWidgets('keeps the cabinet visible when batch deletion fails',
      (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: MedicineCabinetScreen(
          repository: repository,
          onDeleteBatch: (_) => Future.error(StateError('delete failed')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('布洛芬胶囊'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medicine-delete-batch-batch-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(repository.loadCalls, 1);
    expect(find.text('操作失败，请稍后重试'), findsOneWidget);
    expect(find.text('布洛芬胶囊'), findsOneWidget);
  });
}

class _Repository implements MedicineRepository {
  var loadCalls = 0;

  late final detail = MedicineDetail(
    summary: MedicineSummary(
      id: 'medicine-1',
      name: '布洛芬胶囊',
      specification: '0.3g*20粒',
      totalQuantity: 2,
      nearestExpiry: DateTime(2027, 1, 1),
      status: MedicineStatus.active,
    ),
    batches: [
      MedicineBatch(
        id: 'batch-a',
        batchNumber: 'LOT-A',
        specification: '0.3g*20粒',
        productionDate: DateTime(2026, 1, 1),
        expiresOn: DateTime(2027, 1, 1),
        quantity: 2,
        sourceLabel: '家庭药箱',
      ),
    ],
  );

  @override
  Future<MedicineDetail> getById(String id) async => detail;

  @override
  Future<MedicineCollection> load() async {
    loadCalls += 1;
    return MedicineCollection(items: [detail.summary]);
  }
}
