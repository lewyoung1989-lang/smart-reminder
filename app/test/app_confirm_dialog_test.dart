import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smart_reminder_app/ui/components/app_confirm_dialog.dart';

void main() {
  Widget buildTestHost({
    required Widget Function(BuildContext) builder,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(builder: builder),
      ),
    );
  }

  testWidgets('showMedicationConfirmDialog renders advance medication content and handles cancel',
      (tester) async {
    bool? dialogResult;

    await tester.pumpWidget(
      buildTestHost(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            dialogResult = await showMedicationConfirmDialog(
              context: context,
              medicineTitle: '盐酸普罗帕酮片',
              doseLabel: '150mg/次',
              isAdvance: true,
            );
          },
          child: const Text('打卡'),
        ),
      ),
    );

    await tester.tap(find.text('打卡'));
    await tester.pumpAndSettle();

    expect(find.text('确认提前服药'), findsNWidgets(2)); // title and button label
    expect(find.text('盐酸普罗帕酮片'), findsOneWidget);
    expect(find.text('计划剂量：150mg/次'), findsOneWidget);
    expect(find.textContaining('将精确记录当前时间为实际提前服药时间'), findsOneWidget);
    expect(find.text('稍后再说'), findsOneWidget);

    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();

    expect(dialogResult, isFalse);
    expect(find.text('盐酸普罗帕酮片'), findsNothing);
  });

  testWidgets('showMedicationConfirmDialog returns true on confirm',
      (tester) async {
    bool? dialogResult;

    await tester.pumpWidget(
      buildTestHost(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            dialogResult = await showMedicationConfirmDialog(
              context: context,
              medicineTitle: '阿莫西林胶囊',
              isAdvance: false,
            );
          },
          child: const Text('打卡'),
        ),
      ),
    );

    await tester.tap(find.text('打卡'));
    await tester.pumpAndSettle();

    expect(find.text('确认服药打卡'), findsOneWidget);
    expect(find.text('确认服药'), findsOneWidget);
    expect(find.text('阿莫西林胶囊'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认服药'));
    await tester.pumpAndSettle();

    expect(dialogResult, isTrue);
    expect(find.text('阿莫西林胶囊'), findsNothing);
  });

  testWidgets('showAppConfirmDialog renders destructive style for deletion or pause',
      (tester) async {
    bool? dialogResult;

    await tester.pumpWidget(
      buildTestHost(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            dialogResult = await showAppConfirmDialog(
              context: context,
              icon: LucideIcons.pauseCircle,
              iconColor: const Color(0xFFD97706),
              title: '确认暂停用药计划',
              primaryText: '降压药早间计划',
              infoBannerText: '暂停后系统将停止推送此计划的用药提醒通知。',
              confirmLabel: '确认暂停',
              cancelLabel: '取消',
              confirmColor: const Color(0xFFD97706),
            );
          },
          child: const Text('暂停'),
        ),
      ),
    );

    await tester.tap(find.text('暂停'));
    await tester.pumpAndSettle();

    expect(find.text('确认暂停用药计划'), findsOneWidget);
    expect(find.text('降压药早间计划'), findsOneWidget);
    expect(find.text('暂停后系统将停止推送此计划的用药提醒通知。'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认暂停'));
    await tester.pumpAndSettle();

    expect(dialogResult, isTrue);
  });
}
