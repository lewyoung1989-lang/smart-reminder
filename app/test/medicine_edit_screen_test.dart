import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/data/medicine_cabinet_api.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/medicine_models.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/presentation/medicine_edit_screen.dart';

const summary = MedicineSummary(
  id: 'medicine',
  name: '测试药品',
  specification: '10mg',
  manufacturer: '测试公司',
  totalQuantity: 2,
  nearestExpiry: null,
  status: MedicineStatus.unknown,
);
const batch = MedicineBatch(
  id: 'batch',
  batchNumber: '',
  specification: '10mg',
  productionDate: null,
  expiresOn: null,
  quantity: 2,
  sourceLabel: '个人药箱',
  version: 7,
  packageUnit: '盒',
  unitsPerPackage: 20,
  unitName: '片',
  looseUnits: 5,
);

void main() {
  testWidgets(
      'saves zero full packages and decimal loose inventory with progress',
      (tester) async {
    final pending = Completer<void>();
    MedicineBatchEdit? captured;
    await tester.pumpWidget(MaterialApp(
        home: MedicineEditScreen(
      summary: summary,
      batch: batch,
      onSave: (original, changes) {
        expect(original.version, 7);
        captured = changes;
        return pending.future;
      },
    )));
    await tester.enterText(
        find.byKey(const Key('medicine-edit-quantity')), '0');
    final loose = find.byKey(const Key('medicine-edit-loose'));
    await tester.ensureVisible(loose);
    await tester.enterText(loose, '3.5');
    await tester.tap(find.text('收起键盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await tester.pump();
    expect(find.text('正在保存…'), findsOneWidget);
    expect(captured!.quantity, 0);
    expect(captured!.looseUnits, 3.5);
    expect(captured!.medicineName, summary.name);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('rejects negative inventory without sending an update',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: MedicineEditScreen(
      summary: summary,
      batch: batch,
      onSave: (_, __) async {
        calls++;
      },
    )));
    await tester.enterText(
        find.byKey(const Key('medicine-edit-quantity')), '-1');
    await tester.tap(find.text('收起键盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('请输入 0～9999 的整数'), findsOneWidget);
  });

  testWidgets('keeps input on network failure and prevents stale overwrite',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: MedicineEditScreen(
      summary: summary,
      batch: batch,
      onSave: (_, __) async {
        calls++;
        if (calls == 1) throw StateError('network');
        throw const MedicineCabinetApiException(409, '{}');
      },
    )));
    await tester.enterText(
        find.byKey(const Key('medicine-edit-name')), '修改后的药');
    await tester.tap(find.text('收起键盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已填写内容会保留'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('medicine-edit-name')))
            .controller!
            .text,
        '修改后的药');
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(find.text('返回药箱刷新'), findsOneWidget);
    expect(find.textContaining('库存已被更新'), findsOneWidget);
    expect(calls, 2);
  });
}
