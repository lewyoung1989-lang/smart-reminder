import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';
import 'package:smart_reminder_app/features/today/data/today_repository.dart';
import 'package:smart_reminder_app/features/today/domain/today_models.dart';
import 'package:smart_reminder_app/features/today/presentation/today_screen.dart';
import 'package:smart_reminder_app/ui/components/app_list_row.dart';
import 'package:smart_reminder_app/ui/components/app_status_banner.dart';

import 'support/test_fixtures.dart';

final testNow = DateTime(2026, 8, 6, 9, 30);

void main() {
  group('TodayScreen', () {
    testWidgets(
        'puts decisions before the timeline and formats the supplied date', (
      tester,
    ) async {
      await pumpTodayScreen(tester, FakeTodayRepository.success());
      await tester.pumpAndSettle();

      expect(find.text('8月6日 周四'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
      expect(find.byKey(const ValueKey('today-decisions-section')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('today-timeline-section')), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('today-decisions-section')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('today-timeline-section')))
              .dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('洗车计划')).dy,
        lessThan(tester.getTopLeft(find.text('早间用药')).dy),
      );
      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('已完成'), findsWidgets);
      expect(find.text('即将开始'), findsWidgets);
      expect(find.byKey(const ValueKey('today-overview')), findsOneWidget);
      expect(find.text('待决定'), findsOneWidget);
      expect(find.text('今日日程'), findsOneWidget);
      expect(find.text('下一项'), findsOneWidget);
    });

    testWidgets(
        'renders the stable loading skeleton until a repository result arrives',
        (
      tester,
    ) async {
      final repository = _DeferredTodayRepository();
      await pumpTodayScreen(tester, repository);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('app-content-state-loading')),
        findsOneWidget,
      );
      expect(find.text('需要你决定'), findsNothing);

      repository.completer.complete(_snapshot());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app-content-state-loading')),
        findsNothing,
      );
      expect(find.text('洗车计划'), findsOneWidget);
    });

    testWidgets('shows an empty state without inventing a primary action', (
      tester,
    ) async {
      await pumpTodayScreen(tester, FakeTodayRepository.empty());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app-content-state-empty')),
        findsOneWidget,
      );
      expect(find.text('今天没有待处理事项'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows a retryable error and reloads through the repository', (
      tester,
    ) async {
      final repository = _RetryTodayRepository();
      await pumpTodayScreen(tester, repository);
      await tester.pumpAndSettle();

      expect(repository.calls, 1);
      expect(
        find.byKey(const ValueKey('app-content-state-error')),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(repository.calls, 2);
      expect(find.text('洗车计划'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('app-content-state-error')),
        findsNothing,
      );
    });

    testWidgets('shows unavailable content instead of a network retry', (
      tester,
    ) async {
      await pumpTodayScreen(tester, FakeTodayRepository.unavailable());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app-content-state-unavailable')),
        findsOneWidget,
      );
      expect(find.text('今天暂时不可用'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重试'), findsNothing);
    });

    testWidgets('renders with a plain theme that has no semantic extension', (
      tester,
    ) async {
      await pumpTodayScreen(
        tester,
        FakeTodayRepository.success(snapshot: _degradedSnapshot()),
        theme: ThemeData(useMaterial3: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('已降级'), findsOneWidget);
      expect(find.text('早间用药'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders degraded attention in the app dark theme', (
      tester,
    ) async {
      await pumpTodayScreen(
        tester,
        FakeTodayRepository.success(snapshot: _degradedSnapshot()),
        theme: AppTheme.dark(),
      );
      await tester.pumpAndSettle();

      expect(find.text('已降级'), findsOneWidget);
      expect(find.text('工作日出门'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'keeps cached decisions and timeline visible under the offline banner',
        (
      tester,
    ) async {
      await pumpTodayScreen(tester, FakeTodayRepository.cachedOffline());
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(AppStatusBanner)).label,
        '离线：正在显示上次同步内容',
      );
      expect(find.text('洗车计划'), findsOneWidget);
      expect(find.text('早间用药'), findsOneWidget);
    });

    testWidgets(
        'renders permission and degraded attention with explicit non-color status',
        (
      tester,
    ) async {
      final snapshot = TodaySnapshot(
        decisions: <AttentionItem>[
          AttentionItem(
            id: 'permissions',
            title: '家庭共享提醒',
            reason: '需要通知权限才能发送家庭共享提醒',
            dueAt: DateTime(2026, 8, 6, 10),
            kind: AttentionKind.permission,
            actionLabel: '前往授权',
          ),
          AttentionItem(
            id: 'provider',
            title: '工作日出门',
            reason: '天气服务暂时不可用，请确认出发时间',
            dueAt: DateTime(2026, 8, 6, 8),
            kind: AttentionKind.degraded,
            actionLabel: '查看详情',
          ),
        ],
        timeline: const <TimelineItem>[],
      );
      await pumpTodayScreen(
          tester, FakeTodayRepository.success(snapshot: snapshot));
      await tester.pumpAndSettle();

      expect(find.text('需要授权'), findsOneWidget);
      expect(find.text('已降级'), findsOneWidget);
      expect(find.text('家庭共享提醒'), findsOneWidget);
      expect(find.text('工作日出门'), findsOneWidget);
      expect(find.text('天气服务暂时不可用，请确认出发时间'), findsOneWidget);
      expect(
        find.bySemanticsLabel('查看详情：工作日出门（未提供打开处理回调）'),
        findsOneWidget,
      );
    });

    testWidgets('maps every timeline status to text', (tester) async {
      final snapshot = TodaySnapshot(
        decisions: const <AttentionItem>[],
        timeline: <TimelineItem>[
          TimelineItem(
            id: 'upcoming',
            title: '即将开始项目',
            subtitle: '来源 A',
            scheduledAt: DateTime(2026, 8, 6, 10),
            status: TimelineStatus.upcoming,
          ),
          TimelineItem(
            id: 'due',
            title: '现在处理项目',
            subtitle: '来源 B',
            scheduledAt: DateTime(2026, 8, 6, 9),
            status: TimelineStatus.due,
          ),
          TimelineItem(
            id: 'completed',
            title: '完成项目',
            subtitle: '来源 C',
            scheduledAt: DateTime(2026, 8, 6, 8),
            status: TimelineStatus.completed,
          ),
          TimelineItem(
            id: 'skipped',
            title: '跳过项目',
            subtitle: '来源 D',
            scheduledAt: DateTime(2026, 8, 6, 7),
            status: TimelineStatus.skipped,
          ),
        ],
      );
      await pumpTodayScreen(
          tester, FakeTodayRepository.success(snapshot: snapshot));
      await tester.pumpAndSettle();

      expect(find.text('即将开始'), findsOneWidget);
      expect(find.text('现在处理'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('已跳过'), findsOneWidget);
    });

    testWidgets(
        'keeps completed and skipped timeline rows readable without opacity', (
      tester,
    ) async {
      final snapshot = TodaySnapshot(
        decisions: const <AttentionItem>[],
        timeline: <TimelineItem>[
          TimelineItem(
            id: 'completed',
            title: '完成事项',
            subtitle: '来源 A',
            scheduledAt: DateTime(2026, 8, 6, 8),
            status: TimelineStatus.completed,
          ),
          TimelineItem(
            id: 'skipped',
            title: '跳过事项',
            subtitle: '来源 B',
            scheduledAt: DateTime(2026, 8, 6, 9),
            status: TimelineStatus.skipped,
          ),
        ],
      );
      await pumpTodayScreen(
        tester,
        FakeTodayRepository.success(snapshot: snapshot),
      );
      await tester.pumpAndSettle();

      for (final title in <String>['完成事项', '跳过事项']) {
        expect(
          find.ancestor(of: find.text(title), matching: find.byType(Opacity)),
          findsNothing,
        );
      }
      final theme = Theme.of(tester.element(find.byType(TodayScreen)));
      expect(
        tester.widget<Text>(find.text('已完成')).style?.color,
        theme.colorScheme.onSurfaceVariant,
      );
      expect(
        tester.widget<Text>(find.text('已跳过')).style?.color,
        theme.colorScheme.onSurfaceVariant,
      );
    });

    testWidgets('sorts decisions and timeline by their scheduled time', (
      tester,
    ) async {
      final snapshot = TodaySnapshot(
        decisions: <AttentionItem>[
          AttentionItem(
            id: 'later-decision',
            title: '稍后决定',
            reason: '截止时间较晚',
            dueAt: DateTime(2026, 8, 6, 18),
            kind: AttentionKind.confirmation,
            actionLabel: '确认',
          ),
          AttentionItem(
            id: 'early-decision',
            title: '优先决定',
            reason: '截止时间较早',
            dueAt: DateTime(2026, 8, 6, 10),
            kind: AttentionKind.permission,
            actionLabel: '授权',
          ),
        ],
        timeline: <TimelineItem>[
          TimelineItem(
            id: 'later-timeline',
            title: '晚间事项',
            subtitle: '20:00',
            scheduledAt: DateTime(2026, 8, 6, 20),
            status: TimelineStatus.upcoming,
          ),
          TimelineItem(
            id: 'early-timeline',
            title: '上午事项',
            subtitle: '10:00',
            scheduledAt: DateTime(2026, 8, 6, 10),
            status: TimelineStatus.upcoming,
          ),
        ],
      );
      await pumpTodayScreen(
        tester,
        FakeTodayRepository.success(snapshot: snapshot),
        surfaceSize: const Size(800, 1200),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('优先决定')).dy,
        lessThan(tester.getTopLeft(find.text('稍后决定')).dy),
      );
      expect(
        tester.getTopLeft(find.text('上午事项')).dy,
        lessThan(tester.getTopLeft(find.text('晚间事项')).dy),
      );
    });

    testWidgets('renders decisions as a continuous neutral list', (
      tester,
    ) async {
      final snapshot = TodaySnapshot(
        decisions: <AttentionItem>[
          AttentionItem(
            id: 'later-decision',
            title: '稍后决定',
            reason: '截止时间较晚',
            dueAt: DateTime(2026, 8, 6, 18),
            kind: AttentionKind.confirmation,
            actionLabel: '确认',
          ),
          AttentionItem(
            id: 'early-decision',
            title: '优先决定',
            reason: '截止时间较早',
            dueAt: DateTime(2026, 8, 6, 10),
            kind: AttentionKind.permission,
            actionLabel: '授权',
          ),
        ],
        timeline: const <TimelineItem>[],
      );
      await pumpTodayScreen(
        tester,
        FakeTodayRepository.success(snapshot: snapshot),
        surfaceSize: const Size(800, 1000),
      );
      await tester.pumpAndSettle();

      final earlyRow = find.byKey(
        const ValueKey('today-decision-row-early-decision'),
      );
      final laterRow = find.byKey(
        const ValueKey('today-decision-row-later-decision'),
      );
      final theme = Theme.of(tester.element(find.byType(TodayScreen)));
      final earlyDecoration =
          tester.widget<DecoratedBox>(earlyRow).decoration as BoxDecoration;
      final laterDecoration =
          tester.widget<DecoratedBox>(laterRow).decoration as BoxDecoration;
      expect(earlyDecoration.color, theme.colorScheme.surface);
      expect(earlyDecoration.borderRadius, isNull);
      expect(earlyDecoration.border, isNotNull);
      expect(laterDecoration.color, theme.colorScheme.surface);
      expect(laterDecoration.borderRadius, isNull);
      expect(laterDecoration.border, isNull);
      expect(
        tester.getTopLeft(laterRow).dy,
        tester.getBottomLeft(earlyRow).dy,
      );
    });

    testWidgets('keeps a newer load when an older load completes afterward', (
      tester,
    ) async {
      final first = _DeferredTodayRepository();
      final second = _DeferredTodayRepository();
      final screenKey = GlobalKey();
      final olderSnapshot = _snapshotWithTitle('旧内容');
      final newerSnapshot = _snapshotWithTitle('新内容');

      await pumpTodayScreen(tester, first, screenKey: screenKey);
      await tester.pump();
      await pumpTodayScreen(tester, second, screenKey: screenKey);
      await tester.pump();

      second.completer.complete(newerSnapshot);
      await tester.pumpAndSettle();
      expect(find.text('新内容'), findsOneWidget);

      first.completer.complete(olderSnapshot);
      await tester.pumpAndSettle();
      expect(find.text('新内容'), findsOneWidget);
      expect(find.text('旧内容'), findsNothing);
    });

    testWidgets('shows an error when a replacement repository fails', (
      tester,
    ) async {
      final screenKey = GlobalKey();
      await pumpTodayScreen(
        tester,
        FakeTodayRepository.success(),
        screenKey: screenKey,
      );
      await tester.pumpAndSettle();
      expect(find.text('洗车计划'), findsOneWidget);

      await pumpTodayScreen(
        tester,
        FakeTodayRepository.error(),
        screenKey: screenKey,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app-content-state-error')),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
      expect(find.text('洗车计划'), findsNothing);
    });

    testWidgets(
        'shows unavailable state when a replacement repository is unavailable',
        (
      tester,
    ) async {
      final screenKey = GlobalKey();
      await pumpTodayScreen(
        tester,
        FakeTodayRepository.success(),
        screenKey: screenKey,
      );
      await tester.pumpAndSettle();
      expect(find.text('洗车计划'), findsOneWidget);

      await pumpTodayScreen(
        tester,
        FakeTodayRepository.unavailable(),
        screenKey: screenKey,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app-content-state-unavailable')),
        findsOneWidget,
      );
      expect(find.text('今天暂时不可用'), findsOneWidget);
      expect(find.text('洗车计划'), findsNothing);
    });

    testWidgets(
        'opens settings, attention, and timeline through supplied callbacks', (
      tester,
    ) async {
      AttentionItem? openedAttention;
      TimelineItem? openedTimeline;
      var settingsCalls = 0;
      await pumpTodayScreen(
        tester,
        FakeTodayRepository.success(),
        surfaceSize: const Size(800, 1200),
        onOpenSettings: () => settingsCalls += 1,
        onOpenAttention: (item) async {
          openedAttention = item;
        },
        onOpenTimeline: (item) => openedTimeline = item,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('打开设置'));
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.tap(find.byType(AppListRow).first);

      expect(settingsCalls, 1);
      expect(openedAttention?.id, 'demo-car-wash');
      expect(openedTimeline?.id, 'morning-medication');
    });

    testWidgets('reloads today content after a decision action completes', (
      tester,
    ) async {
      final repository = _SequenceTodayRepository([
        _snapshotWithTitle('需要记录服药'),
        TodaySnapshot(decisions: const [], timeline: const []),
      ]);
      final completedActions = <String>[];
      await pumpTodayScreen(
        tester,
        repository,
        surfaceSize: const Size(800, 1200),
        onOpenAttention: (item) async {
          completedActions.add(item.id);
        },
      );
      await tester.pumpAndSettle();

      expect(find.text('需要记录服药'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();

      expect(completedActions, ['需要记录服药']);
      expect(repository.calls, 2);
      expect(find.text('需要记录服药'), findsNothing);
      expect(find.text('今天没有待处理事项'), findsOneWidget);
    });

    testWidgets('does not overflow at narrow width and 200 percent text scale',
        (
      tester,
    ) async {
      await pumpTodayScreen(
        tester,
        FakeTodayRepository.success(),
        surfaceSize: const Size(320, 568),
        textScaler: const TextScaler.linear(2),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('早间用药'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('早间用药'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> pumpTodayScreen(
  WidgetTester tester,
  TodayRepository repository, {
  Size surfaceSize = const Size(800, 900),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeData? theme,
  Key? screenKey,
  VoidCallback? onOpenSettings,
  AttentionActionCallback? onOpenAttention,
  ValueChanged<TimelineItem>? onOpenTimeline,
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
        child: TodayScreen(
          key: screenKey,
          repository: repository,
          now: testNow,
          onOpenSettings: onOpenSettings,
          onOpenAttention: onOpenAttention,
          onOpenTimeline: onOpenTimeline,
        ),
      ),
    ),
  );
}

TodaySnapshot _snapshot() {
  return TodaySnapshot(
    decisions: <AttentionItem>[
      AttentionItem(
        id: 'car-wash',
        title: '洗车计划',
        reason: '天气晴朗，等待你确认洗车时间',
        dueAt: DateTime(2026, 8, 6, 18),
        kind: AttentionKind.confirmation,
        actionLabel: '确认',
      ),
    ],
    timeline: <TimelineItem>[
      TimelineItem(
        id: 'medication',
        title: '早间用药',
        subtitle: '布洛芬缓释胶囊',
        scheduledAt: DateTime(2026, 8, 6, 8),
        status: TimelineStatus.completed,
      ),
    ],
  );
}

TodaySnapshot _degradedSnapshot() {
  return TodaySnapshot(
    decisions: <AttentionItem>[
      AttentionItem(
        id: 'degraded',
        title: '工作日出门',
        reason: '天气服务暂时不可用，请确认出发时间',
        dueAt: DateTime(2026, 8, 6, 8),
        kind: AttentionKind.degraded,
        actionLabel: '查看详情',
      ),
    ],
    timeline: <TimelineItem>[
      TimelineItem(
        id: 'medication',
        title: '早间用药',
        subtitle: '布洛芬缓释胶囊',
        scheduledAt: DateTime(2026, 8, 6, 8),
        status: TimelineStatus.completed,
      ),
    ],
  );
}

TodaySnapshot _snapshotWithTitle(String title) {
  return TodaySnapshot(
    decisions: <AttentionItem>[
      AttentionItem(
        id: title,
        title: title,
        reason: '用于加载顺序验证',
        dueAt: DateTime(2026, 8, 6, 10),
        kind: AttentionKind.confirmation,
        actionLabel: '确认',
      ),
    ],
    timeline: const <TimelineItem>[],
  );
}

class _DeferredTodayRepository implements TodayRepository {
  final Completer<TodaySnapshot> completer = Completer<TodaySnapshot>();

  @override
  Future<TodaySnapshot> load() => completer.future;
}

class _RetryTodayRepository implements TodayRepository {
  var calls = 0;

  @override
  Future<TodaySnapshot> load() {
    calls += 1;
    if (calls == 1) return Future<TodaySnapshot>.error(StateError('failed'));
    return Future<TodaySnapshot>.value(_snapshot());
  }
}

class _SequenceTodayRepository implements TodayRepository {
  _SequenceTodayRepository(this.snapshots);

  final List<TodaySnapshot> snapshots;
  var calls = 0;

  @override
  Future<TodaySnapshot> load() async {
    final index = calls;
    calls += 1;
    return snapshots[index];
  }
}
