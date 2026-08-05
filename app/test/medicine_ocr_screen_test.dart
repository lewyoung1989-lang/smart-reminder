import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/home/presentation/app_shell.dart';
import 'package:smart_reminder_app/features/medicine_ocr/domain/ocr_job.dart';
import 'package:smart_reminder_app/features/medicine_ocr/presentation/medicine_ocr_screen.dart';

void main() {
  Widget buildCaptureScreen({
    required Future<List<int>?> Function(String kind) capture,
  }) =>
      MaterialApp(
        home: MedicineOcrScreen(
          capture: capture,
          createJob: ({required frontBytes, expiryBytes}) async =>
              const OcrJob(id: 'job-1', status: 'queued'),
          getJob: (_) async => const OcrJob(id: 'job-1', status: 'queued'),
          confirmJob: (_, __) async {},
        ),
      );

  testWidgets('switches among reminders, cabinet, and medicine entry',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppShell(
          reminders: Text('提醒页面'),
          medicineCabinet: Text('药箱页面'),
          medicineOcr: Text('拍照页面'),
        ),
      ),
    );

    expect(find.text('提醒页面'), findsOneWidget);
    expect(find.text('药箱'), findsOneWidget);
    expect(find.text('拍照录入'), findsOneWidget);

    await tester.tap(find.text('药箱'));
    await tester.pump();
    expect(find.text('药箱页面'), findsOneWidget);

    await tester.tap(find.text('拍照录入'));
    await tester.pump();
    expect(find.text('拍照页面'), findsOneWidget);
  });

  testWidgets(
    'requires front photo, shows candidates, and confirms edited values',
    (tester) async {
      final captures = <String, List<int>>{
        'front': [1],
        'expiry': [2],
      };
      Map<String, Object?>? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: MedicineOcrScreen(
            capture: (kind) async => captures[kind],
            createJob: ({required frontBytes, expiryBytes}) async =>
                const OcrJob(id: 'job-1', status: 'queued'),
            getJob: (_) async => OcrJob(
              id: 'job-1',
              status: 'succeeded',
              candidate: OcrCandidate(
                medicineName: '布洛芬缓释胶囊',
                specification: '0.3g*20粒',
                batchNumber: '',
                expiryDate: DateTime(2028, 5, 31),
              ),
            ),
            confirmJob: (_, fields) async {
              confirmed = fields;
            },
            pollInterval: Duration.zero,
          ),
        ),
      );

      final startButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '开始识别'),
      );
      expect(startButton.onPressed, isNull);

      await tester.tap(find.text('拍摄药盒正面'));
      await tester.pump();
      await tester.tap(find.text('拍摄有效期'));
      await tester.pump();
      await tester.tap(find.text('开始识别'));
      await tester.pumpAndSettle();

      expect(find.text('核对识别结果'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('medicine-name')),
        '布洛芬胶囊',
      );
      await tester.tap(find.text('确认入库'));
      await tester.pumpAndSettle();

      expect(confirmed?['medicine_name'], '布洛芬胶囊');
      expect(confirmed?['expiry_date'], '2028-05-31');
    },
  );

  testWidgets('camera failure stays on capture screen with guidance',
      (tester) async {
    await tester.pumpWidget(
      buildCaptureScreen(
        capture: (_) async => throw Exception('camera denied'),
      ),
    );

    await tester.tap(find.text('拍摄药盒正面'));
    await tester.pump();

    expect(find.text('无法打开相机，请检查相机权限后重试'), findsOneWidget);
    expect(find.text('拍摄药盒正面'), findsOneWidget);
  });

  testWidgets('cancelling camera does not show an error', (tester) async {
    await tester.pumpWidget(
      buildCaptureScreen(capture: (_) async => null),
    );

    await tester.tap(find.text('拍摄药盒正面'));
    await tester.pump();

    expect(find.text('无法打开相机，请检查相机权限后重试'), findsNothing);
    expect(find.text('拍摄药盒正面'), findsOneWidget);
  });

  testWidgets('camera cancellation clears a previous capture error',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      buildCaptureScreen(
        capture: (_) async {
          calls += 1;
          if (calls == 1) throw Exception('camera unavailable');
          return null;
        },
      ),
    );

    await tester.tap(find.text('拍摄药盒正面'));
    await tester.pump();
    expect(find.text('无法打开相机，请检查相机权限后重试'), findsOneWidget);

    await tester.tap(find.text('拍摄药盒正面'));
    await tester.pump();
    expect(find.text('无法打开相机，请检查相机权限后重试'), findsNothing);
  });
}
