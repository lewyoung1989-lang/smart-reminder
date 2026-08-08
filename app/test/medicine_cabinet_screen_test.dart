import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/data/medicine_repository.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/medicine_models.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/presentation/medicine_cabinet_screen.dart';
import 'package:smart_reminder_app/ui/components/app_list_row.dart';

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

  testWidgets('corrects a batch expiry date and reloads the cabinet',
      (tester) async {
    final repository = _Repository();
    final corrections = <({String batchId, DateTime expiryDate})>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MedicineCabinetScreen(
          repository: repository,
          onCorrectBatchExpiry: (batch, expiryDate) async {
            corrections.add((batchId: batch.id, expiryDate: expiryDate));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('布洛芬胶囊'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medicine-correct-expiry-batch-a')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('medicine-expiry-date-input')),
      '2027-06-30',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(corrections, [
      (batchId: 'batch-a', expiryDate: DateTime(2027, 6, 30)),
    ]);
    expect(repository.loadCalls, 2);
    expect(find.text('有效期已修正'), findsOneWidget);
  });

  testWidgets('discloses truncated batches and labels unknown expiry neutrally',
      (tester) async {
    final repository = _Repository(
      status: MedicineStatus.unknown,
      nearestExpiry: null,
      isTruncated: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: MedicineCabinetScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('仅显示已加载的 1 个库存批次'), findsOneWidget);
    expect(find.text('数量和有效期状态仅基于这些批次'), findsOneWidget);
    final row = tester.widget<AppListRow>(
      find.byWidgetPredicate(
        (widget) => widget is AppListRow && widget.title == '布洛芬胶囊',
      ),
    );
    expect(row.statusText, '有效期未知');
    expect(row.statusColor, isNot(Colors.green));
  });

  testWidgets('reloads the cabinet only after confirmed capture',
      (tester) async {
    final repository = _Repository();
    var results = [false, true].iterator;
    await tester.pumpWidget(
      MaterialApp(
        home: MedicineCabinetScreen(
          repository: repository,
          captureAvailability: MedicineCaptureAvailability.ready,
          onCapture: () async => results.moveNext() && results.current,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('拍照录入'));
    await tester.pumpAndSettle();
    expect(repository.loadCalls, 1);

    await tester.tap(find.text('拍照录入'));
    await tester.pumpAndSettle();
    expect(repository.loadCalls, 2);
  });
}

class _Repository implements MedicineRepository {
  _Repository({
    this.status = MedicineStatus.active,
    this.nearestExpiry,
    this.isTruncated = false,
  });

  var loadCalls = 0;
  final MedicineStatus status;
  final DateTime? nearestExpiry;
  final bool isTruncated;

  late final detail = MedicineDetail(
    summary: MedicineSummary(
      id: 'medicine-1',
      name: '布洛芬胶囊',
      specification: '0.3g*20粒',
      totalQuantity: 2,
      nearestExpiry: nearestExpiry ??
          (status == MedicineStatus.unknown ? null : DateTime(2027, 1, 1)),
      status: status,
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
    return MedicineCollection(
      items: [detail.summary],
      isTruncated: isTruncated,
      loadedBatchCount: 1,
    );
  }
}
