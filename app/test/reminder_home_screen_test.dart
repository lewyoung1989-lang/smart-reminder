import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/reminders/domain/reminder.dart';
import 'package:smart_reminder_app/features/reminders/data/reminder_api.dart';
import 'package:smart_reminder_app/features/reminders/presentation/reminder_home_screen.dart';
import 'package:smart_reminder_app/platform/notifications/reminder_notification_scheduler.dart';

Reminder reminder(
  String id,
  String title,
  ReminderStatus status,
) =>
    Reminder(
      id: id,
      title: title,
      timezone: 'Asia/Shanghai',
      scheduledAt: DateTime(2026, 8, 5, 12, 30),
      severity: ReminderSeverity.notification,
      status: status,
      cancelledAt:
          status == ReminderStatus.cancelled ? DateTime(2026, 8, 5, 12) : null,
    );

class RecordingScheduler implements ReminderNotificationScheduler {
  RecordingScheduler({this.cancelError, this.events});

  final Object? cancelError;
  final List<String>? events;
  final cancelled = <String>[];

  @override
  Future<void> cancel({required String reminderId}) async {
    events?.add('local');
    cancelled.add(reminderId);
    if (cancelError case final error?) throw error;
  }

  @override
  Future<void> schedule({required reminderId, required draft}) async {}
}

Widget buildHome({
  required Future<ReminderPage> Function({
    required ReminderStatus status,
    Uri? pageUrl,
  }) listReminders,
  Future<Reminder> Function(String id)? cancelReminder,
  ReminderNotificationScheduler? scheduler,
  WidgetBuilder? createReminder,
}) =>
    MaterialApp(
      home: ReminderHomeScreen(
        listReminders: listReminders,
        cancelReminder: cancelReminder ??
            (id) async => reminder(id, '已取消', ReminderStatus.cancelled),
        notificationScheduler: scheduler,
        createReminder: createReminder ?? (_) => const SizedBox.shrink(),
      ),
    );

void main() {
  testWidgets('loads pending first and keeps three lifecycle tabs',
      (tester) async {
    final requested = <ReminderStatus>[];
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) async {
          requested.add(status);
          return ReminderPage(
            reminders: [reminder(status.name, status.name, status)],
            nextPage: null,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, [ReminderStatus.pending]);
    expect(find.text('待提醒'), findsOneWidget);
    expect(find.text('已过期'), findsOneWidget);
    expect(find.text('已取消'), findsOneWidget);
    expect(find.text('pending'), findsOneWidget);

    await tester.tap(find.text('已过期'));
    await tester.pumpAndSettle();
    expect(requested, [ReminderStatus.pending, ReminderStatus.expired]);
    expect(find.text('expired'), findsOneWidget);

    tester
        .widget<TabBar>(find.byType(TabBar))
        .controller!
        .animateTo(2, duration: Duration.zero);
    await tester.pumpAndSettle();
    expect(requested, [
      ReminderStatus.pending,
      ReminderStatus.expired,
      ReminderStatus.cancelled,
    ]);
    expect(find.text('cancelled'), findsOneWidget);
  });

  testWidgets('shows first page error and retries without leaving the tab',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) async {
          calls += 1;
          if (calls == 1) throw Exception('offline');
          return ReminderPage(
            reminders: [reminder('1', '重试成功', status)],
            nextPage: null,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('提醒加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('重试成功'), findsOneWidget);
  });

  testWidgets('creation result returns to pending and refreshes',
      (tester) async {
    var listCalls = 0;
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) async {
          listCalls += 1;
          return ReminderPage(
            reminders: listCalls == 1
                ? []
                : [reminder('new', '新提醒', ReminderStatus.pending)],
            nextPage: null,
          );
        },
        createReminder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => Navigator.of(context).pop(
              const ReminderCreationResult(
                reminderId: 'new',
                notificationScheduled: true,
              ),
            ),
            child: const Text('完成创建'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-reminder')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成创建'));
    await tester.pumpAndSettle();

    expect(listCalls, 2);
    expect(find.text('新提醒'), findsOneWidget);
    expect(find.text('提醒已创建，通知已安排'), findsOneWidget);
  });

  testWidgets('cancels on server before cancelling the local notification',
      (tester) async {
    var active = true;
    final events = <String>[];
    final scheduler = RecordingScheduler(events: events);
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) async => ReminderPage(
          reminders: status == ReminderStatus.pending && active
              ? [reminder('one', '喝水', ReminderStatus.pending)]
              : [],
          nextPage: null,
        ),
        cancelReminder: (id) async {
          events.add('server');
          active = false;
          return reminder(id, '喝水', ReminderStatus.cancelled);
        },
        scheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cancel-one')));
    await tester.pumpAndSettle();
    expect(find.text('取消后不会再通知'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确认取消'));
    await tester.pumpAndSettle();

    expect(events, ['server', 'local']);
    expect(find.text('喝水'), findsNothing);
    expect(find.text('提醒已取消'), findsOneWidget);
  });

  testWidgets('local cancellation failure keeps server cancellation',
      (tester) async {
    var active = true;
    final scheduler = RecordingScheduler(
      cancelError: const NotificationCancellationFailed(),
    );
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) async => ReminderPage(
          reminders: status == ReminderStatus.pending && active
              ? [reminder('one', '吃药', ReminderStatus.pending)]
              : [],
          nextPage: null,
        ),
        cancelReminder: (id) async {
          active = false;
          return reminder(id, '吃药', ReminderStatus.cancelled);
        },
        scheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cancel-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认取消'));
    await tester.pumpAndSettle();

    expect(find.text('吃药'), findsNothing);
    expect(find.text('提醒已取消，但手机通知可能仍存在'), findsOneWidget);
  });

  testWidgets('server cancellation removes the row even if refresh fails',
      (tester) async {
    var listCalls = 0;
    final scheduler = RecordingScheduler();
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) async {
          listCalls += 1;
          if (listCalls > 1) throw Exception('refresh failed');
          return ReminderPage(
            reminders: [reminder('one', '散步', ReminderStatus.pending)],
            nextPage: null,
          );
        },
        cancelReminder: (id) async =>
            reminder(id, '散步', ReminderStatus.cancelled),
        scheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cancel-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认取消'));
    await tester.pumpAndSettle();

    expect(find.text('散步'), findsNothing);
    expect(find.text('提醒已取消'), findsOneWidget);
  });

  testWidgets('older refresh response cannot overwrite a newer response',
      (tester) async {
    final older = Completer<ReminderPage>();
    final newer = Completer<ReminderPage>();
    var calls = 0;
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) {
          calls += 1;
          if (calls == 1) {
            return Future.value(
              ReminderPage(
                reminders: [reminder('initial', '初始提醒', status)],
                nextPage: null,
              ),
            );
          }
          return calls == 2 ? older.future : newer.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final olderRequest = refresh.onRefresh();
    await tester.pump();
    final newerRequest = refresh.onRefresh();
    newer.complete(
      ReminderPage(
        reminders: [reminder('new', '最新提醒', ReminderStatus.pending)],
        nextPage: null,
      ),
    );
    await newerRequest;
    await tester.pump();
    older.complete(
      ReminderPage(
        reminders: [reminder('old', '旧响应', ReminderStatus.pending)],
        nextPage: null,
      ),
    );
    await olderRequest;
    await tester.pump();

    expect(find.text('最新提醒'), findsOneWidget);
    expect(find.text('旧响应'), findsNothing);
  });

  testWidgets('scrolling near the end loads the next cursor page',
      (tester) async {
    final pageUrls = <Uri?>[];
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) async {
          pageUrls.add(pageUrl);
          if (pageUrl == null) {
            return ReminderPage(
              reminders: [
                for (var index = 0; index < 14; index += 1)
                  reminder('$index', '提醒 $index', status),
              ],
              nextPage: Uri.parse(
                'https://api.invalid/api/v1/reminders?cursor=next&status=pending',
              ),
            );
          }
          return ReminderPage(
            reminders: [reminder('last', '最后一条', status)],
            nextPage: null,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('reminder-list-pending')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(pageUrls, hasLength(2));
    expect(pageUrls.last?.queryParameters['cursor'], 'next');
  });

  testWidgets('refresh invalidates an in-flight cursor loading state',
      (tester) async {
    final cursor = Completer<ReminderPage>();
    var firstPageCalls = 0;
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) {
          if (pageUrl != null) return cursor.future;
          firstPageCalls += 1;
          return Future.value(
            ReminderPage(
              reminders: firstPageCalls == 1
                  ? [
                      for (var index = 0; index < 14; index += 1)
                        reminder('$index', '旧列表 $index', status),
                    ]
                  : [reminder('fresh', '刷新结果', status)],
              nextPage: firstPageCalls == 1
                  ? Uri.parse(
                      'https://api.invalid/api/v1/reminders?cursor=next&status=pending',
                    )
                  : null,
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('reminder-list-pending')),
      const Offset(0, -900),
    );
    await tester.pump();

    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    await refresh.onRefresh();
    cursor.complete(
      ReminderPage(
        reminders: [
          reminder('stale', '旧分页结果', ReminderStatus.pending),
        ],
        nextPage: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('刷新结果'), findsOneWidget);
    expect(find.text('旧分页结果'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('cancellation restarts an in-flight cancelled tab request',
      (tester) async {
    final oldCancelledRequest = Completer<ReminderPage>();
    var active = true;
    var cancelledCalls = 0;
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) {
          if (status == ReminderStatus.cancelled) {
            cancelledCalls += 1;
            if (cancelledCalls == 1) return oldCancelledRequest.future;
            return Future.value(
              ReminderPage(
                reminders: [
                  reminder('one', '已取消记录', ReminderStatus.cancelled),
                ],
                nextPage: null,
              ),
            );
          }
          return Future.value(
            ReminderPage(
              reminders: status == ReminderStatus.pending && active
                  ? [reminder('one', '待取消记录', ReminderStatus.pending)]
                  : [],
              nextPage: null,
            ),
          );
        },
        cancelReminder: (id) async {
          active = false;
          return reminder(id, '待取消记录', ReminderStatus.cancelled);
        },
        scheduler: RecordingScheduler(),
      ),
    );
    await tester.pumpAndSettle();

    final tabController =
        tester.widget<TabBar>(find.byType(TabBar)).controller!;
    tabController.animateTo(2, duration: Duration.zero);
    tabController.animateTo(0, duration: Duration.zero);
    expect(cancelledCalls, 1);
    tester.widget<IconButton>(find.byKey(const Key('cancel-one'))).onPressed!();
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认取消'));
    await tester.pump(const Duration(milliseconds: 400));
    oldCancelledRequest.complete(
      const ReminderPage(reminders: [], nextPage: null),
    );
    await tester.pump(const Duration(milliseconds: 100));

    tester
        .widget<TabBar>(find.byType(TabBar))
        .controller!
        .animateTo(2, duration: Duration.zero);
    await tester.pumpAndSettle();

    expect(cancelledCalls, 2);
    expect(find.text('已取消记录'), findsOneWidget);
  });

  testWidgets('expired cancellation conflict refreshes without local cancel',
      (tester) async {
    var pendingCalls = 0;
    final scheduler = RecordingScheduler();
    await tester.pumpWidget(
      buildHome(
        listReminders: ({required status, pageUrl}) async {
          if (status == ReminderStatus.pending) pendingCalls += 1;
          return ReminderPage(
            reminders: status == ReminderStatus.pending && pendingCalls == 1
                ? [reminder('one', '刚刚过期', ReminderStatus.pending)]
                : [],
            nextPage: null,
          );
        },
        cancelReminder: (_) async => throw ReminderApiException(
          409,
          jsonEncode({
            'code': 'reminder_expired',
            'detail': '提醒时间已过，不能取消',
          }),
        ),
        scheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cancel-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认取消'));
    await tester.pumpAndSettle();

    expect(pendingCalls, 2);
    expect(scheduler.cancelled, isEmpty);
    expect(find.text('刚刚过期'), findsNothing);
    expect(find.text('提醒时间已过，不能取消'), findsOneWidget);
    expect(find.text('取消失败，请检查网络后重试'), findsNothing);
  });
}
