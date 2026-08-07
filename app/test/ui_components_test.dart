import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smart_reminder_app/ui/components/app_content_state.dart';
import 'package:smart_reminder_app/ui/components/app_list_row.dart';
import 'package:smart_reminder_app/ui/components/app_page_header.dart';
import 'package:smart_reminder_app/ui/components/app_property_row.dart';
import 'package:smart_reminder_app/ui/components/app_segmented_control.dart';
import 'package:smart_reminder_app/ui/components/app_status_banner.dart';

import 'support/test_app.dart';

enum SampleStatus { active, pending }

void main() {
  group('AppStatusBanner', () {
    testWidgets('announces warning title exactly and invokes its action', (
      tester,
    ) async {
      var actionCalls = 0;

      await tester.pumpApp(
        AppStatusBanner(
          severity: AppStatusSeverity.warning,
          title: '未来三天有雨',
          message: '洗车计划可能需要改期',
          actionLabel: '查看',
          onAction: () => actionCalls += 1,
        ),
      );

      expect(
        tester.getSemantics(find.byType(AppStatusBanner)).label,
        '警告：未来三天有雨',
      );
      expect(find.text('洗车计划可能需要改期'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '查看'));
      expect(actionCalls, 1);
    });

    testWidgets('gives every severity a non-color semantic label', (
      tester,
    ) async {
      final expectedLabels = <AppStatusSeverity, String>{
        AppStatusSeverity.info: '信息：标题',
        AppStatusSeverity.success: '成功：标题',
        AppStatusSeverity.warning: '警告：标题',
        AppStatusSeverity.error: '错误：标题',
        AppStatusSeverity.offline: '离线：标题',
      };

      for (final entry in expectedLabels.entries) {
        await tester.pumpApp(
          AppStatusBanner(severity: entry.key, title: '标题'),
        );
        expect(
          tester.getSemantics(find.byType(AppStatusBanner)).label,
          entry.value,
        );
      }
    });

    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      testWidgets('supports every severity with a plain $brightness theme', (
        tester,
      ) async {
        final labels = <AppStatusSeverity, String>{
          AppStatusSeverity.info: '信息',
          AppStatusSeverity.success: '成功',
          AppStatusSeverity.warning: '警告',
          AppStatusSeverity.error: '错误',
          AppStatusSeverity.offline: '离线',
        };

        for (final entry in labels.entries) {
          var actionCalls = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness, useMaterial3: true),
              home: Scaffold(
                body: AppStatusBanner(
                  severity: entry.key,
                  title: '状态',
                  actionLabel: '处理',
                  onAction: () => actionCalls += 1,
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull, reason: entry.key.name);
          expect(
            tester.getSemantics(find.byType(AppStatusBanner)).label,
            '${entry.value}：状态',
          );
          await tester.tap(find.widgetWithText(TextButton, '处理'));
          expect(actionCalls, 1);
        }
      });
    }

    for (final severity in <AppStatusSeverity>[
      AppStatusSeverity.success,
      AppStatusSeverity.warning,
    ]) {
      testWidgets('$severity uses accessible text and action foregrounds', (
        tester,
      ) async {
        await tester.pumpApp(
          AppStatusBanner(
            severity: severity,
            title: '状态标题',
            message: '状态说明',
            actionLabel: '查看',
            onAction: () {},
          ),
        );

        final theme = Theme.of(tester.element(find.byType(AppStatusBanner)));
        final accessibleForeground = theme.colorScheme.onSurface;
        final title = tester.widget<Text>(find.text('状态标题'));
        final message = tester.widget<Text>(find.text('状态说明'));
        final action = tester.widget<TextButton>(
          find.widgetWithText(TextButton, '查看'),
        );

        expect(title.style?.color, accessibleForeground);
        expect(message.style?.color, accessibleForeground);
        expect(
          action.style?.foregroundColor?.resolve(<WidgetState>{}),
          accessibleForeground,
        );
      });
    }
  });

  group('AppSegmentedControl', () {
    testWidgets('keeps stable dimensions while counts change', (tester) async {
      var count = 9;
      late StateSetter setState;

      await tester.pumpApp(
        SizedBox(
          width: 320,
          child: StatefulBuilder(
            builder: (context, update) {
              setState = update;
              return AppSegmentedControl<SampleStatus>(
                value: SampleStatus.active,
                options: <AppSegment<SampleStatus>>[
                  AppSegment(
                    value: SampleStatus.active,
                    label: '进行中',
                    count: count,
                  ),
                  const AppSegment(
                    value: SampleStatus.pending,
                    label: '待处理',
                    count: 2,
                  ),
                ],
                onChanged: (_) {},
              );
            },
          ),
        ),
      );

      final initialSize = tester.getSize(
        find.byType(AppSegmentedControl<SampleStatus>),
      );
      expect(initialSize.height, greaterThanOrEqualTo(44));
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('app-segmented-control-visual-track')),
            )
            .height,
        40,
      );

      setState(() => count = 999);
      await tester.pump();

      expect(
        tester.getSize(find.byType(AppSegmentedControl<SampleStatus>)),
        initialSize,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes selection and changes from active to pending', (
      tester,
    ) async {
      var value = SampleStatus.active;

      await tester.pumpApp(
        StatefulBuilder(
          builder: (context, setState) {
            return AppSegmentedControl<SampleStatus>(
              value: value,
              options: const <AppSegment<SampleStatus>>[
                AppSegment(value: SampleStatus.active, label: '进行中'),
                AppSegment(value: SampleStatus.pending, label: '待处理'),
              ],
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      );

      expect(
        tester.getSemantics(find.text('进行中')).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      await tester.tap(find.text('待处理'));
      await tester.pump();
      expect(value, SampleStatus.pending);
      expect(
        tester.getSemantics(find.text('待处理')).flagsCollection.isSelected,
        Tristate.isTrue,
      );
    });

    testWidgets('keeps full labels visible at 200 percent text scale', (
      tester,
    ) async {
      await tester.pumpApp(
        SizedBox(
          width: 220,
          child: AppSegmentedControl<SampleStatus>(
            value: SampleStatus.active,
            options: const <AppSegment<SampleStatus>>[
              AppSegment(
                value: SampleStatus.active,
                label: '正在进行中',
                count: 18,
              ),
              AppSegment(
                value: SampleStatus.pending,
                label: '等待后续处理',
                count: 206,
              ),
            ],
            onChanged: (_) {},
          ),
        ),
        surfaceSize: const Size(220, 300),
        textScaler: const TextScaler.linear(2),
      );

      for (final label in <String>['正在进行中', '等待后续处理']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.overflow,
            isNot(anyOf(TextOverflow.fade, TextOverflow.ellipsis)));
      }
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('rejects a selected value missing from options', () {
      expect(
        () => AppSegmentedControl<SampleStatus>(
          value: SampleStatus.pending,
          options: const <AppSegment<SampleStatus>>[
            AppSegment(value: SampleStatus.active, label: '进行中'),
            AppSegment(value: SampleStatus.active, label: '处理中'),
          ],
          onChanged: (_) {},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '$error',
            'message',
            contains('exactly one option'),
          ),
        ),
      );
    });

    test('rejects duplicate selected values', () {
      expect(
        () => AppSegmentedControl<SampleStatus>(
          value: SampleStatus.active,
          options: const <AppSegment<SampleStatus>>[
            AppSegment(value: SampleStatus.active, label: '进行中'),
            AppSegment(value: SampleStatus.active, label: '处理中'),
          ],
          onChanged: (_) {},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '$error',
            'message',
            contains('exactly one option'),
          ),
        ),
      );
    });

    test('rejects duplicate values that are not selected', () {
      expect(
        () => AppSegmentedControl<int>(
          value: 1,
          options: const <AppSegment<int>>[
            AppSegment(value: 1, label: '当前'),
            AppSegment(value: 2, label: '等待'),
            AppSegment(value: 2, label: '重复'),
          ],
          onChanged: (_) {},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '$error',
            'message',
            contains('duplicate option value'),
          ),
        ),
      );
    });

    testWidgets('shows a check cue only in the selected segment', (
      tester,
    ) async {
      await tester.pumpApp(
        AppSegmentedControl<SampleStatus>(
          value: SampleStatus.active,
          options: const <AppSegment<SampleStatus>>[
            AppSegment(value: SampleStatus.active, label: '进行中'),
            AppSegment(value: SampleStatus.pending, label: '待处理'),
          ],
          onChanged: (_) {},
        ),
      );

      final selectedSegment = find.ancestor(
        of: find.text('进行中'),
        matching: find.byType(InkWell),
      );
      final pendingSegment = find.ancestor(
        of: find.text('待处理'),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(
          of: selectedSegment,
          matching: find.byIcon(LucideIcons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: pendingSegment,
          matching: find.byIcon(LucideIcons.check),
        ),
        findsNothing,
      );
    });
  });

  group('AppContentState', () {
    testWidgets('loading uses a stable four-row skeleton and no action', (
      tester,
    ) async {
      await tester.pumpApp(const AppContentState.loading());

      expect(find.byKey(const ValueKey('app-content-state-loading')),
          findsOneWidget);
      for (var index = 0; index < 4; index += 1) {
        expect(find.byKey(ValueKey('app-content-skeleton-$index')),
            findsOneWidget);
      }
      final initialSize = tester.getSize(
        find.byKey(const ValueKey('app-content-state-loading')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.getSize(find.byKey(const ValueKey('app-content-state-loading'))),
        initialSize,
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('empty has one primary action only when supplied', (
      tester,
    ) async {
      await tester.pumpApp(
        const AppContentState.empty(
          title: '还没有提醒',
          message: '创建第一个提醒',
        ),
      );

      expect(find.byKey(const ValueKey('app-content-state-empty')),
          findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);

      var calls = 0;
      await tester.pumpApp(
        AppContentState.empty(
          title: '还没有提醒',
          actionLabel: '创建提醒',
          onAction: () => calls += 1,
        ),
      );

      expect(find.widgetWithText(FilledButton, '创建提醒'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.text('创建提醒'));
      expect(calls, 1);
    });

    testWidgets('error exposes retry only when supplied', (tester) async {
      var retries = 0;
      await tester.pumpApp(
        AppContentState.error(
          title: '加载失败',
          message: '请稍后再试',
          actionLabel: '重试',
          onAction: () => retries += 1,
        ),
      );

      expect(find.byKey(const ValueKey('app-content-state-error')),
          findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retries, 1);
    });

    testWidgets('unavailable exposes recovery only when supplied', (
      tester,
    ) async {
      var recoveries = 0;
      await tester.pumpApp(
        AppContentState.unavailable(
          title: '暂时不可用',
          message: '检查网络连接',
          actionLabel: '重新连接',
          onAction: () => recoveries += 1,
        ),
      );

      expect(
        find.byKey(const ValueKey('app-content-state-unavailable')),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, '重新连接'), findsOneWidget);
      await tester.tap(find.text('重新连接'));
      expect(recoveries, 1);
    });
  });

  testWidgets('AppListRow is bordered, wrapping, and accessible when tapped', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpApp(
      AppListRow(
        icon: LucideIcons.bell,
        title: '这是一条需要换行显示的较长提醒标题',
        subtitle: '明天上午九点在家里的客厅提醒我',
        statusText: '已开启',
        onTap: () => taps += 1,
      ),
      surfaceSize: const Size(320, 500),
      textScaler: const TextScaler.linear(2),
    );

    final row = find.byType(AppListRow);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(64));
    expect(find.byType(Card), findsNothing);
    expect(find.text('已开启'), findsOneWidget);
    expect(
        tester.getSize(find.text('这是一条需要换行显示的较长提醒标题')).height, greaterThan(40));
    expect(
      tester
          .getSemantics(row)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(row);
    expect(taps, 1);
  });

  testWidgets('AppListRow positions form one continuous bordered list', (
    tester,
  ) async {
    await tester.pumpApp(
      const Column(
        children: [
          AppListRow(
            icon: LucideIcons.bell,
            title: '第一行',
            subtitle: '顶部边界',
            position: AppListRowPosition.first,
          ),
          AppListRow(
            icon: LucideIcons.clock,
            title: '中间行',
            subtitle: '连续边界',
            position: AppListRowPosition.middle,
          ),
          AppListRow(
            icon: LucideIcons.circleCheck,
            title: '最后一行',
            subtitle: '底部边界',
            position: AppListRowPosition.last,
          ),
        ],
      ),
    );

    BoxDecoration decorationFor(String title) {
      final row = find.ancestor(
        of: find.text(title),
        matching: find.byType(AppListRow),
      );
      final decoratedBox = find.descendant(
        of: row,
        matching: find.byType(DecoratedBox),
      );
      return tester.widget<DecoratedBox>(decoratedBox.first).decoration
          as BoxDecoration;
    }

    final first = decorationFor('第一行');
    final middle = decorationFor('中间行');
    final last = decorationFor('最后一行');
    final firstBorder = first.border! as Border;
    final middleBorder = middle.border! as Border;
    final lastBorder = last.border! as Border;
    final firstRadius = first.borderRadius! as BorderRadius;
    final middleRadius = middle.borderRadius! as BorderRadius;
    final lastRadius = last.borderRadius! as BorderRadius;

    expect(firstBorder.top.style, BorderStyle.solid);
    expect(firstBorder.bottom.style, BorderStyle.solid);
    expect(firstRadius.topLeft, isNot(Radius.zero));
    expect(firstRadius.bottomLeft, Radius.zero);
    expect(middleBorder.top.style, BorderStyle.none);
    expect(middleBorder.bottom.style, BorderStyle.solid);
    expect(middleRadius, BorderRadius.zero);
    expect(lastBorder.top.style, BorderStyle.none);
    expect(lastBorder.bottom.style, BorderStyle.solid);
    expect(lastRadius.topLeft, Radius.zero);
    expect(lastRadius.bottomLeft, isNot(Radius.zero));
    final firstRow = find.ancestor(
      of: find.text('第一行'),
      matching: find.byType(AppListRow),
    );
    final middleRow = find.ancestor(
      of: find.text('中间行'),
      matching: find.byType(AppListRow),
    );
    final lastRow = find.ancestor(
      of: find.text('最后一行'),
      matching: find.byType(AppListRow),
    );
    expect(
      tester.getBottomLeft(firstRow).dy,
      tester.getTopLeft(middleRow).dy,
    );
    expect(tester.getBottomLeft(middleRow).dy, tester.getTopLeft(lastRow).dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppPageHeader stays compact with a stable action area', (
    tester,
  ) async {
    await tester.pumpApp(
      AppPageHeader(
        eyebrow: '提醒计划',
        title: '今天',
        actions: <Widget>[
          Tooltip(
            message: '添加提醒',
            child: IconButton(
              onPressed: () {},
              icon: const Icon(LucideIcons.plus),
            ),
          ),
        ],
      ),
    );

    expect(find.text('提醒计划'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('今天')).flagsCollection.isHeader,
      isTrue,
    );
    final actionSize = tester.getSize(find.byType(IconButton));
    expect(actionSize.width, greaterThanOrEqualTo(44));
    expect(actionSize.height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byType(AppPageHeader)).height, lessThan(96));
  });

  testWidgets('pumpApp MediaQuery reaches dialog overlays', (tester) async {
    late MediaQueryData dialogMediaQuery;

    await tester.pumpApp(
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (dialogContext) {
                  dialogMediaQuery = MediaQuery.of(dialogContext);
                  return const AlertDialog(title: Text('对话框'));
                },
              );
            },
            child: const Text('打开'),
          );
        },
      ),
      surfaceSize: const Size(320, 500),
      textScaler: const TextScaler.linear(2),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('对话框'), findsOneWidget);
    expect(dialogMediaQuery.size, const Size(320, 500));
    expect(dialogMediaQuery.textScaler.scale(10), 20);
  });

  group('AppPropertyRow', () {
    testWidgets('lays out label and value horizontally when space allows', (
      tester,
    ) async {
      await tester.pumpApp(
        const AppPropertyRow(label: '时间', value: Text('明天 09:00')),
      );

      expect(tester.getTopLeft(find.text('明天 09:00')).dx, greaterThan(200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks and wraps key values in narrow 200 percent text', (
      tester,
    ) async {
      const value = '每周一上午九点十五分在上海时区提醒';
      await tester.pumpApp(
        const AppPropertyRow(label: '重复时间', value: Text(value)),
        surfaceSize: const Size(240, 400),
        textScaler: const TextScaler.linear(2),
      );

      expect(
        tester.getTopLeft(find.text(value)).dy,
        greaterThan(tester.getTopLeft(find.text('重复时间')).dy),
      );
      final text = tester.widget<Text>(find.text(value));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(tester.takeException(), isNull);
    });
  });
}
