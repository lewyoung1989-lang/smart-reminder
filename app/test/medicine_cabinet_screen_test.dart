import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/data/medicine_repository.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/medicine_models.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/inventory_batch.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/medicine_description_draft.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/presentation/medicine_cabinet_screen.dart';
import 'package:smart_reminder_app/features/quick_create/domain/voice_input_controller.dart';
import 'package:smart_reminder_app/ui/components/app_segmented_control.dart';

void main() {
  testWidgets('switches between personal and family inventory scopes',
      (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(
      MaterialApp(home: MedicineCabinetScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('家庭药箱'));
    await tester.pumpAndSettle();

    expect(repository.scopes, [
      MedicineCabinetScope.personal,
      MedicineCabinetScope.family,
    ]);
    expect(find.text('个人药箱'), findsOneWidget);
    expect(
        find.byType(AppSegmentedControl<MedicineCabinetScope>), findsOneWidget);
  });

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
    final row = find.byKey(const ValueKey('medicine-row-medicine-1'));
    expect(row, findsOneWidget);
    expect(
      tester.getSemantics(row).label,
      contains('有效期未知'),
    );
    final status = tester.widget<Text>(find.text('有效期未知'));
    expect(status.style?.color, isNot(Colors.green));
  });

  testWidgets('uses native cabinet tabs and a continuous neutral list',
      (tester) async {
    final repository = _Repository(status: MedicineStatus.expired);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MedicineCabinetScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cabinet-scope-tabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('cabinet-filter-tabs')), findsOneWidget);
    expect(
        find.byType(AppSegmentedControl<MedicineCabinetScope>), findsOneWidget);

    final personal = tester.widget<Text>(find.text('个人药箱'));
    final family = tester.widget<Text>(find.text('家庭药箱'));
    expect(personal.style?.fontSize, 13);
    expect(personal.style?.fontWeight, FontWeight.w600);
    expect(personal.style?.color, const Color(0xFF176B52));
    expect(family.style?.color, const Color(0xFF6C6C70));
    expect(
      tester.getSemantics(find.text('个人药箱')).flagsCollection.isSelected,
      Tristate.isTrue,
    );

    final search = tester.widget<TextField>(
      find.byKey(const Key('medicine-search')),
    );
    final decoration = search.decoration!;
    expect(decoration.filled, isTrue);
    expect(decoration.fillColor, const Color(0xFFE5E5EA));
    expect((decoration.enabledBorder as OutlineInputBorder).borderSide,
        BorderSide.none);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, isNull);
    expect(
      Theme.of(tester.element(find.text('药箱'))).scaffoldBackgroundColor,
      const Color(0xFFF2F2F7),
    );
    expect(find.text('已过期'), findsWidgets);
    expect(
        find.byKey(const ValueKey('medicine-row-medicine-1')), findsOneWidget);
  });

  testWidgets('cabinet tabs remain usable at narrow width and 200 percent text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 800),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: MedicineCabinetScreen(repository: _Repository()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人药箱'), findsOneWidget);
    expect(find.text('家庭药箱'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('cabinet-scope-tabs'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('cabinet applies a paired native dark palette', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: MedicineCabinetScreen(repository: _Repository()),
      ),
    );
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.text('药箱')));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
    expect(theme.colorScheme.surface, const Color(0xFF1C1C1E));
    expect(theme.colorScheme.primary, const Color(0xFF78D5B2));
    expect(tester.takeException(), isNull);
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
          onCapture: (_) async => results.moveNext() && results.current,
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

  testWidgets('keeps medicine input visible and explains a save failure',
      (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MedicineCabinetScreen(
          repository: repository,
          onCreateBatch: (_) => Future.error(StateError('create failed')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('录入'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('medicine-entry-name')),
      '依巴斯汀',
    );
    await tester.tap(find.byKey(const Key('medicine-entry-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('medicine-entry-sheet')), findsOneWidget);
    expect(find.text('依巴斯汀'), findsOneWidget);
    expect(find.text('保存失败，请检查网络后重试'), findsOneWidget);
    expect(repository.loadCalls, 1);
  });

  testWidgets('medicine entry reflows at narrow width and large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: MedicineCabinetScreen(
            repository: _Repository(),
            onCreateBatch: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('录入'));
    await tester.pumpAndSettle();

    expect(find.text('药品名称 *'), findsOneWidget);
    expect(find.text('规格'), findsOneWidget);
    expect(find.text('有效期'), findsOneWidget);
    expect(find.text('生产日期（选填）'), findsOneWidget);
    expect(
      find.byKey(const Key('medicine-entry-batch-number')),
      findsNothing,
    );
    expect(find.byKey(const Key('medicine-entry-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
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
  final scopes = <MedicineCabinetScope>[];
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
  Future<MedicineCollection> load({
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
  }) async {
    loadCalls += 1;
    scopes.add(scope);
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
