# Flutter UI 与 OCR 整合实施计划

> **面向代理执行者：** 必须使用 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans` 逐任务执行；每个步骤使用复选框追踪。

**目标：** 在保留 `main` 的认证、真实库存/OCR API 和部署配置前提下，使用新的 Flutter UI 架构。

**架构：** 认证根应用和 `AuthenticatedClient` 保持不变。新增 API 适配仓储，将库存批次转换为 UI 的药品聚合与详情模型。药箱通过路由复用已有 OCR 采集、上传、轮询、人工确认页面，确认后重新加载库存。

**技术栈：** Flutter、Material 3、`http`、`image_picker`、既有 Django REST API、`flutter_test`、Golden 测试。

---

### 任务 1：移植 UI 基础和提醒确认兼容层

**文件：** UI 分支中新增的主题、组件、Today、Plans、Quick Create、Reminder Draft、通知创建服务及其测试；修改 `pubspec.yaml`。

- [ ] 写失败测试，证明 `AppTheme`、`QuickCreateSheet` 与 `ReminderCreationService` 可在当前 `main` 的认证客户端下编译。
- [ ] 运行聚焦测试，确认因缺少新 UI 类型而失败。
- [ ] 从 `feature/flutter-ui-redesign` 移植 UI 基础和提醒确认实现；保留 `ReminderDraftApi` 的认证客户端与 `ReminderNotificationScheduler` 的既有接口。
- [ ] 运行提醒、快速创建、主题和组件测试。
- [ ] 提交：`feat(app): adopt redesigned reminder experience`。

### 任务 2：实现真实库存到 UI 药箱的适配层

**文件：** 创建 `app/lib/features/medicine_cabinet/data/api_medicine_repository.dart`；复用 UI 分支的 `medicine_models.dart`、`medicine_repository.dart`、`medicine_cabinet_screen.dart`、`medicine_detail_screen.dart`；创建适配层测试。

- [ ] 写失败测试：多个 `InventoryBatch` 按药名和规格聚合；过期/临期状态采用最严重批次；详情保留每个批号、有效期和数量；API 失败向 UI 传递原始错误。
- [ ] 使用 `MedicineCabinetApi.listBatches()` 的固定假实现运行测试，确认适配器不存在而失败。
- [ ] 实现 `ApiMedicineRepository`：读取第一页库存、按 `medicineId` 聚合、映射状态与批次；`getById` 从已加载批次构建详情；只读模型不可变。
- [ ] 让新药箱的删除回调调用 `MedicineCabinetApi.deleteBatch`，成功后刷新，失败时保留列表并提示错误。
- [ ] 运行适配器、药箱和详情测试。
- [ ] 提交：`feat(app): connect medicine UI to inventory API`。

### 任务 3：将 OCR 流程接入新药箱

**文件：** 修改新药箱、`MedicineOcrScreen`（仅在需要返回成功结果时）、`main.dart`；添加集成 widget 测试。

- [ ] 写失败测试：点击已启用的“拍照录入”打开 OCR 路由；OCR 确认后返回药箱并重新调用仓储；取消或 OCR 失败不刷新药箱。
- [ ] 保持 `MedicineOcrScreen` 的现有双拍摄、签名上传、轮询和候选人工确认；将确认成功通过 `Navigator.pop(context, true)` 返回，且不在页面销毁后更新状态。
- [ ] 在药箱注入 `onCapture` 路由回调，认证用户使用 `ImagePicker` 和 `MedicineOcrApi`；相机权限不可用保持明确的禁用/设置恢复状态。
- [ ] 运行 OCR、药箱和集成测试。
- [ ] 提交：`feat(app): launch OCR from redesigned medicine cabinet`。

### 任务 4：接入认证根应用和自适应外壳

**文件：** 修改 `app/lib/main.dart`；移植 `app/lib/app/shell/app_shell.dart`、设置页面、Today/Plans 数据接口及所需真实或明确不可用仓储；更新根应用测试。

- [ ] 写失败测试：认证成功显示新三目的地外壳；认证失败仍显示既有登录；药箱使用 API 仓储；登出仍回到认证页。
- [ ] 保留 `AuthController`、`AuthenticatedClient`、刷新令牌、API 关闭和通知初始化；认证后构造 `ApiMedicineRepository` 与 OCR 路由依赖。
- [ ] 今天和计划在无真实 API 时使用明确的不可用仓储，不能向已认证生产用户展示演示数据。
- [ ] 设置页保留主题模式切换，并增加既有个人资料与登出入口。
- [ ] 运行认证、外壳、设置、药箱和提醒回归测试。
- [ ] 提交：`feat(app): integrate authenticated adaptive shell`。

### 任务 5：视觉、后端契约与最终验证

**文件：** 更新必要 Golden、无障碍和 API 测试；仅在结果变化时更新基线。

- [ ] 为真实库存适配、OCR 确认刷新和认证外壳添加测试；确保 OCR 未确认前不会创建库存。
- [ ] 重新生成受影响 Golden，检查中文字体、无裁切、无重叠和药箱相机入口。
- [ ] 运行 `../.tools/flutter/bin/dart format lib test`、`../.tools/flutter/bin/flutter analyze`、`../.tools/flutter/bin/flutter test`、格式检查；运行相关 Django OCR 测试。
- [ ] 核对 `git diff --check`、工作树范围和部署配置未被 UI 改写。
- [ ] 提交：`fix(app): verify UI OCR integration`（仅验证发现问题时）。
