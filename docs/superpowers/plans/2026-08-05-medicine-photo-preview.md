# Medicine Photo Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在药盒识别页拍照后展示正面与有效期双缩略图，并保证只有用户点击“开始识别”才上传图片和创建 OCR 任务。

**Architecture:** 保留 `MedicineOcrScreen` 现有 `_frontBytes`、`_expiryBytes` 与阶段状态机，在 capture 阶段增加一个纯展示的照片槽位构建方法。照片继续只存在内存中；现有 `_start` 是唯一进入上传状态并调用 `createJob` 的入口，失败时沿用现有回到 capture 阶段的逻辑。

**Tech Stack:** Flutter、Material 3、`Image.memory`、Flutter Widget Tests。

---

### Task 1: 用 Widget 测试锁定预览和上传边界

**Files:**
- Modify: `app/test/medicine_ocr_screen_test.dart`
- Test: `app/test/medicine_ocr_screen_test.dart`

- [ ] **Step 1: 扩展主流程测试，证明拍照不会创建 OCR 任务**

在 `requires front photo, shows candidates, and confirms edited values` 中记录调用次数与字节，并在点击开始识别前加入：

```dart
var createJobCalls = 0;
List<int>? submittedFront;
List<int>? submittedExpiry;

createJob: ({required frontBytes, expiryBytes}) async {
  createJobCalls += 1;
  submittedFront = frontBytes;
  submittedExpiry = expiryBytes;
  return const OcrJob(id: 'job-1', status: 'queued');
},
```

拍摄正面后断言：

```dart
expect(find.byKey(const Key('front-photo-preview')), findsOneWidget);
expect(find.byKey(const Key('expiry-photo-preview')), findsNothing);
expect(createJobCalls, 0);
```

拍摄有效期后断言：

```dart
expect(find.byKey(const Key('front-photo-preview')), findsOneWidget);
expect(find.byKey(const Key('expiry-photo-preview')), findsOneWidget);
expect(createJobCalls, 0);
```

点击“开始识别”后断言：

```dart
expect(createJobCalls, 1);
expect(submittedFront, [1]);
expect(submittedExpiry, [2]);
```

- [ ] **Step 2: 增加取消重拍保留缩略图测试**

新增测试，第一次正面拍摄返回 `[1]`，第二次重拍返回 `null`：

```dart
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
```

- [ ] **Step 3: 增加上传失败保留照片并允许重试测试**

构造第一次 `createJob` 抛出异常、第二次返回任务的场景：

```dart
testWidgets('upload failure keeps previews and allows retry', (tester) async {
  var createJobCalls = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: MedicineOcrScreen(
        capture: (kind) async => kind == 'front' ? [1] : [2],
        createJob: ({required frontBytes, expiryBytes}) async {
          createJobCalls += 1;
          if (createJobCalls == 1) throw Exception('network unavailable');
          return const OcrJob(id: 'job-1', status: 'queued');
        },
        getJob: (_) async => const OcrJob(
          id: 'job-1',
          status: 'succeeded',
          candidate: OcrCandidate(medicineName: '测试药品'),
        ),
        confirmJob: (_, __) async {},
        pollInterval: Duration.zero,
      ),
    ),
  );

  await tester.tap(find.text('拍摄药盒正面'));
  await tester.pump();
  await tester.tap(find.text('拍摄有效期（可选）'));
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
```

- [ ] **Step 4: 运行聚焦测试并确认 RED**

Run:

```bash
cd app
/Users/liuyang/Desktop/own/smart-reminder/.tools/flutter/bin/flutter test --no-pub test/medicine_ocr_screen_test.dart
```

Expected: FAIL，原因是 `front-photo-preview`、`expiry-photo-preview` 与重拍 tooltip 尚不存在。

- [ ] **Step 5: 提交测试**

```bash
git add app/test/medicine_ocr_screen_test.dart
git commit -m "test: require medicine photo previews"
```

### Task 2: 实现双缩略图预览

**Files:**
- Modify: `app/lib/features/medicine_ocr/presentation/medicine_ocr_screen.dart`
- Test: `app/test/medicine_ocr_screen_test.dart`

- [ ] **Step 1: 引入内存图片所需类型**

在文件顶部加入：

```dart
import 'dart:typed_data';
```

- [ ] **Step 2: 增加稳定尺寸的照片槽位方法**

在 `_MedicineOcrScreenState` 内增加：

```dart
Widget _photoSlot({
  required String kind,
  required String label,
  required List<int>? bytes,
}) {
  final photoBytes = bytes;
  final retakeLabel = kind == 'front' ? '重新拍摄药盒正面' : '重新拍摄有效期';
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AspectRatio(
        aspectRatio: 4 / 3,
        child: photoBytes != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      Uint8List.fromList(photoBytes),
                      key: Key('$kind-photo-preview'),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xFFE7ECE9),
                        child: Icon(Icons.image_outlined),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      tooltip: retakeLabel,
                      onPressed: () => _capture(kind),
                      icon: const Icon(Icons.camera_alt_outlined),
                    ),
                  ),
                ],
              )
            : OutlinedButton.icon(
                onPressed: () => _capture(kind),
                icon: Icon(
                  kind == 'front'
                      ? Icons.camera_alt_outlined
                      : Icons.event_outlined,
                ),
                label: Text('拍摄$label'),
              ),
      ),
      const SizedBox(height: 6),
      Text(label, textAlign: TextAlign.center),
    ],
  );
}
```

`errorBuilder` 只保护损坏或测试字节的渲染；真实相机 JPEG 仍通过 `Image.memory` 展示。

- [ ] **Step 3: 用双槽位替换两个独立拍摄按钮**

把 `_captureView` 顶部替换为：

```dart
Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(
      child: _photoSlot(
        kind: 'front',
        label: '药盒正面',
        bytes: _frontBytes,
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: _photoSlot(
        kind: 'expiry',
        label: '有效期（可选）',
        bytes: _expiryBytes,
      ),
    ),
  ],
),
```

保留 `_frontBytes == null ? null : _start`，保证正面必拍且拍照不触发上传。

- [ ] **Step 4: 确认入库时清理错误状态**

在 `_confirm` 成功后的 `setState` 中加入：

```dart
_error = null;
```

- [ ] **Step 5: 运行聚焦测试并确认 GREEN**

Run:

```bash
cd app
/Users/liuyang/Desktop/own/smart-reminder/.tools/flutter/bin/flutter test --no-pub test/medicine_ocr_screen_test.dart
```

Expected: 该文件全部测试通过。

- [ ] **Step 6: 运行格式化与静态分析**

```bash
/Users/liuyang/Desktop/own/smart-reminder/.tools/flutter/bin/dart format \
  app/lib/features/medicine_ocr/presentation/medicine_ocr_screen.dart \
  app/test/medicine_ocr_screen_test.dart
cd app
/Users/liuyang/Desktop/own/smart-reminder/.tools/flutter/bin/flutter analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 7: 提交实现**

```bash
git add app/lib/features/medicine_ocr/presentation/medicine_ocr_screen.dart \
  app/test/medicine_ocr_screen_test.dart
git commit -m "feat: preview medicine photos before OCR"
```

### Task 3: 完整验证、发布与 iPhone 验收

**Files:**
- Verify: `app/lib/features/medicine_ocr/presentation/medicine_ocr_screen.dart`
- Verify: `app/test/medicine_ocr_screen_test.dart`

- [ ] **Step 1: 运行 Flutter 全量测试和分析**

```bash
cd app
/Users/liuyang/Desktop/own/smart-reminder/.tools/flutter/bin/flutter test --no-pub
/Users/liuyang/Desktop/own/smart-reminder/.tools/flutter/bin/flutter analyze --no-pub
```

Expected: 全部 Widget/Unit 测试通过，静态分析无问题。

- [ ] **Step 2: 运行仓库完整回归检查**

```bash
.venv/bin/pytest backend -q
.venv/bin/python backend/manage.py check
git diff --check
git status --short
```

Expected: 后端测试通过，Django 无检查问题，diff 无空白错误，工作树干净。

- [ ] **Step 3: 推送 GitHub main**

```bash
git push origin main
```

Expected: GitHub `main` 指向当前完整提交。

- [ ] **Step 4: 安全构建 iPhone Release 包**

从腾讯云生成 `iphone-test` 的现有 Token 到权限为 `600` 的临时文件，传输到本机后生成仅包含 `API_BASE_URL=https://aipupu.cloud` 与 `API_ACCESS_TOKEN` 的临时 JSON。构建命令：

```bash
cd app
/Users/liuyang/Desktop/own/smart-reminder/.tools/flutter/bin/flutter build ios \
  --release --no-pub \
  --dart-define-from-file=/private/tmp/smart-reminder-iphone-defines.json
```

构建完成后立即删除服务器和本机的原始 Token 与 JSON 临时文件，不输出 Token，不提交生成文件。

- [ ] **Step 5: 覆盖安装并执行真机验收**

```bash
xcrun devicectl device install app \
  --device E017E520-1D38-5853-8BA0-B1F0A312B72E \
  app/build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --terminate-existing \
  --device E017E520-1D38-5853-8BA0-B1F0A312B72E \
  com.liuyang.smartreminder.smartReminderApp
```

验收顺序：拍摄正面后看到缩略图；未点击“开始识别”前腾讯云没有新的 `/api/v1/ocr/uploads`；点击后才出现上传与任务请求；拍摄有效期后显示第二张缩略图；取消重拍保留旧图；识别结果可确认入库。
