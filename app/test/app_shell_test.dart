import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/shell/app_shell.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';
import 'package:smart_reminder_app/features/auth/domain/auth_models.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/data/medicine_repository.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/medicine_models.dart';
import 'package:smart_reminder_app/features/plans/data/plan_repository.dart';
import 'package:smart_reminder_app/features/today/data/action_center_api.dart';
import 'package:smart_reminder_app/features/today/data/today_repository.dart';
import 'package:smart_reminder_app/features/today/domain/today_models.dart';

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
    expect(find.text('计划'), findsOneWidget);
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
