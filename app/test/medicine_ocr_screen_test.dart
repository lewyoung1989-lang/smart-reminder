import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';
import 'package:smart_reminder_app/features/home/presentation/app_shell.dart';
import 'package:smart_reminder_app/features/medicine_ocr/domain/ocr_job.dart';
import 'package:smart_reminder_app/features/medicine_ocr/presentation/medicine_ocr_screen.dart';
import 'package:smart_reminder_app/ui/components/app_page_header.dart';
import 'package:smart_reminder_app/ui/components/app_status_banner.dart';

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

  testWidgets(
    'uses a safe iPhone task layout with a persistent primary OCR action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MedicineOcrScreen(
            capture: (_) async => null,
            createJob: ({required frontBytes, expiryBytes}) async =>
                const OcrJob(id: 'job-1', status: 'queued'),
            getJob: (_) async => const OcrJob(id: 'job-1', status: 'queued'),
            confirmJob: (_, __) async {},
          ),
        ),
      );

      expect(find.byType(AppPageHeader), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNotNull);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, '开始识别')).height,
        greaterThanOrEqualTo(44),
      );
    },
  );

  testWidgets('shows camera failures in an accessible inline status banner',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MedicineOcrScreen(
          capture: (_) async => throw Exception('camera denied'),
          createJob: ({required frontBytes, expiryBytes}) async =>
              const OcrJob(id: 'job-1', status: 'queued'),
          getJob: (_) async => const OcrJob(id: 'job-1', status: 'queued'),
          confirmJob: (_, __) async {},
        ),
      ),
    );

    await tester.tap(find.text('拍摄药盒正面'));
    await tester.pump();

    expect(find.byType(AppStatusBanner), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(AppStatusBanner)).label,
      contains('无法打开相机'),
    );
  });

  testWidgets('switches among reminders, cabinet, and profile without OCR tab',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppShell(
          reminders: Text('提醒页面'),
          medicineCabinet: Text('药箱页面'),
          profile: Text('我的页面'),
        ),
      ),
    );

    expect(find.text('提醒页面'), findsOneWidget);
    expect(find.text('药箱'), findsOneWidget);
    expect(find.text('拍照录入'), findsNothing);

    await tester.tap(find.text('药箱'));
    await tester.pump();
    expect(find.text('药箱页面'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump();
    expect(find.text('我的页面'), findsOneWidget);
  });

  testWidgets('returns true to the cabinet route after confirmed inventory',
      (tester) async {
    final result = Completer<bool?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result.complete(
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => MedicineOcrScreen(
                      capture: (kind) async => kind == 'front' ? [1] : null,
                      createJob: ({required frontBytes, expiryBytes}) async =>
                          const OcrJob(id: 'job-1', status: 'queued'),
                      getJob: (_) async => const OcrJob(
                        id: 'job-1',
                        status: 'succeeded',
                        candidate: OcrCandidate(
                          medicineName: '布洛芬胶囊',
                          specification: '0.3g*20粒',
                          batchNumber: 'LOT-1',
                        ),
                      ),
                      confirmJob: (_, __) async {},
                      pollInterval: Duration.zero,
                    ),
                  ),
                ),
              );
            },
            child: const Text('打开录入'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开录入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拍摄药盒正面'));
    await tester.pump();
    await tester.tap(find.text('开始识别'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认入库'));
    await tester.pumpAndSettle();

    expect(await result.future, isTrue);
  });

  testWidgets(
    'requires front photo, shows candidates, and confirms edited values',
    (tester) async {
      final captures = <String, List<int>>{
        'front': [1],
        'expiry': [2],
      };
      var createJobCalls = 0;
      List<int>? submittedFront;
      List<int>? submittedExpiry;
      Map<String, Object?>? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: MedicineOcrScreen(
            capture: (kind) async => captures[kind],
            createJob: ({required frontBytes, expiryBytes}) async {
              createJobCalls += 1;
              submittedFront = frontBytes;
              submittedExpiry = expiryBytes;
              return const OcrJob(id: 'job-1', status: 'queued');
            },
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
      expect(find.byKey(const Key('front-photo-preview')), findsOneWidget);
      expect(find.byKey(const Key('expiry-photo-preview')), findsNothing);
      expect(createJobCalls, 0);

      await tester.tap(find.textContaining('拍摄有效期'));
      await tester.pump();
      expect(find.byKey(const Key('front-photo-preview')), findsOneWidget);
      expect(find.byKey(const Key('expiry-photo-preview')), findsOneWidget);
      expect(createJobCalls, 0);

      await tester.tap(find.text('开始识别'));
      await tester.pumpAndSettle();

      expect(createJobCalls, 1);
      expect(submittedFront, [1]);
      expect(submittedExpiry, [2]);
      expect(find.text('核对识别结果'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('medicine-name')),
        '布洛芬胶囊',
      );
      await tester.tap(find.text('确认入库'));
      await tester.pumpAndSettle();

      expect(confirmed?['medicine_name'], '布洛芬胶囊');
      expect(confirmed?['expiry_date'], '2028-05-31');
      expect(find.byKey(const Key('front-photo-preview')), findsNothing);
      expect(find.byKey(const Key('expiry-photo-preview')), findsNothing);
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

  testWidgets('cancelling retake keeps the existing front preview',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      buildCaptureScreen(
        capture: (_) async {
          calls += 1;
          return calls == 1 ? [1] : null;
        },
      ),
    );

    await tester.tap(find.text('拍摄药盒正面'));
    await tester.pump();
    expect(find.byKey(const Key('front-photo-preview')), findsOneWidget);

    await tester.tap(find.byTooltip('重新拍摄药盒正面'));
    await tester.pump();
    expect(find.byKey(const Key('front-photo-preview')), findsOneWidget);
  });

  testWidgets('upload failure keeps previews and allows retry', (tester) async {
    var createJobCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MedicineOcrScreen(
          capture: (kind) async => kind == 'front' ? [1] : [2],
          createJob: ({required frontBytes, expiryBytes}) async {
            createJobCalls += 1;
            if (createJobCalls == 1) {
              throw Exception('network unavailable');
            }
            return const OcrJob(id: 'job-1', status: 'queued');
          },
          getJob: (_) async => const OcrJob(
            id: 'job-1',
            status: 'succeeded',
            candidate: OcrCandidate(
              medicineName: '测试药品',
              specification: '',
              batchNumber: '',
            ),
          ),
          confirmJob: (_, __) async {},
          pollInterval: Duration.zero,
        ),
      ),
    );

    await tester.tap(find.text('拍摄药盒正面'));
    await tester.pump();
    await tester.tap(find.textContaining('拍摄有效期'));
    await tester.pump();
    await tester.tap(find.text('开始识别'));
    await tester.pump();

    expect(find.text('上传失败，请检查网络后重试'), findsOneWidget);
    expect(find.byKey(const Key('front-photo-preview')), findsOneWidget);
    expect(find.byKey(const Key('expiry-photo-preview')), findsOneWidget);
    expect(createJobCalls, 1);

    await tester.tap(find.text('开始识别'));
    await tester.pumpAndSettle();
    expect(createJobCalls, 2);
    expect(find.text('核对识别结果'), findsOneWidget);
  });
}
