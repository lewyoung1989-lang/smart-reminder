import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/data/medicine_repository.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/medicine_models.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/medicine_description_draft.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/presentation/medicine_cabinet_screen.dart';
import 'package:smart_reminder_app/features/quick_create/domain/voice_input_controller.dart';
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

    await tester.tap(find.text('录入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medicine-entry-capture')));
    await tester.pumpAndSettle();
    expect(repository.loadCalls, 1);

    await tester.tap(find.text('录入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medicine-entry-capture')));
    await tester.pumpAndSettle();
    expect(repository.loadCalls, 2);
  });

  testWidgets('creates a batch from text entry and reloads the cabinet',
      (tester) async {
    final repository = _Repository();
    final created = <MedicineBatchInput>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MedicineCabinetScreen(
          repository: repository,
          onCreateBatch: (input) async => created.add(input),
          onParseDescription: (_) async => MedicineDescriptionDraft(
            medicineName: '布洛芬胶囊',
            specification: '0.3g',
            quantity: 2,
            expiryDate: DateTime(2027, 1, 1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('录入'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('medicine-entry-description')),
      '录入布洛芬胶囊 0.3g 2盒，有效期到2027年1月1日',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('medicine-entry-parse')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('medicine-entry-save')));
    await tester.tap(find.byKey(const Key('medicine-entry-save')));
    await tester.pumpAndSettle();

    expect(created.single.medicineName, '布洛芬胶囊');
    expect(created.single.specification, '0.3g');
    expect(created.single.quantity, 2);
    expect(created.single.expiryDate, DateTime(2027, 1, 1));
    expect(repository.loadCalls, 2);
    expect(find.text('药品已录入'), findsOneWidget);
  });

  testWidgets('uses voice transcript to prefill medicine entry',
      (tester) async {
    final voice = _FakeVoiceInputController()
      ..transcript = '录入维生素C 100mg 3瓶，有效期到2027-06-30';
    final repository = _Repository();
    final created = <MedicineBatchInput>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MedicineCabinetScreen(
          repository: repository,
          voiceInputController: voice,
          onCreateBatch: (input) async => created.add(input),
          onParseDescription: (_) async => MedicineDescriptionDraft(
            medicineName: '维生素C',
            specification: '100mg',
            quantity: 3,
            expiryDate: DateTime(2027, 6, 30),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('录入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medicine-entry-voice')));
    await tester.pumpAndSettle();
    expect(find.text('停止录音'), findsOneWidget);
    await tester.tap(find.byKey(const Key('medicine-entry-voice')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('medicine-entry-save')));
    await tester.tap(find.byKey(const Key('medicine-entry-save')));
    await tester.pumpAndSettle();

    expect(created.single.medicineName, '维生素C');
    expect(created.single.specification, '100mg');
    expect(created.single.quantity, 3);
    expect(created.single.expiryDate, DateTime(2027, 6, 30));
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

class _FakeVoiceInputController extends VoiceInputController {
  VoiceInputPhase _phase = VoiceInputPhase.idle;
  String? transcript;

  @override
  VoiceInputPhase get phase => _phase;

  @override
  Duration get elapsed => const Duration(seconds: 3);

  @override
  String? get errorMessage => null;

  void _setPhase(VoiceInputPhase value) {
    _phase = value;
    notifyListeners();
  }

  @override
  Future<void> start() async => _setPhase(VoiceInputPhase.recording);

  @override
  Future<String?> stopAndTranscribe() async {
    _setPhase(VoiceInputPhase.transcribing);
    _setPhase(VoiceInputPhase.idle);
    return transcript;
  }

  @override
  Future<void> retry() async => _setPhase(VoiceInputPhase.idle);

  @override
  Future<void> cancel() async => _setPhase(VoiceInputPhase.idle);
}
