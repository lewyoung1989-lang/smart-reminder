# 药箱库存批次滑动删除实施计划

> **面向代理开发者：** 必须使用 `superpowers:executing-plans` 逐项实施本计划，并在每项功能中遵循 `superpowers:test-driven-development`；完成前使用 `superpowers:verification-before-completion` 重新运行全部验证。

**目标：** 在家庭药箱列表中加入仅向左滑动的单批次删除、二次确认和失败恢复，并通过用户隔离的后端删除接口持久化。

**架构：** Django 提供 owner-scoped `DELETE` 端点；Flutter 数据层封装 DELETE 请求；页面以依赖注入的删除回调驱动 `Dismissible`，成功后同步更新列表并屏蔽旧分页响应。所有删除都以库存批次 ID 为边界，不删除 `MedicineItem` 或其他批次。

**技术栈：** Django REST Framework、pytest、Flutter Material、Dart、flutter_test、package:http。

---

### 任务 1：增加单库存批次删除接口

**文件：**

- 修改：`backend/tests/medicines/api/test_inventory_batches.py`
- 修改：`backend/apps/medicines/api/views.py`
- 修改：`backend/apps/medicines/api/urls.py`

- [ ] **步骤 1：写入失败的后端删除测试**

新增测试验证未登录返回 `401`，自己的批次返回 `204`，同一 `MedicineItem` 的另一个批次和主记录保留，其他用户的批次返回 `404`：

```python
@pytest.mark.django_db
def test_inventory_batch_delete_requires_authentication(api_client, user):
    batch = create_batch(owner=user, name="布洛芬")
    response = api_client.delete(f"/api/v1/inventory-batches/{batch.id}")
    assert response.status_code == 401
    assert InventoryBatch.objects.filter(id=batch.id).exists()


@pytest.mark.django_db
def test_inventory_batch_delete_removes_only_owned_batch(api_client, user):
    medicine = MedicineItem.objects.create(owner=user, name="布洛芬")
    removed = InventoryBatch.objects.create(medicine=medicine, batch_number="A")
    kept = InventoryBatch.objects.create(medicine=medicine, batch_number="B")
    api_client.force_authenticate(user)

    response = api_client.delete(f"/api/v1/inventory-batches/{removed.id}")

    assert response.status_code == 204
    assert not InventoryBatch.objects.filter(id=removed.id).exists()
    assert InventoryBatch.objects.filter(id=kept.id).exists()
    assert MedicineItem.objects.filter(id=medicine.id).exists()
```

- [ ] **步骤 2：运行测试并确认端点不存在**

运行：

```bash
cd backend
../.venv/bin/pytest tests/medicines/api/test_inventory_batches.py -q
```

预期：新删除请求因 URL 不存在或方法不允许而失败。

- [ ] **步骤 3：实现 owner-scoped 删除视图**

增加 `InventoryBatchDestroyView(DestroyAPIView)`，使用 `IsAuthenticated`，查询集限定为：

```python
InventoryBatch.objects.filter(medicine__owner=self.request.user)
```

URL 使用 `<uuid:pk>`，路径保持无尾斜杠：

```python
path(
    "inventory-batches/<uuid:pk>",
    InventoryBatchDestroyView.as_view(),
    name="inventory-batch-detail",
)
```

- [ ] **步骤 4：运行后端测试并确认通过**

运行：`cd backend && ../.venv/bin/pytest tests/medicines/api/test_inventory_batches.py -q`

预期：全部通过。

### 任务 2：增加 Flutter 删除 API

**文件：**

- 修改：`app/test/medicine_cabinet_api_test.dart`
- 修改：`app/lib/features/medicine_cabinet/data/medicine_cabinet_api.dart`

- [ ] **步骤 1：写入失败的 DELETE 请求测试**

新增一个 `204` 响应测试：

```dart
test('deletes one inventory batch with authorization', () async {
  final client = RecordingClient([http.Response('', 204)]);
  final api = MedicineCabinetApi(
    baseUrl: 'https://api.invalid',
    accessToken: 'token',
    client: client,
  );

  await api.deleteBatch('batch id/1');

  expect(client.requests.single.method, 'DELETE');
  expect(
    client.requests.single.url.path,
    '/api/v1/inventory-batches/batch%20id%2F1',
  );
  expect(client.requests.single.headers['Authorization'], 'Bearer token');
});
```

再增加 `500` 返回 `MedicineCabinetApiException` 的测试。

- [ ] **步骤 2：运行 API 测试并确认方法缺失**

运行：`cd app && flutter test test/medicine_cabinet_api_test.dart`

预期：因 `deleteBatch` 未定义而失败。

- [ ] **步骤 3：实现删除请求**

使用 `Uri(pathSegments: [...])` 或 `Uri.encodeComponent` 安全编码批次 ID，发送带现有 `_headers` 的 DELETE；只接受 `204`，其他状态复用 `MedicineCabinetApiException(statusCode, body)`。

- [ ] **步骤 4：运行 API 测试并确认通过**

运行：`cd app && flutter test test/medicine_cabinet_api_test.dart`

预期：全部通过。

### 任务 3：实现左滑确认和失败恢复

**文件：**

- 修改：`app/test/medicine_cabinet_screen_test.dart`
- 修改：`app/lib/features/medicine_cabinet/presentation/medicine_cabinet_screen.dart`

- [ ] **步骤 1：扩展测试构造器并写取消测试**

给测试 App 注入 `Future<void> Function(String id) deleteBatch`。渲染一行后向左拖动，断言出现 `删除这批药品？`，点击 `取消` 后删除回调未调用、药品仍存在。

- [ ] **步骤 2：运行 Widget 测试并确认构造参数缺失**

运行：`cd app && flutter test test/medicine_cabinet_screen_test.dart`

预期：因页面没有 `deleteBatch` 参数或列表行不是 `Dismissible` 而失败。

- [ ] **步骤 3：实现最小滑动与确认 UI**

新增：

```dart
typedef InventoryBatchDeleter = Future<void> Function(String id);
```

用 `Dismissible` 包装每行，配置：

```dart
key: ValueKey('medicine-batch-${batch.id}'),
direction: DismissDirection.endToStart,
background: const _DeleteBackground(),
confirmDismiss: (_) => _confirmDelete(batch),
onDismissed: (_) => _removeDeletedBatch(batch.id),
```

删除背景使用 `colorScheme.errorContainer`、`Icons.delete_outline` 和“删除”；对话框显示药名、可选批号以及“只会删除当前批次”。

- [ ] **步骤 4：增加确认成功测试**

滑动第一行、点击 `删除`，断言回调只收到第一行 ID，第一行消失，第二行和同名药品仍显示。删除最后一行时断言出现现有空状态。

- [ ] **步骤 5：增加确认失败测试**

让删除回调抛出异常；确认后断言行仍存在，并出现 `删除失败，请稍后重试`。

- [ ] **步骤 6：运行 Widget 测试并确认通过**

运行：`cd app && flutter test test/medicine_cabinet_screen_test.dart`

预期：全部通过。

### 任务 4：防止旧分页响应恢复已删除批次并完成依赖注入

**文件：**

- 修改：`app/test/medicine_cabinet_screen_test.dart`
- 修改：`app/test/smart_reminder_app_test.dart`
- 修改：`app/lib/features/medicine_cabinet/presentation/medicine_cabinet_screen.dart`
- 修改：`app/lib/main.dart`

- [ ] **步骤 1：写入失败的旧分页响应测试**

使用 `Completer<InventoryBatchPage>` 挂起下一页请求；删除页面已有批次后，让旧分页响应返回包含相同 ID 的批次，断言该行不会重新出现。

- [ ] **步骤 2：运行测试并确认旧响应会恢复批次**

运行：`cd app && flutter test test/medicine_cabinet_screen_test.dart`

预期：新测试因分页结果未过滤已删除 ID 而失败。

- [ ] **步骤 3：实现删除 ID 过滤并连接真实 API**

页面维护 `_deletedBatchIds`。`onDismissed` 加入 ID 并删除当前列表项；首屏加载成功时以服务器结果替换列表并清空集合；下一页合并时过滤集合中的 ID。`main.dart` 注入：

```dart
MedicineCabinetScreen(
  listBatches: _medicineCabinetApi.listBatches,
  deleteBatch: _medicineCabinetApi.deleteBatch,
)
```

同步更新所有直接构造 `MedicineCabinetScreen` 的测试。

- [ ] **步骤 4：运行药箱 Widget 和应用入口测试**

运行：

```bash
cd app
flutter test test/medicine_cabinet_screen_test.dart \
  test/smart_reminder_app_test.dart
```

预期：全部通过。

### 任务 5：完整验证与提交

**文件：**

- 检查：本计划涉及的全部文件

- [ ] **步骤 1：运行后端全量测试和 Django 检查**

```bash
.venv/bin/pytest backend -q
.venv/bin/python backend/manage.py check
```

预期：全部通过。

- [ ] **步骤 2：运行 Flutter 全量测试和静态分析**

```bash
cd app
flutter test
flutter analyze
```

预期：全部通过，无分析错误。

- [ ] **步骤 3：检查差异和隐私边界**

```bash
git diff --check
git status --short
```

确认删除端点只按 owner 查询，日志未加入药名或批号，未改动无关 OCR 设计文件。

- [ ] **步骤 4：提交功能代码**

明确暂存本功能文件，提交信息：

```text
feat: add medicine batch swipe deletion
```

- [ ] **步骤 5：推送、部署和真机准备**

推送 GitHub `main`。腾讯云按完整 SHA 部署后，使用 iPhone 验证：取消删除、成功删除、网络失败保留、同名多批次仅删除一行。
