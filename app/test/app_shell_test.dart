import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/shell/app_shell.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';
import 'package:smart_reminder_app/features/auth/domain/auth_models.dart';
import 'package:smart_reminder_app/features/quick_create/domain/quick_create_draft.dart';
import 'package:smart_reminder_app/features/reminder_drafts/application/reminder_creation_service.dart';
import 'package:smart_reminder_app/features/reminder_drafts/domain/reminder_draft.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/data/medicine_repository.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/medicine_models.dart';
import 'package:smart_reminder_app/features/plans/data/plan_repository.dart';
import 'package:smart_reminder_app/features/today/data/action_center_api.dart';
import 'package:smart_reminder_app/features/today/data/today_repository.dart';
import 'package:smart_reminder_app/features/today/domain/today_models.dart';
import 'package:smart_reminder_app/platform/notifications/reminder_notification_scheduler.dart';

void main() {
  testWidgets('uses redesigned destinations and opens account settings',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: AppShell(
          todayRepository: const UnavailableTodayRepository(),
          planRepository: const UnavailablePlanRepository(),
          medicineRepository: _UnavailableMedicineRepository(),
          user: const AuthUser(
            id: 'user-1',
            phoneMasked: '138****8000',
            phoneVerified: true,
          ),
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onChangePassword: (_, __, ___) async {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天'), findsWidgets);
    expect(find.text('周期'), findsOneWidget);
    expect(find.text('药箱'), findsOneWidget);
    expect(find.text('提醒'), findsNothing);

    await tester.tap(find.byTooltip('打开设置'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('138****8000'), findsOneWidget);
    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('keeps the authenticated reminder manager reachable',
      (tester) async {
    var managerCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          todayRepository: const UnavailableTodayRepository(),
          planRepository: const UnavailablePlanRepository(),
          medicineRepository: _UnavailableMedicineRepository(),
          user: const AuthUser(
            id: 'user-1',
            phoneMasked: '138****8000',
            phoneVerified: true,
          ),
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onChangePassword: (_, __, ___) async {},
          onLogout: () async {},
          onOpenReminderManager: () => managerCalls += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('管理提醒'), findsOneWidget);
    await tester.tap(find.byTooltip('管理提醒'));
    expect(managerCalls, 1);
  });

  testWidgets('surfaces permanent camera denial with a settings recovery',
      (tester) async {
    var settingsCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          todayRepository: const UnavailableTodayRepository(),
          planRepository: const UnavailablePlanRepository(),
          medicineRepository: _UnavailableMedicineRepository(),
          user: const AuthUser(
            id: 'user-1',
            phoneMasked: '138****8000',
            phoneVerified: true,
          ),
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onChangePassword: (_, __, ___) async {},
          onLogout: () async {},
          captureAvailability: MedicineCaptureAvailability.permanentlyDenied,
          onOpenSystemSettings: () => settingsCalls += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('药箱'));
    await tester.pumpAndSettle();

    expect(find.text('需要相机权限才能拍照录入'), findsOneWidget);
    await tester.tap(find.text('打开设置'));
    expect(settingsCalls, 1);
  });

  testWidgets('uses a navigation rail from 600dp', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          todayRepository: const UnavailableTodayRepository(),
          planRepository: const UnavailablePlanRepository(),
          medicineRepository: _UnavailableMedicineRepository(),
          user: const AuthUser(
            id: 'user-1',
            phoneMasked: '138****8000',
            phoneVerified: true,
          ),
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onChangePassword: (_, __, ___) async {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('hides quick create on periodic plans only', (tester) async {
    final creationService = ReminderCreationService(
      confirmDraft: (_) async => 'reminder-1',
      notificationScheduler: _ThrowingNotificationScheduler(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          todayRepository: const UnavailableTodayRepository(),
          planRepository: const UnavailablePlanRepository(),
          medicineRepository: _UnavailableMedicineRepository(),
          user: const AuthUser(
            id: 'user-1',
            phoneMasked: '138****8000',
            phoneVerified: true,
          ),
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onChangePassword: (_, __, ___) async {},
          onLogout: () async {},
          createDraft: (_) async => QuickCreateDraft.reminder(
            reminder: ReminderDraft(
              id: 'draft-1',
              title: '喝水',
              scheduledAt: DateTime(2026, 8, 8, 18, 40),
              timezone: 'Asia/Shanghai',
              severity: ReminderSeverity.notification,
              weatherMessage: null,
              ambiguities: const [],
            ),
          ),
          reminderCreationService: creationService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick-create-bar')), findsOneWidget);

    await tester.tap(find.text('周期'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick-create-bar')), findsNothing);

    await tester.tap(find.text('药箱'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick-create-bar')), findsOneWidget);
  });

  testWidgets('logout from settings returns to the shell root', (tester) async {
    var logoutCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          todayRepository: const UnavailableTodayRepository(),
          planRepository: const UnavailablePlanRepository(),
          medicineRepository: _UnavailableMedicineRepository(),
          user: const AuthUser(
            id: 'user-1',
            phoneMasked: '138****8000',
            phoneVerified: true,
          ),
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onChangePassword: (_, __, ___) async {},
          onLogout: () async => logoutCalls += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('打开设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认退出'));
    await tester.pumpAndSettle();

    expect(logoutCalls, 1);
    expect(find.text('设置'), findsNothing);
  });

  testWidgets(
      'quick create exits the draft after server creation when notification scheduling fails',
      (tester) async {
    final draft = QuickCreateDraft.reminder(
      reminder: ReminderDraft(
        id: 'draft-1',
        title: '喝水',
        scheduledAt: DateTime(2026, 8, 8, 18, 40),
        timezone: 'Asia/Shanghai',
        severity: ReminderSeverity.notification,
        weatherMessage: null,
        ambiguities: const [],
      ),
    );
    final creationService = ReminderCreationService(
      confirmDraft: (_) async => 'reminder-1',
      notificationScheduler: _ThrowingNotificationScheduler(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          todayRepository: const UnavailableTodayRepository(),
          planRepository: const UnavailablePlanRepository(),
          medicineRepository: _UnavailableMedicineRepository(),
          user: const AuthUser(
            id: 'user-1',
            phoneMasked: '138****8000',
            phoneVerified: true,
          ),
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onChangePassword: (_, __, ___) async {},
          onLogout: () async {},
          createDraft: (_) async => draft,
          reminderCreationService: creationService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quick-create-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quick-create-input')),
      '1分钟后提醒我喝水',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(find.text('确认计划'), findsNothing);
    expect(find.text('提醒已创建，但手机通知未安排'), findsOneWidget);
  });

  testWidgets('editing a workflow draft re-parses the expression in place',
      (tester) async {
    QuickCreateDraft buildDraft() => QuickCreateDraft.workflow(
          workflow: WorkflowDraft(
            id: 'workflow-draft-1',
            title: '提醒草稿',
            templateHint: 'medication_cycle',
            slots: const {
              'medicine_name': '降压药',
              'frequency': 'daily',
              'time_of_day': '09:00',
            },
            ambiguities: const ['请补充药品剂量和服药周期'],
            policyDecision: 'needs_clarification',
            riskLevel: 'R2',
            policyQuestion: null,
          ),
        );
    final createdTexts = <String>[];
    final creationService = ReminderCreationService(
      confirmDraft: (_) async => 'reminder-1',
      notificationScheduler: _ThrowingNotificationScheduler(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          todayRepository: const UnavailableTodayRepository(),
          planRepository: const UnavailablePlanRepository(),
          medicineRepository: _UnavailableMedicineRepository(),
          user: const AuthUser(
            id: 'user-1',
            phoneMasked: '138****8000',
            phoneVerified: true,
          ),
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onChangePassword: (_, __, ___) async {},
          onLogout: () async {},
          createDraft: (text) async {
            createdTexts.add(text);
            return buildDraft();
          },
          reminderCreationService: creationService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quick-create-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quick-create-input')),
      '以后每天9点我吃药',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    expect(find.text('确认计划'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '修改'));
    await tester.pumpAndSettle();

    final input = find.byKey(const Key('workflow-reparse-input'));
    expect(input, findsOneWidget);
    expect(
      tester.widget<TextField>(input).controller!.text,
      '以后每天9点我吃药',
    );

    await tester.enterText(input, '以后每天9点我吃降压药1片');
    await tester.pump();
    await tester.tap(find.byKey(const Key('workflow-reparse-submit')));
    await tester.pumpAndSettle();

    expect(createdTexts, ['以后每天9点我吃药', '以后每天9点我吃降压药1片']);
    expect(find.text('确认计划'), findsOneWidget);
    expect(find.text('以后每天9点我吃降压药1片'), findsOneWidget);
    expect(find.byKey(const Key('quick-create-input')), findsNothing);
  });

  testWidgets('dispatches today medication decisions to verified actions',
      (tester) async {
    final todayRepository = _SequenceTodayRepository([
      TodaySnapshot(
        decisions: <AttentionItem>[
          AttentionItem(
            id: 'attention-1',
            title: '服用布洛芬',
            reason: '已到服药时间，请确认是否已服用',
            dueAt: DateTime(2026, 8, 8, 8),
            kind: AttentionKind.confirmation,
            actionLabel: '记录',
            actionTarget: const ActionTarget(
              resource: 'medication_occurrence',
              id: 'occurrence-1',
            ),
          ),
        ],
        timeline: const <TimelineItem>[],
      ),
      TodaySnapshot(decisions: const [], timeline: const []),
    ]);
    final actions = _RecordingActionCenterActions();
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          todayRepository: todayRepository,
          planRepository: const UnavailablePlanRepository(),
          medicineRepository: _UnavailableMedicineRepository(),
          user: const AuthUser(
            id: 'user-1',
            phoneMasked: '138****8000',
            phoneVerified: true,
          ),
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onChangePassword: (_, __, ___) async {},
          onLogout: () async {},
          actionCenterActions: actions,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '记录'));
    await tester.pumpAndSettle();

    expect(actions.takenOccurrences, ['occurrence-1']);
    expect(todayRepository.calls, 2);
    expect(find.text('服用布洛芬'), findsNothing);
    expect(find.text('已记录服药'), findsOneWidget);
  });
}

class _ThrowingNotificationScheduler implements ReminderNotificationScheduler {
  @override
  Future<void> schedule({
    required String reminderId,
    required ReminderDraft draft,
  }) async {
    throw StateError('notification bridge unavailable');
  }

  @override
  Future<void> cancel({required String reminderId}) async {}
}

class _UnavailableMedicineRepository implements MedicineRepository {
  @override
  Future<MedicineCollection> load() => Future.value(
        MedicineCollection(items: const [], loadedBatchCount: 0),
      );

  @override
  Future<MedicineDetail> getById(String id) =>
      Future.error(StateError('No medicine available'));
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

class _RecordingActionCenterActions implements ActionCenterActions {
  final takenOccurrences = <String>[];
  final handledBatches = <String>[];

  @override
  Future<void> markMedicationTaken(String occurrenceId) async {
    takenOccurrences.add(occurrenceId);
  }

  @override
  Future<void> handleExpiryBatch(String batchId) async {
    handledBatches.add(batchId);
  }
}
