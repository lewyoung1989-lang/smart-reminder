import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/features/reminder_drafts/presentation/reminder_draft_screen.dart';
import 'package:smart_reminder_app/ui/components/app_page_header.dart';
import 'package:smart_reminder_app/ui/components/app_property_row.dart';
import 'package:smart_reminder_app/ui/components/app_status_banner.dart';

void main() {
  ReminderDraft draft({List<String> ambiguities = const []}) => ReminderDraft(
        id: 'draft-1',
        title: '喝水',
        scheduledAt: DateTime(2026, 8, 4, 10, 1),
        timezone: 'Asia/Shanghai',
        severity: ReminderSeverity.notification,
        weatherMessage: null,
        ambiguities: ambiguities,
        parserSource: 'local_fallback',
      );

  Widget app({
    required ReminderDraft value,
    required Future<void> Function() onConfirm,
  }) =>
      MaterialApp(
        home: ReminderDraftScreen(
          sourceText: '1分钟后提醒我喝水',
          draft: value,
          onConfirm: onConfirm,
          onEdit: () {},
          now: DateTime(2026, 8, 4, 10),
        ),
      );

  testWidgets('confirmation shows original expression and structured plan', (
    tester,
  ) async {
    await tester.pumpWidget(app(value: draft(), onConfirm: () async {}));

    expect(find.text('确认计划'), findsOneWidget);
    expect(find.text('1分钟后提醒我喝水'), findsOneWidget);
    expect(find.text('本地规则（模型不可用）'), findsOneWidget);
    expect(find.byType(AppPageHeader), findsOneWidget);
    expect(find.byType(AppStatusBanner), findsOneWidget);
    expect(find.byType(AppPropertyRow), findsAtLeastNWidgets(4));
    expect(find.widgetWithText(OutlinedButton, '修改'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认'), findsOneWidget);
  });

  testWidgets('confirmation keeps content safe and actions in the thumb zone', (
    tester,
  ) async {
    await tester.pumpWidget(app(value: draft(), onConfirm: () async {}));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(find.byType(SafeArea), findsWidgets);
    expect(scaffold.bottomNavigationBar, isNotNull);
  });

  testWidgets('ambiguity warning disables confirmation', (tester) async {
    await tester.pumpWidget(
      app(value: draft(ambiguities: const ['缺少提醒时间']), onConfirm: () async {}),
    );

    expect(find.text('缺少提醒时间'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('confirmation cannot be double tapped while pending',
      (tester) async {
    final completer = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      app(
        value: draft(),
        onConfirm: () {
          calls += 1;
          return completer.future;
        },
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pump();
    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();
  });
}
