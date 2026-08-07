# iOS HIG 界面重设计实施计划

> **面向执行代理：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项完成。步骤使用复选框跟踪。

**目标：** 将智能提醒 Flutter 客户端升级为符合 iPhone Apple HIG 的三标签高频工具界面，同时完整保留认证、提醒、药箱和 OCR 的真实业务能力。

**架构：** 继续以 Material 3 为渲染基础，在 `AppTheme` 建立 iOS 风格的语义颜色、文本、分组列表与导航令牌；业务页面继续通过既有仓储和回调获得真实数据。顶层使用持久化的 `IndexedStack` 保存标签状态，二级业务通过标准 `MaterialPageRoute` 推进，输入与 OCR 使用单层 Sheet 或页面，避免覆盖业务流。

**技术栈：** Flutter、Material 3、`lucide_icons_flutter`、`permission_handler`、`image_picker`、现有 HTTP API 与 Flutter widget test。

---

## 文件边界

| 文件 | 责任 |
| --- | --- |
| `app/lib/app/theme/app_theme.dart` | 定义浅色、深色、文字缩放和 Material 组件的统一 iOS 风格主题。 |
| `app/lib/app/theme/app_colors.dart` | 提供成功、警告、错误、离线等语义状态颜色，不能以颜色单独传达状态。 |
| `app/lib/ui/components/app_page_header.dart` | 提供顶层大标题、二级紧凑标题和 44pt 操作区。 |
| `app/lib/ui/components/app_list_row.dart` | 提供可换行、可访问、最小 44pt 的 inset grouped 列表行。 |
| `app/lib/ui/components/app_property_row.dart` | 提供详情页属性分组行与超大字号下的纵向回流。 |
| `app/lib/ui/components/app_status_banner.dart` | 提供包含文字、图标和语义标签的内联状态反馈。 |
| `app/lib/app/shell/app_shell.dart` | 提供三个顶层目的地、状态保持、设置入口和底部拇指区创建动作。 |
| `app/lib/features/{today,plans,medicine_cabinet}/presentation/*.dart` | 将三个核心列表页调整为安全区内的大标题、分组列表、内联加载/错误和可达操作。 |
| `app/lib/features/{medicine_cabinet,medicine_ocr,plans,reminder_drafts}/presentation/*.dart` | 将详情与任务流调整为标准返回、取消、确认、删除确认和不阻塞等待状态。 |
| `app/test/*_test.dart` | 覆盖主题、导航、命中区域、语义、文字缩放、深色模式、权限和真实业务入口。 |

## 任务 1：建立可验证的 iOS 视觉令牌

**文件：**
- 修改：`app/lib/app/theme/app_theme.dart`
- 修改：`app/lib/app/theme/app_colors.dart`
- 测试：`app/test/app_theme_test.dart`
- 测试：`app/test/ui_components_test.dart`

- [ ] **步骤 1：补充失败测试，锁定 iOS 主题的交互色、深色模式与 44pt 控件。**

```dart
test('浅色和深色主题都使用深绿色交互色并关闭 surface tint', () {
  for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.surfaceTint, Colors.transparent);
    expect(theme.filledButtonTheme.style!.minimumSize!
        .resolve(<WidgetState>{}), const Size(64, 44));
  }
});
```

- [ ] **步骤 2：运行测试，确认在引入新的 HIG 令牌前失败。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/app_theme_test.dart`

预期：新增断言失败，指出主题尚未暴露所需的统一令牌或尺寸。

- [ ] **步骤 3：在主题中实现系统表面层级和语义组件默认值。**

```dart
return ThemeData(
  useMaterial3: true,
  colorScheme: colorScheme,
  scaffoldBackgroundColor: scaffoldBackground,
  fontFamily: fontFamily,
  materialTapTargetSize: MaterialTapTargetSize.padded,
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: colorScheme.onSurface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  navigationBarTheme: NavigationBarThemeData(
    height: 72,
    backgroundColor: colorScheme.surface,
    surfaceTintColor: Colors.transparent,
  ),
);
```

保留 `NotoSansSC`，所有字号仍由 `TextTheme` 提供，禁止新增不可缩放的 `TextStyle(fontSize: ...)` 作为正文或标签文本。

- [ ] **步骤 4：运行主题与组件测试，确认通过。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/app_theme_test.dart test/ui_components_test.dart`

预期：PASS，且 200% 文字缩放下无 `TextOverflow` 异常。

- [ ] **步骤 5：提交该任务。**

```bash
git add app/lib/app/theme/app_theme.dart app/lib/app/theme/app_colors.dart app/test/app_theme_test.dart app/test/ui_components_test.dart
git commit -m "feat(app): refine iOS visual tokens"
```

## 任务 2：统一页面、列表和状态组件的 HIG 交互

**文件：**
- 修改：`app/lib/ui/components/app_page_header.dart`
- 修改：`app/lib/ui/components/app_list_row.dart`
- 修改：`app/lib/ui/components/app_property_row.dart`
- 修改：`app/lib/ui/components/app_status_banner.dart`
- 测试：`app/test/ui_components_test.dart`

- [ ] **步骤 1：增加大标题、列表行与属性行在超大字体时回流的失败测试。**

```dart
testWidgets('列表行在 200% 文字缩放下保留完整标题和 44pt 命中区', (tester) async {
  await tester.pumpApp(
    const AppListRow(title: '明天早上出门前查询天气并决定是否携带雨伞'),
    textScaler: const TextScaler.linear(2),
  );
  expect(tester.getSize(find.byType(AppListRow)).height, greaterThanOrEqualTo(44));
  expect(tester.widget<Text>(find.textContaining('查询天气')).overflow,
      isNot(TextOverflow.ellipsis));
});
```

- [ ] **步骤 2：运行测试，确认超大字号覆盖能捕获当前的硬编码或截断风险。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/ui_components_test.dart`

预期：新增测试先失败或暴露布局异常。

- [ ] **步骤 3：实现系统式的页面标题、分组列表和状态语义。**

```dart
Semantics(
  button: onTap != null,
  label: title,
  child: ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(onTap: onTap, child: content),
    ),
  ),
);
```

标题组件在顶层选择 `textTheme.headlineLarge`，二级页选择 `titleLarge`；属性行根据 `MediaQuery.textScalerOf(context)` 在横排不能容纳时变为纵向；状态横幅对每种状态同时输出图标、中文名称和 `Semantics` 标签。

- [ ] **步骤 4：运行组件测试，确认通过。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/ui_components_test.dart`

预期：PASS，语义标签和所有动作测试保持通过。

- [ ] **步骤 5：提交该任务。**

```bash
git add app/lib/ui/components app/test/ui_components_test.dart
git commit -m "feat(app): improve accessible iOS components"
```

## 任务 3：重构应用壳为 HIG 三标签与可达创建流

**文件：**
- 修改：`app/lib/app/shell/app_shell.dart`
- 测试：`app/test/app_shell_test.dart`

- [ ] **步骤 1：增加顶层三标签、选中图标、设置入口与标签状态保持的失败测试。**

```dart
testWidgets('iPhone 壳只显示三个顶层标签并保留所选页面', (tester) async {
  await tester.pumpWidget(buildShell());
  expect(find.byType(NavigationBar), findsOneWidget);
  expect(find.text('今天'), findsWidgets);
  await tester.tap(find.text('药箱').last);
  await tester.pumpAndSettle();
  expect(find.byKey(const PageStorageKey<String>('medicine-tab')), findsOneWidget);
  expect(find.byTooltip('打开设置'), findsOneWidget);
});
```

- [ ] **步骤 2：运行壳测试，确认新增断言失败。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/app_shell_test.dart`

预期：FAIL，直到壳暴露对应导航语义或稳定键。

- [ ] **步骤 3：实现三个顶层目的地、iPhone 底部创建动作与大屏自适应。**

```dart
final content = IndexedStack(index: _selectedIndex, children: tabs);
return Scaffold(
  body: SafeArea(top: false, child: content),
  bottomNavigationBar: SafeArea(
    top: false,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _QuickCreateBar(enabled: enabled, onPressed: _openQuickCreate, compact: true),
      NavigationBar(selectedIndex: _selectedIndex, onDestinationSelected: _selectDestination,
        destinations: _destinations),
    ]),
  ),
);
```

保留宽屏 `NavigationRail`，但 375pt 至 430pt 始终使用底部 `NavigationBar`。图标保持 Lucide；使用轮廓/填充或清晰选中指示表达当前标签，不能只靠颜色。

- [ ] **步骤 4：运行壳测试，确认真实提醒入口与退出认证逻辑未回归。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/app_shell_test.dart test/reminder_ui_auth_compatibility_test.dart`

预期：PASS，且“提醒管理”可从今天页触达。

- [ ] **步骤 5：提交该任务。**

```bash
git add app/lib/app/shell/app_shell.dart app/test/app_shell_test.dart app/test/reminder_ui_auth_compatibility_test.dart
git commit -m "feat(app): align shell with iPhone navigation"
```

## 任务 4：改造今天与计划的列表、加载和详情层级

**文件：**
- 修改：`app/lib/features/today/presentation/today_screen.dart`
- 修改：`app/lib/features/plans/presentation/plans_screen.dart`
- 修改：`app/lib/features/plans/presentation/plan_detail_screen.dart`
- 测试：`app/test/today_screen_test.dart`
- 测试：`app/test/plans_screen_test.dart`
- 测试：`app/test/plan_detail_screen_test.dart`

- [ ] **步骤 1：增加核心列表页在窄屏、横屏、深色和 200% 字号下的失败测试。**

```dart
testWidgets('今天页在 375pt 宽和 200% 文字缩放下完整显示提醒', (tester) async {
  await tester.pumpApp(TodayScreen(repository: repository),
    surfaceSize: const Size(375, 812), textScaler: const TextScaler.linear(2));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.byType(AppListRow), findsWidgets);
});
```

- [ ] **步骤 2：运行三个页面的测试，确认新增断言失败。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/today_screen_test.dart test/plans_screen_test.dart test/plan_detail_screen_test.dart`

预期：新增测试在缺少目标断言或适配时失败。

- [ ] **步骤 3：将页面组织为安全区内的顶层大标题、分区和内联状态。**

```dart
return Scaffold(
  body: SafeArea(
    child: CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: AppPageHeader(title: '今天', ...)),
        SliverPadding(padding: const EdgeInsets.all(AppSpacing.lg), sliver: ...),
      ],
    ),
  ),
);
```

保留仓储加载、提醒管理和计划详情路由；将失败、空态和加载态放到当前滚动层级，加载时使用与最终行形状一致的骨架或内联占位，禁止使用全屏阻塞进度圈。详情页使用标准返回按钮和紧凑标题。

- [ ] **步骤 4：运行今天、计划和详情回归测试。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/today_screen_test.dart test/plans_screen_test.dart test/plan_detail_screen_test.dart`

预期：PASS，测试覆盖真实列表、筛选、错误重试和详情返回。

- [ ] **步骤 5：提交该任务。**

```bash
git add app/lib/features/today/presentation/today_screen.dart app/lib/features/plans/presentation app/test/today_screen_test.dart app/test/plans_screen_test.dart app/test/plan_detail_screen_test.dart
git commit -m "feat(app): refine today and plans for iPhone"
```

## 任务 5：完成药箱、药品详情和 OCR 的 HIG 工作流

**文件：**
- 修改：`app/lib/features/medicine_cabinet/presentation/medicine_cabinet_screen.dart`
- 修改：`app/lib/features/medicine_cabinet/presentation/medicine_detail_screen.dart`
- 修改：`app/lib/features/medicine_ocr/presentation/medicine_ocr_screen.dart`
- 测试：`app/test/medicine_cabinet_screen_test.dart`
- 测试：`app/test/medicine_ocr_screen_test.dart`

- [ ] **步骤 1：增加搜索、相机权限恢复、删除确认和 OCR 确认入库的失败测试。**

```dart
testWidgets('永久拒绝相机权限时提供至少 44pt 的系统设置入口', (tester) async {
  await tester.pumpWidget(buildMedicineCabinet(
    captureAvailability: MedicineCaptureAvailability.permanentlyDenied));
  await tester.pumpAndSettle();
  final action = find.widgetWithText(FilledButton, '打开设置');
  expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
  expect(tester.getSemantics(action).label, contains('打开设置'));
});
```

- [ ] **步骤 2：运行药箱和 OCR 测试，确认新增断言失败。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/medicine_cabinet_screen_test.dart test/medicine_ocr_screen_test.dart`

预期：FAIL，直至实现明确的权限、确认或可访问语义。

- [ ] **步骤 3：实现搜索、筛选、分组详情与单层 OCR 任务流。**

```dart
showModalBottomSheet<QuickCreateResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => const _TaskSheet(),
);
```

药箱顶部保留搜索和筛选，库存条目使用 `AppListRow`；详情用分组属性行呈现批次、有效期和数量。删除必须经 `AlertDialog` 二次确认。拍照前继续保留用途说明；永久拒绝时显示“打开设置”；OCR 的上传、轮询与确认必须在当前页面显示进度，并保证确认前不会调用库存写入 API。

- [ ] **步骤 4：运行药箱、OCR 与相机权限全部回归测试。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/medicine_cabinet_screen_test.dart test/medicine_ocr_screen_test.dart test/smart_reminder_app_test.dart`

预期：PASS，真实 API 依赖仍由注入回调提供。

- [ ] **步骤 5：提交该任务。**

```bash
git add app/lib/features/medicine_cabinet/presentation app/lib/features/medicine_ocr/presentation app/test/medicine_cabinet_screen_test.dart app/test/medicine_ocr_screen_test.dart
git commit -m "feat(app): refine medicine and OCR flows"
```

## 任务 6：统一二级表单、设置和确认页面

**文件：**
- 修改：`app/lib/app/settings/settings_screen.dart`
- 修改：`app/lib/features/reminder_drafts/presentation/reminder_draft_screen.dart`
- 修改：`app/lib/features/reminder_drafts/presentation/reminder_composer_screen.dart`
- 修改：`app/lib/features/quick_create/presentation/quick_create_sheet.dart`
- 修改：`app/lib/features/profile/presentation/change_password_screen.dart`
- 测试：`app/test/settings_screen_test.dart`
- 测试：`app/test/reminder_draft_screen_test.dart`
- 测试：`app/test/quick_create_sheet_test.dart`

- [ ] **步骤 1：增加 Sheet 取消入口和危险操作确认的失败测试。**

```dart
testWidgets('快速创建 Sheet 同时提供取消入口和至少 44pt 的确认动作', (tester) async {
  await tester.pumpApp(const QuickCreateSheet(...));
  expect(find.text('取消'), findsOneWidget);
  expect(tester.getSize(find.text('取消')).height, greaterThanOrEqualTo(44));
});
```

- [ ] **步骤 2：运行表单与设置测试，确认新增测试失败。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/settings_screen_test.dart test/reminder_draft_screen_test.dart test/quick_create_sheet_test.dart`

预期：FAIL，直到每个任务层提供明确取消、返回与确认路径。

- [ ] **步骤 3：实现单层 Sheet、标准顶部导航和底部确认操作。**

```dart
Scaffold(
  appBar: AppBar(
    leading: IconButton(tooltip: '返回', onPressed: Navigator.of(context).pop,
      icon: const Icon(Icons.arrow_back_ios_new)),
  ),
  bottomNavigationBar: SafeArea(
    top: false,
    child: Padding(padding: const EdgeInsets.all(16), child: FilledButton(...)),
  ),
  body: ...,
);
```

设置继续经齿轮入口提供主题、账号、修改密码和退出登录；退出登录、删除与覆盖操作均使用中文警告对话框。快速创建、语音解析和提醒确认必须在同一单层任务中展示可见进度和失败消息，不能嵌套 Sheet。

- [ ] **步骤 4：运行表单、设置、认证兼容性回归测试。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test test/settings_screen_test.dart test/reminder_draft_screen_test.dart test/quick_create_sheet_test.dart test/reminder_ui_auth_compatibility_test.dart`

预期：PASS，退出登录后根路由不保留受保护页面。

- [ ] **步骤 5：提交该任务。**

```bash
git add app/lib/app/settings app/lib/features/reminder_drafts/presentation app/lib/features/quick_create/presentation app/lib/features/profile/presentation app/test/settings_screen_test.dart app/test/reminder_draft_screen_test.dart app/test/quick_create_sheet_test.dart
git commit -m "feat(app): refine iOS task and settings flows"
```

## 任务 7：完成全量验证和真机前构建门禁

**文件：**
- 修改：`docs/superpowers/specs/2026-08-07-ios-hig-ui-redesign.md`（仅在验收发现需求与实现不一致时同步中文事实）
- 测试：`app/test/`

- [ ] **步骤 1：格式化并静态检查。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/dart format --set-exit-if-changed lib test`

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter analyze`

预期：格式化命令无输出，分析输出 `No issues found!`。

- [ ] **步骤 2：执行完整 widget、数据层、认证、通知与 OCR 回归。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter test`

预期：全部测试通过，且不出现未处理的 Flutter 异常。

- [ ] **步骤 3：检查差异健康度。**

运行：`git diff --check`

预期：无输出。

- [ ] **步骤 4：构建 iOS 模拟器产物。**

运行：`../../flutter-ui-redesign/.tools/flutter/bin/flutter build ios --simulator --debug`

预期：构建成功；若因本机 CocoaPods/Xcode 环境失败，记录完整报错与已验证的 Dart 测试结果，不能将此失败误报为应用代码失败。

- [ ] **步骤 5：提交验证后最终变更。**

```bash
git add docs/superpowers/specs/2026-08-07-ios-hig-ui-redesign.md
git commit -m "docs: record iOS HIG verification"
```

## 自检结果

- 规格覆盖：任务 1 至 3 覆盖主题、三个顶层标签、安全区和点击目标；任务 4 至 6 覆盖三个核心闭环、详情、Sheet、OCR 权限和认证；任务 7 覆盖静态、单元、widget 与 iOS 构建验证。
- 占位扫描：本文档不含 `TODO`、`TBD` 或“稍后实现”占位；每项代码任务包含目标路径、断言、命令和通过标准。
- 类型一致性：引用的 `AppShell`、`TodayScreen`、`PlansScreen`、`MedicineCabinetScreen`、`MedicineCaptureAvailability`、`AppListRow`、`QuickCreateSheet` 均存在于当前代码库；测试中的省略构造仅为表达测试目标，实施时使用现有测试夹具和真实必填参数。
