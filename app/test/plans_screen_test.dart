import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';
import 'package:smart_reminder_app/core/data/feature_unavailable_exception.dart';
import 'package:smart_reminder_app/features/plans/data/plan_repository.dart';
import 'package:smart_reminder_app/features/plans/domain/plan_models.dart';
import 'package:smart_reminder_app/features/plans/presentation/plan_detail_screen.dart';
import 'package:smart_reminder_app/features/plans/presentation/plans_screen.dart';
import 'package:smart_reminder_app/ui/components/app_list_row.dart';
import 'package:smart_reminder_app/ui/components/app_status_banner.dart';

import 'support/test_fixtures.dart';

void main() {
  group('PlansScreen', () {
    testWidgets('status segments filter the continuous plan list',
        (tester) async {
      await pumpPlansScreen(tester, DemoPlanRepository(now: fixedNow));
      await tester.pumpAndSettle();

      expect(find.text('工作日出门'), findsOneWidget);
      expect(find.text('早间用药'), findsNothing);
      expect(find.byType(AppListRow), findsWidgets);
      final rows = tester.widgetList<AppListRow>(find.byType(AppListRow));
      expect(rows.first.position, AppListRowPosition.first);
      expect(rows.last.position, AppListRowPosition.last);

      await tester.tap(find.text('待确认'));
      await tester.pumpAndSettle();

      expect(find.text('早间用药'), findsOneWidget);
      expect(find.text('工作日出门'), findsNothing);
    });

    testWidgets('kind filter sheet filters and clears the visible list',
        (tester) async {
      await pumpPlansScreen(tester, DemoPlanRepository(now: fixedNow));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('筛选计划'));
      await tester.pumpAndSettle();
      expect(find.text('计划类型'), findsOneWidget);
      expect(find.text('运行中'), findsWidgets);

      await tester.tap(find.text('用药'));
      await tester.pumpAndSettle();
      expect(find.text('周末维生素'), findsOneWidget);
      expect(find.text('工作日出门'), findsNothing);

      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      expect(find.text('工作日出门'), findsOneWidget);
    });

    testWidgets('shows loading empty retry unavailable and offline states',
        (tester) async {
      final deferred = _DeferredPlanRepository();
      await pumpPlansScreen(tester, deferred);
      await tester.pump();
      expect(find.byKey(const ValueKey('app-content-state-loading')),
          findsOneWidget);

      deferred.completer.complete(PlanCollection(items: const []));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-content-state-empty')),
          findsOneWidget);

      await pumpPlansScreen(tester, _RetryPlanRepository());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-content-state-error')),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();
      expect(find.text('工作日出门'), findsOneWidget);

      await pumpPlansScreen(tester, FakePlanRepository.unavailable());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-content-state-unavailable')),
          findsOneWidget);

      await pumpPlansScreen(tester, FakePlanRepository.cachedOffline());
      await tester.pumpAndSettle();
      expect(find.byType(AppStatusBanner), findsOneWidget);
      expect(find.text('工作日出门'), findsOneWidget);
    });

    testWidgets(
        'pushes detail on compact layouts and selects detail in wide panes',
        (tester) async {
      await pumpPlansScreen(
        tester,
        FakePlanRepository.success(),
        surfaceSize: const Size(390, 844),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppListRow));
      await tester.pumpAndSettle();
      expect(find.byType(PlanDetailScreen), findsOneWidget);
      expect(find.text('08:45 公司'), findsOneWidget);
      Navigator.of(tester.element(find.byType(PlanDetailScreen))).pop();
      await tester.pumpAndSettle();

      await pumpPlansScreen(
        tester,
        _TwoActivePlansRepository(),
        surfaceSize: const Size(1280, 800),
      );
      await tester.pumpAndSettle();
      expect(find.text('08:45 公司'), findsNothing);

      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is AppListRow && widget.title == '工作日出门',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlansScreen), findsOneWidget);
      expect(find.byType(PlanDetailScreen), findsOneWidget);
      expect(find.text('08:45 公司'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact detail back action returns to the plan list',
        (tester) async {
      await pumpPlansScreen(
        tester,
        FakePlanRepository.success(),
        surfaceSize: const Size(390, 844),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppListRow));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('返回计划'));
      await tester.pumpAndSettle();

      expect(find.byType(PlansScreen), findsOneWidget);
      expect(find.byType(PlanDetailScreen), findsNothing);
      expect(find.byType(AppListRow), findsOneWidget);
    });

    testWidgets('wide detail error keeps the list visible and retries',
        (tester) async {
      final repository = _RetryDetailPlanRepository();
      await pumpPlansScreen(
        tester,
        repository,
        surfaceSize: const Size(1280, 800),
      );
      await tester.pumpAndSettle();

      expect(find.text('工作日出门'), findsOneWidget);
      expect(find.text('计划详情加载失败'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(repository.detailCalls, 2);
      expect(find.text('08:45 公司'), findsOneWidget);
      expect(find.text('计划详情加载失败'), findsNothing);
    });

    testWidgets('wide unavailable detail keeps the list visible',
        (tester) async {
      await pumpPlansScreen(
        tester,
        _UnavailableDetailPlanRepository(),
        surfaceSize: const Size(1280, 800),
      );
      await tester.pumpAndSettle();

      expect(find.text('工作日出门'), findsOneWidget);
      expect(find.text('计划详情暂时不可用'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重试'), findsNothing);
    });

    testWidgets('uses supplied open callback instead of pushing detail',
        (tester) async {
      PlanSummary? opened;
      await pumpPlansScreen(
        tester,
        FakePlanRepository.success(),
        onOpenPlan: (plan) => opened = plan,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppListRow));
      expect(opened?.id, 'workday-departure');
      expect(find.byType(PlanDetailScreen), findsNothing);
    });

    testWidgets('does not overflow at narrow width and 200 percent text scale',
        (tester) async {
      await pumpPlansScreen(
        tester,
        DemoPlanRepository(now: fixedNow),
        surfaceSize: const Size(320, 568),
        textScaler: const TextScaler.linear(2),
        theme: AppTheme.dark(),
      );
      await tester.pumpAndSettle();
      expect(find.text('工作日出门'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the plan header and status tabs fixed while rows scroll',
        (tester) async {
      await pumpPlansScreen(
        tester,
        _ManyActivePlansRepository(),
        surfaceSize: const Size(393, 700),
      );
      await tester.pumpAndSettle();

      final scroll = find.byKey(const PageStorageKey('plans-list-scroll'));
      final header = find.byKey(const ValueKey('plans-fixed-header'));
      final tabs = find.byKey(const ValueKey('plans-status-tabs'));
      final firstRow = find.text('计划 1');
      final initialHeaderTop = tester.getTopLeft(header).dy;
      final initialTabsTop = tester.getTopLeft(tabs).dy;
      final initialRowTop = tester.getTopLeft(firstRow).dy;

      await tester.drag(scroll, const Offset(0, -240));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(header).dy, initialHeaderTop);
      expect(tester.getTopLeft(tabs).dy, initialTabsTop);
      expect(tester.getTopLeft(firstRow).dy, lessThan(initialRowTop));
      expect(tester.takeException(), isNull);
    });

    testWidgets('left swipe deletes a periodic plan after confirmation',
        (tester) async {
      final repository = _DeletablePlanRepository();
      await pumpPlansScreen(
        tester,
        repository,
        surfaceSize: const Size(390, 844),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(
        const ValueKey('dismiss-plan-workday-departure'),
      );
      await tester.drag(row, const Offset(-320, 0));
      await tester.pumpAndSettle();

      expect(find.text('删除这个计划？'), findsOneWidget);
      expect(repository.deletedIds, isEmpty);

      await tester.tap(find.byKey(const ValueKey('confirm-delete-plan')));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, ['workday-departure']);
      expect(find.text('工作日出门'), findsNothing);
      expect(find.text('计划已删除'), findsOneWidget);
    });

    testWidgets('cancelling swipe deletion keeps the periodic plan',
        (tester) async {
      final repository = _DeletablePlanRepository();
      await pumpPlansScreen(
        tester,
        repository,
        surfaceSize: const Size(390, 844),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey('dismiss-plan-workday-departure')),
        const Offset(-320, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, isEmpty);
      expect(find.text('工作日出门'), findsOneWidget);
    });

    testWidgets('failed swipe deletion restores the periodic plan row',
        (tester) async {
      final repository = _DeletablePlanRepository(shouldFail: true);
      await pumpPlansScreen(
        tester,
        repository,
        surfaceSize: const Size(390, 844),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey('dismiss-plan-workday-departure')),
        const Offset(-320, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-delete-plan')));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, isEmpty);
      expect(find.text('工作日出门'), findsOneWidget);
      expect(find.text('删除失败，请稍后重试'), findsOneWidget);
    });
  });
}

Future<void> pumpPlansScreen(
  WidgetTester tester,
  PlanRepository repository, {
  Size surfaceSize = const Size(800, 900),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeData? theme,
  ValueChanged<PlanSummary>? onOpenPlan,
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
        child: PlansScreen(repository: repository, onOpenPlan: onOpenPlan),
      ),
    ),
  );
}

class _DeferredPlanRepository implements PlanRepository {
  final completer = Completer<PlanCollection>();

  @override
  Future<PlanDetail> getById(String id) => Future.error(StateError('unused'));

  @override
  Future<PlanCollection> load() => completer.future;
}

class _RetryPlanRepository implements PlanRepository {
  var calls = 0;

  @override
  Future<PlanDetail> getById(String id) async => departureDetail;

  @override
  Future<PlanCollection> load() {
    calls += 1;
    if (calls == 1) return Future.error(StateError('failed'));
    return Future.value(PlanCollection(items: [departureDetail.summary]));
  }
}

class _TwoActivePlansRepository implements PlanRepository {
  final _otherSummary = PlanSummary(
    id: 'evening-blood-pressure',
    title: '晚间血压记录',
    subtitle: '每天睡前记录',
    nextRunAt: DateTime(2026, 8, 6, 21),
    status: PlanStatus.active,
    kind: PlanKind.reminder,
  );

  @override
  Future<PlanDetail> getById(String id) async {
    if (id == departureDetail.summary.id) return departureDetail;
    if (id == _otherSummary.id) {
      return PlanDetail(
        summary: _otherSummary,
        queriedSources: const [],
        reminderLabel: '按计划时间通知提醒',
        executions: const [],
      );
    }
    throw StateError('Unknown plan: $id');
  }

  @override
  Future<PlanCollection> load() async {
    return PlanCollection(items: [_otherSummary, departureDetail.summary]);
  }
}

class _ManyActivePlansRepository implements PlanRepository {
  late final List<PlanSummary> _items = List<PlanSummary>.generate(
    12,
    (index) => PlanSummary(
      id: 'plan-${index + 1}',
      title: '计划 ${index + 1}',
      subtitle: '每日提醒',
      nextRunAt: DateTime(2026, 8, 6, 8 + index),
      status: PlanStatus.active,
      kind: PlanKind.reminder,
    ),
  );

  @override
  Future<PlanDetail> getById(String id) => Future.error(StateError('unused'));

  @override
  Future<PlanCollection> load() async => PlanCollection(items: _items);
}

class _RetryDetailPlanRepository implements PlanRepository {
  var detailCalls = 0;

  @override
  Future<PlanDetail> getById(String id) {
    detailCalls += 1;
    if (detailCalls == 1) return Future.error(StateError('detail failed'));
    return Future.value(departureDetail);
  }

  @override
  Future<PlanCollection> load() async {
    return PlanCollection(items: [departureDetail.summary]);
  }
}

class _UnavailableDetailPlanRepository implements PlanRepository {
  @override
  Future<PlanDetail> getById(String id) {
    return Future.error(const FeatureUnavailableException('plans'));
  }

  @override
  Future<PlanCollection> load() async {
    return PlanCollection(items: [departureDetail.summary]);
  }
}

class _DeletablePlanRepository implements PlanRepository, PlanActions {
  _DeletablePlanRepository({this.shouldFail = false});

  final bool shouldFail;
  final deletedIds = <String>[];

  @override
  Future<PlanDetail> getById(String id) async => departureDetail;

  @override
  Future<PlanCollection> load() async => PlanCollection(
        items: deletedIds.contains(departureDetail.summary.id)
            ? const []
            : [departureDetail.summary],
      );

  @override
  Future<void> delete(String id) async {
    if (shouldFail) throw StateError('delete failed');
    deletedIds.add(id);
  }

  @override
  Future<PlanDetail> pause(String id) async => departureDetail;

  @override
  Future<PlanDetail> resume(String id) async => departureDetail;
}
