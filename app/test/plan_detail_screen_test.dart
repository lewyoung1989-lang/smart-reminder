import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';
import 'package:smart_reminder_app/features/plans/domain/plan_models.dart';
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
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
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
