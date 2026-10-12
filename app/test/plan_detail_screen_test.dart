import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';
import 'package:smart_reminder_app/features/plans/domain/plan_models.dart';
import 'package:smart_reminder_app/features/plans/presentation/edit_medication_plan_sheet.dart';
import 'package:smart_reminder_app/features/plans/presentation/plan_detail_screen.dart';
import 'package:smart_reminder_app/ui/components/app_status_banner.dart';

import 'support/test_fixtures.dart';

void main() {
  group('PlanDetailScreen', () {
    testWidgets('departure detail explains live dependencies and active action',
        (tester) async {
      await pumpPlanDetail(tester, departureDetail, onPause: () async {});

      expect(find.text('08:45 公司'), findsOneWidget);
      expect(find.text('路线、天气'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '暂停计划'), findsOneWidget);
      expect(find.byType(AppStatusBanner), findsOneWidget);
    });

    testWidgets('shows the original reminder expression when available',
        (tester) async {
      await pumpPlanDetail(tester, _detailWithSourceText());

      expect(find.text('原始备注'), findsOneWidget);
      expect(find.text('每天晚上六点半提醒我饭后吃拜新同一片'), findsOneWidget);
    });

    testWidgets('shows dose label when present', (tester) async {
      await pumpPlanDetail(tester, _detailWithDose());

      expect(find.text('单次剂量'), findsOneWidget);
      expect(find.text('每次150mg'), findsOneWidget);
      // 空查询来源不展示
      expect(find.text('查询来源'), findsNothing);
      expect(find.text('无额外数据来源'), findsNothing);
    });

    testWidgets('active detail invokes a supplied pause callback',
        (tester) async {
      var pauses = 0;
      await pumpPlanDetail(
        tester,
        departureDetail,
        onPause: () async => pauses += 1,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, '暂停计划'));
      await tester.pumpAndSettle();
      expect(pauses, 1);
    });

    testWidgets('paused detail invokes a supplied resume callback',
        (tester) async {
      var resumes = 0;
      await pumpPlanDetail(
        tester,
        _pausedDetail(),
        onResume: () async => resumes += 1,
      );
      expect(find.widgetWithText(OutlinedButton, '恢复计划'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '恢复计划'));
      await tester.pumpAndSettle();
      expect(resumes, 1);
    });

    testWidgets('more menu invokes a supplied edit callback', (tester) async {
      var edits = 0;
      await pumpPlanDetail(
        tester,
        departureDetail,
        onEdit: () => edits += 1,
      );
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑计划'));
      await tester.pumpAndSettle();
      expect(edits, 1);
    });

    testWidgets('editing medication plan opens structured sheet and updates directly',
        (tester) async {
      String? savedMedicine;
      String? savedDose;
      List<String>? savedTimes;

      final updatedDetail = PlanDetail(
        summary: PlanSummary(
          id: 'med-plan-1',
          title: '阿莫西林胶囊服药提醒',
          subtitle: '阿莫西林胶囊 · 每次2粒',
          nextRunAt: fixedNow,
          status: PlanStatus.active,
          kind: PlanKind.medication,
        ),
        doseLabel: '每次2粒',
        medicationConfig: MedicationConfig(
          medicineName: '阿莫西林胶囊',
          doseText: '每次2粒',
          times: const ['08:00', '20:00'],
        ),
        queriedSources: const [],
        reminderLabel: '每天 08:00、20:00 通知提醒',
        executions: const [],
      );

      await pumpPlanDetail(
        tester,
        _detailWithDose(),
        onUpdateMedication: ({
          required String medicineName,
          required String doseText,
          required List<String> times,
        }) async {
          savedMedicine = medicineName;
          savedDose = doseText;
          savedTimes = times;
          return updatedDetail;
        },
      );

      // 打开编辑浮层
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑计划'));
      await tester.pumpAndSettle();

      // 验证浮层元素
      expect(find.text('编辑用药计划'), findsOneWidget);
      expect(find.byType(EditMedicationPlanSheet), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '药品名称'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '单次剂量'), findsOneWidget);
      expect(find.text('07:30'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget);
      expect(find.text('保存修改'), findsOneWidget);

      // 修改药品名称和剂量
      await tester.enterText(
          find.widgetWithText(TextFormField, '盐酸普罗帕酮片'), '阿莫西林胶囊');
      await tester.enterText(
          find.widgetWithText(TextFormField, '每次150mg'), '每次2粒');

      // 点击保存修改
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();

      // 验证回调参数
      expect(savedMedicine, '阿莫西林胶囊');
      expect(savedDose, '每次2粒');
      expect(savedTimes, containsAll(['07:30', '15:00', '22:00']));

      // 验证详情页原地刷新
      expect(find.text('阿莫西林胶囊服药提醒'), findsOneWidget);
      expect(find.text('每次2粒'), findsOneWidget);
    });

    testWidgets(
        'missing actions are disabled with an unavailable semantic reason',
        (tester) async {
      await pumpPlanDetail(tester, departureDetail);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, '暂停计划'))
              .onPressed,
          isNull);
      expect(find.bySemanticsLabel('暂停计划，服务尚未接入'), findsOneWidget);
    });

    testWidgets('confirms delete and invokes the callback once',
        (tester) async {
      var deletes = 0;
      await pumpPlanDetail(tester, departureDetail,
          onDelete: () async => deletes += 1);
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除计划'));
      await tester.pumpAndSettle();
      expect(find.text('删除这个计划？'), findsOneWidget);
      final deleteButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '删除'),
      );
      expect(
        deleteButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        AppTheme.light().colorScheme.error,
      );
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
    });

    testWidgets('shows action errors without changing the active status',
        (tester) async {
      await pumpPlanDetail(
        tester,
        departureDetail,
        onPause: () => Future<void>.error(StateError('pause failed')),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, '暂停计划'));
      await tester.pumpAndSettle();
      expect(find.text('操作失败，请稍后重试'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '暂停计划'), findsOneWidget);
      expect(find.text('恢复计划'), findsNothing);
    });

    testWidgets('does not overflow at narrow width and 200 percent text scale',
        (tester) async {
      await pumpPlanDetail(
        tester,
        departureDetail,
        surfaceSize: const Size(320, 568),
        textScaler: const TextScaler.linear(2),
        theme: AppTheme.dark(),
      );
      await tester.drag(find.byType(Scrollable), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> pumpPlanDetail(
  WidgetTester tester,
  PlanDetail detail, {
  Future<void> Function()? onPause,
  Future<void> Function()? onResume,
  VoidCallback? onEdit,
  Future<void> Function()? onDelete,
  Future<PlanDetail> Function({
    required String medicineName,
    required String doseText,
    required List<String> times,
  })? onUpdateMedication,
  Size surfaceSize = const Size(800, 900),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surfaceSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: surfaceSize, textScaler: textScaler),
        child: PlanDetailScreen(
          detail: detail,
          onPause: onPause,
          onResume: onResume,
          onEdit: onEdit,
          onDelete: onDelete,
          onUpdateMedication: onUpdateMedication,
        ),
      ),
    ),
  );
}

PlanDetail _pausedDetail() {
  final summary = PlanSummary(
    id: 'paused',
    title: '暂停提醒',
    subtitle: '等待恢复',
    nextRunAt: fixedNow,
    status: PlanStatus.paused,
    kind: PlanKind.reminder,
  );
  return PlanDetail(
    summary: summary,
    queriedSources: const [],
    reminderLabel: '通知提醒',
    executions: const [],
  );
}

PlanDetail _detailWithSourceText() {
  final summary = PlanSummary(
    id: 'source-text',
    title: '晚间用药',
    subtitle: '拜新同 · 1片',
    nextRunAt: fixedNow,
    status: PlanStatus.active,
    kind: PlanKind.medication,
  );
  return PlanDetail(
    summary: summary,
    queriedSources: const [],
    reminderLabel: '每天 18:30 通知提醒',
    executions: const [],
    sourceText: '每天晚上六点半提醒我饭后吃拜新同一片',
  );
}

PlanDetail _detailWithDose() {
  final summary = PlanSummary(
    id: 'medication-dose',
    title: '服药提醒',
    subtitle: '盐酸普罗帕酮片 · 每次150mg',
    nextRunAt: fixedNow,
    status: PlanStatus.active,
    kind: PlanKind.medication,
  );
  return PlanDetail(
    summary: summary,
    doseLabel: '每次150mg',
    medicationConfig: MedicationConfig(
      medicineName: '盐酸普罗帕酮片',
      doseText: '每次150mg',
      times: const ['07:30', '15:00', '22:00'],
    ),
    queriedSources: const [],
    reminderLabel: '每天 07:30、15:00、22:00 通知提醒',
    executions: const [],
  );
}

