import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/domain/inventory_batch.dart';
import 'package:smart_reminder_app/features/medicine_cabinet/presentation/medicine_cabinet_screen.dart';

InventoryBatch batch({
  required String id,
  required String name,
  InventoryExpiryStatus status = InventoryExpiryStatus.valid,
  DateTime? expiryDate,
  int? daysUntilExpiry = 365,
}) =>
    InventoryBatch(
      id: id,
      medicineId: 'medicine-$id',
      medicineName: name,
      specification: '0.3g*20粒',
      batchNumber: 'LOT-$id',
      productionDate: DateTime(2026, 1, 1),
      expiryDate: expiryDate,
      quantity: 2,
      expiryStatus: status,
      daysUntilExpiry: daysUntilExpiry,
    );

Widget testApp(
  Future<InventoryBatchPage> Function({String query, Uri? pageUrl}) loader,
) =>
    MaterialApp(home: MedicineCabinetScreen(listBatches: loader));

void main() {
  testWidgets('shows loading and then an empty cabinet', (tester) async {
    final response = Completer<InventoryBatchPage>();
    await tester.pumpWidget(
      testApp(({String query = '', Uri? pageUrl}) => response.future),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    response.complete(
      const InventoryBatchPage(batches: [], nextPage: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('药箱里还没有药品'), findsOneWidget);
    expect(find.text('可从“拍照录入”添加药品'), findsOneWidget);
  });

  testWidgets('retries after a loading error', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      testApp(({String query = '', Uri? pageUrl}) async {
        calls += 1;
        if (calls == 1) {
          throw Exception('network');
        }
        return InventoryBatchPage(
          batches: [batch(id: '1', name: '布洛芬胶囊')],
          nextPage: null,
        );
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('药箱加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('布洛芬胶囊'), findsOneWidget);
  });

  testWidgets('searches, clears, and refreshes the cabinet', (tester) async {
    final queries = <String>[];
    await tester.pumpWidget(
      testApp(({String query = '', Uri? pageUrl}) async {
        queries.add(query);
        return InventoryBatchPage(
          batches: [batch(id: '${queries.length}', name: '搜索结果')],
          nextPage: null,
        );
      }),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('medicine-search')),
      '  布洛芬  ',
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(queries, ['', '布洛芬']);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(queries, ['', '布洛芬', '']);

    await tester.drag(
      find.byKey(const Key('medicine-cabinet-list')),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(queries, ['', '布洛芬', '', '']);
  });

  testWidgets('shows expiry states and loads the next cursor page',
      (tester) async {
    final pageRequests = <Uri?>[];
    await tester.pumpWidget(
      testApp(({String query = '', Uri? pageUrl}) async {
        pageRequests.add(pageUrl);
        if (pageUrl != null) {
          return InventoryBatchPage(
            batches: [batch(id: 'next', name: '下一页药品')],
            nextPage: null,
          );
        }
        return InventoryBatchPage(
          batches: [
            batch(
              id: 'expired',
              name: '过期药品',
              status: InventoryExpiryStatus.expired,
              expiryDate: DateTime(2026, 7, 1),
              daysUntilExpiry: -35,
            ),
            batch(
              id: 'soon',
              name: '临期药品',
              status: InventoryExpiryStatus.expiringSoon,
              expiryDate: DateTime(2026, 8, 20),
              daysUntilExpiry: 15,
            ),
            batch(
              id: 'valid',
              name: '有效药品',
              expiryDate: DateTime(2027, 8, 5),
            ),
            batch(
              id: 'unknown',
              name: '未知药品',
              status: InventoryExpiryStatus.unknown,
              expiryDate: null,
              daysUntilExpiry: null,
            ),
          ],
          nextPage: Uri.parse(
            'https://api.invalid/api/v1/inventory-batches?cursor=next',
          ),
        );
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('已过期 35 天'), findsOneWidget);
    expect(find.text('15 天后过期'), findsOneWidget);
    expect(find.text('有效'), findsOneWidget);
    expect(find.text('未录入有效期'), findsOneWidget);
    final expiredChip = tester.widget<Chip>(
      find.ancestor(
        of: find.text('已过期 35 天'),
        matching: find.byType(Chip),
      ),
    );
    final validChip = tester.widget<Chip>(
      find.ancestor(
        of: find.text('有效'),
        matching: find.byType(Chip),
      ),
    );
    expect(expiredChip.backgroundColor, isNot(validChip.backgroundColor));

    await tester.drag(
      find.byKey(const Key('medicine-cabinet-list')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();

    expect(pageRequests.length, 2);
    expect(pageRequests.last?.queryParameters['cursor'], 'next');
    expect(find.text('下一页药品'), findsOneWidget);
  });

  testWidgets('ignores an old cursor response after a new search',
      (tester) async {
    final oldNextPage = Completer<InventoryBatchPage>();
    var cursorRequests = 0;
    await tester.pumpWidget(
      testApp(({String query = '', Uri? pageUrl}) async {
        if (pageUrl != null) {
          cursorRequests += 1;
          return oldNextPage.future;
        }
        if (query == '新搜索') {
          return InventoryBatchPage(
            batches: [batch(id: 'new', name: '新结果')],
            nextPage: null,
          );
        }
        return InventoryBatchPage(
          batches: List.generate(
            8,
            (index) => batch(id: 'old-$index', name: '旧结果 $index'),
          ),
          nextPage: Uri.parse(
            'https://api.invalid/api/v1/inventory-batches?cursor=old',
          ),
        );
      }),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('medicine-cabinet-list')),
      const Offset(0, -700),
    );
    await tester.pump();
    expect(cursorRequests, 1);
    await tester.enterText(
      find.byKey(const Key('medicine-search')),
      '新搜索',
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump();
    expect(find.text('新结果'), findsOneWidget);

    oldNextPage.complete(
      InventoryBatchPage(
        batches: [batch(id: 'stale', name: '旧分页结果')],
        nextPage: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧分页结果'), findsNothing);
  });

  testWidgets('retries a failed cursor page without hiding current items',
      (tester) async {
    var cursorRequests = 0;
    await tester.pumpWidget(
      testApp(({String query = '', Uri? pageUrl}) async {
        if (pageUrl != null) {
          cursorRequests += 1;
          if (cursorRequests == 1) {
            throw Exception('cursor failed');
          }
          return InventoryBatchPage(
            batches: [batch(id: 'recovered', name: '补充药品')],
            nextPage: null,
          );
        }
        return InventoryBatchPage(
          batches: List.generate(
            8,
            (index) => batch(id: '$index', name: '现有药品 $index'),
          ),
          nextPage: Uri.parse(
            'https://api.invalid/api/v1/inventory-batches?cursor=retry',
          ),
        );
      }),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('medicine-cabinet-list')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多药品加载失败'), findsOneWidget);
    expect(find.text('现有药品 7'), findsOneWidget);
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();

    expect(cursorRequests, 2);
    expect(find.text('补充药品'), findsOneWidget);
    expect(find.text('更多药品加载失败'), findsNothing);
  });

  testWidgets('distinguishes an empty search from an empty cabinet',
      (tester) async {
    await tester.pumpWidget(
      testApp(
        ({String query = '', Uri? pageUrl}) async =>
            const InventoryBatchPage(batches: [], nextPage: null),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('药箱里还没有药品'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('medicine-search')),
      '不存在的药',
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(find.text('没有找到匹配药品'), findsOneWidget);
    expect(find.text('药箱里还没有药品'), findsNothing);
  });
}
