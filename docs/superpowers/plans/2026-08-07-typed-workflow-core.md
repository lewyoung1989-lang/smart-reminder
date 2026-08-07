# 类型化工作流 V1 内核实施计划

> **面向代理执行者：** 必须使用 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans` 按任务执行；每个步骤使用复选框追踪。

**目标：** 建立 V1 三条核心闭环共用的确定性工作流内核，使文字或已完成转写只能形成经 Pydantic 校验、模板白名单编译和策略判断后的草稿或工作流，继续兼容既有单次提醒客户端。

**架构：** 新建 `apps.workflows` 负责不可变 Schema、模板/组件注册表、编译器、信任策略和工作流资源；既有 `ReminderDraft`、`ReminderRule` 原地扩展，旧 `/reminder-drafts` 与 `/voice/reminder-drafts` 保持 `legacy_once` 投影。模型只提供候选 `TaskSpec`，服务端忽略候选中的权限、风险、组件和信任声明，并只从注册表构造 `WorkflowSpec`。

**技术栈：** Django 5.2、DRF、Pydantic 2、PostgreSQL/SQLite 测试、pytest、既有 JWT 认证。

---

## 执行前自审与接口契约

本计划只交付三条闭环共用的“创建控制面”，不提前实现 Celery Runner、药品业务数据或外部天气/路线调用。运行时、药品有效期和 iOS 真机交互分别由后续计划实施；本计划中任何 `source.*` 节点仅是已验证的静态 Spec，绝不产生伪造的实时结果。

### 已确认的边界修正

- 既有 `ReminderIntentParser` 的输出是 `ReminderDraftData`，只能表示单次提醒，不能直接当作 `TaskSpec`。新建 `apps.workflows.services.task_parser.WorkflowTaskParser`：它先识别确定性的三种模板槽位；未命中时才调用新的 `WorkflowTaskProvider`，并用 `TaskSpec.model_validate` 验证返回值。旧 `ReminderIntentParser` 保持原样，仅供旧端点使用。
- `template_hint` 与 `requested_capabilities` 都是候选信息。`WorkflowCompiler` 只以完整槽位和注册表 manifest 决定模板，不能因客户端字段、模型风险等级或信任字段而扩大能力。
- `POST /api/v1/workflow-drafts` 只接收 `text`；严格序列化器拒绝 `trusted`、`risk_level`、`workflow_spec`、`capability_signature` 等未知字段，返回 400。成功时返回持久化的草稿、编译结果和策略；未匹配模板或缺少关键槽位返回 422 的结构化追问，不创建 `ReminderRule`。
- `POST /api/v1/workflow-drafts/<uuid:draft_id>/confirm` 在一个事务内锁定草稿，重新验证 JSON 为 `TaskSpec` 和 `WorkflowSpec`，重新运行编译器与策略。只有 `needs_confirmation` 或 `auto_create` 才能创建规则；确认 R0/R1 后创建或恢复同一能力签名的 `TrustGrant`；R2 不创建授权。重复确认必须返回同一 `reminder_id`。
- `ReminderRule.workflow_spec_json` 永远保存已编译的 JSON；`template_key`、`template_version`、`schema_version` 由服务端填充。旧规则的数据迁移一律回填 `legacy_once`，不反向解析或修改旧 `schedule_json`、`conditions_json`、`scheduled_at`。

### 固定请求与响应形状

```json
POST /api/v1/workflow-drafts
{"text":"明早九点到公司，坐公交，提前提醒我"}

201 Created
{
  "id":"<uuid>",
  "status":"pending_confirmation",
  "expires_at":"<ISO-8601>",
  "task_spec":{"schema_version":1,"intent":"create_workflow","template_hint":"smart_departure","title":"去公司","slots":{},"requested_capabilities":[],"ambiguities":[]},
  "workflow_spec":{"schema_version":1,"template_key":"smart_departure","template_version":"1.0.0","timezone":"Asia/Shanghai","nodes":[],"edges":[]},
  "policy":{"decision":"needs_confirmation","risk_level":"R1","capability_signature":"<sha256>","question":null}
}

POST /api/v1/workflow-drafts/<uuid>/confirm
201 Created
{"reminder_id":"<uuid>","status":"confirmed"}
```

### 自审结论

- 设计第 6、7、8、9、11、14、20 节均可对应到任务 1 至 5；第 10、12、13、18 节仍由任务 6 拆分，不冒充已实现。
- 删除了“复用既有解析器直接转换”的不成立假设，补入 `WorkflowTaskParser`、Provider 协议、严格输入与确认端点。
- 任务中出现的 `TaskSpec`、`WorkflowSpec`、`WorkflowCompiler`、`WorkflowTaskParser`、`PolicyDecision`、`TrustGrant` 均在任务 1 至 5 中首次定义或由本节给出输入输出约束；不保留任何未完成占位，也不允许未定义的自由表达式。

## 文件边界

| 文件 | 责任 |
|---|---|
| `backend/apps/workflows/domain/schemas.py` | 严格 `TaskSpec`、`WorkflowSpec`、节点、失败策略和能力签名模型。 |
| `backend/apps/workflows/domain/registry.py` | V1 三个模板及其固定组件、版本、风险和能力清单。 |
| `backend/apps/workflows/services/compiler.py` | 从候选槽位编译有限 DAG，验证节点、边、失败策略和最终通知可达性。 |
| `backend/apps/workflows/services/policy.py` | 判断追问、首次确认、R2 强制确认与已信任 R0/R1 直接创建。 |
| `backend/apps/workflows/models.py` | `WorkflowTemplate`、`TrustGrant`、`WorkflowDraft`、`WorkflowRun` 的持久化边界。 |
| `backend/apps/reminders/models.py` | 兼容扩展既有草稿和规则，不能删除旧字段。 |
| `backend/apps/workflows/api/*.py` | 草稿、工作流、信任授权的认证 API。 |
| `backend/tests/workflows/**` | Schema、编译、策略、迁移兼容和 API 的回归测试。 |

## 任务 1：建立工作流应用与兼容迁移

**文件：**
- 创建：`backend/apps/workflows/__init__.py`
- 创建：`backend/apps/workflows/apps.py`
- 创建：`backend/apps/workflows/models.py`
- 创建：`backend/apps/workflows/migrations/0001_initial.py`
- 修改：`backend/config/settings.py`
- 修改：`backend/apps/reminders/models.py`
- 创建：`backend/apps/reminders/migrations/0005_workflow_compatibility.py`
- 测试：`backend/tests/workflows/test_models.py`

- [ ] **步骤 1：编写失败模型测试，锁定个人隔离、唯一信任签名和旧规则兼容字段。**

```python
def test_trust_grant_is_unique_for_active_user_signature(user):
    TrustGrant.objects.create(
        user=user,
        capability_signature="a" * 64,
        template_key="smart_departure",
        template_major_version=1,
        scope_json={"owner": "self"},
    )
    with pytest.raises(IntegrityError):
        TrustGrant.objects.create(
            user=user,
            capability_signature="a" * 64,
            template_key="smart_departure",
            template_major_version=1,
            scope_json={"owner": "self"},
        )


def test_legacy_rule_retains_existing_schedule_fields_after_workflow_expansion(rule):
    rule.refresh_from_db()
    assert rule.template_key == "legacy_once"
    assert rule.workflow_spec_json["template_key"] == "legacy_once"
```

- [ ] **步骤 2：运行测试确认 RED。**

运行：

```bash
.venv/bin/python -m pytest backend/tests/workflows/test_models.py -q
```

预期：因 `apps.workflows`、模型或兼容字段不存在而失败。

- [ ] **步骤 3：实现最小数据模型和可回滚的加字段迁移。**

`WorkflowTemplate` 只保存注册键、版本、状态和能力清单；`TrustGrant` 保存 SHA-256 能力签名与撤销时间；`WorkflowDraft` 保存候选、编译结果、策略结果和 30 分钟过期时间。`ReminderRule` 新增可空 `template_key`、`template_version`、`schema_version`、`workflow_spec_json`、`next_run_at`、`last_run_at`、`revision`、`paused_reason`，并在数据迁移中把既有规则回填为固定 `legacy_once` Spec。迁移不删除 `schedule_json`、`conditions_json`、`scheduled_at` 或 `source_draft`。

- [ ] **步骤 4：运行模型与迁移测试确认 GREEN。**

```bash
.venv/bin/python -m pytest backend/tests/workflows/test_models.py backend/tests/reminders/migrations -q
.venv/bin/python backend/manage.py makemigrations --check --dry-run
```

预期：测试通过且不存在未生成迁移。

- [ ] **步骤 5：提交。**

```bash
git add backend/apps/workflows backend/apps/reminders/models.py backend/apps/reminders/migrations backend/config/settings.py backend/tests/workflows
git commit -m "feat: add typed workflow persistence"
```

## 任务 2：定义严格候选与可执行工作流 Schema

**文件：**
- 创建：`backend/apps/workflows/domain/__init__.py`
- 创建：`backend/apps/workflows/domain/schemas.py`
- 测试：`backend/tests/workflows/domain/test_schemas.py`

- [ ] **步骤 1：编写失败 Schema 测试。**

```python
def test_task_spec_rejects_model_supplied_risk_and_unknown_fields():
    with pytest.raises(ValidationError):
        TaskSpec.model_validate({
            "schema_version": 1,
            "intent": "create_workflow",
            "template_hint": "smart_departure",
            "slots": {},
            "requested_capabilities": [],
            "risk_level": "R0",
        })


def test_workflow_spec_rejects_cycle_and_requires_terminal_action():
    with pytest.raises(ValidationError):
        WorkflowSpec.model_validate(cyclic_workflow_payload())
```

- [ ] **步骤 2：运行测试确认 RED。**

```bash
.venv/bin/python -m pytest backend/tests/workflows/domain/test_schemas.py -q
```

- [ ] **步骤 3：实现严格的判别联合类型。**

`TaskSpec` 仅接受 `schema_version`、`intent`、`template_hint`、`title`、`slots`、`requested_capabilities` 和 `ambiguities`，所有模型可控对象均使用 `extra="forbid"`。`WorkflowNode` 仅接受注册的节点类型；`FailurePolicy` 为 `fail`、`degrade`、`skip`；`WorkflowSpec` 验证唯一节点 ID、边引用存在、无环、Trigger 入度为零、至少一条 `action.*` 终点可达。能力签名使用 `json.dumps(..., sort_keys=True, separators=(",", ":"))` 后计算 SHA-256。

- [ ] **步骤 4：运行 Schema 测试确认 GREEN。**

```bash
.venv/bin/python -m pytest backend/tests/workflows/domain/test_schemas.py -q
```

- [ ] **步骤 5：提交。**

```bash
git add backend/apps/workflows/domain backend/tests/workflows/domain/test_schemas.py
git commit -m "feat: validate typed workflow specs"
```

## 任务 3：建立模板和组件白名单编译器

**文件：**
- 创建：`backend/apps/workflows/domain/registry.py`
- 创建：`backend/apps/workflows/services/__init__.py`
- 创建：`backend/apps/workflows/services/compiler.py`
- 测试：`backend/tests/workflows/services/test_compiler.py`

- [ ] **步骤 1：编写失败编译器测试。**

```python
def test_compiler_ignores_untrusted_template_hint_and_selects_only_matching_registered_template():
    spec = compiler.compile(TaskSpec.model_validate({
        "schema_version": 1,
        "intent": "create_workflow",
        "template_hint": "not-a-template",
        "title": "明早到公司",
        "slots": departure_slots(),
        "requested_capabilities": ["route.estimate", "weather.forecast"],
        "ambiguities": [],
    }))
    assert spec.template_key == "smart_departure"
    assert {node.type for node in spec.nodes} == {
        "trigger.before_arrival", "source.route_eta", "source.weather_forecast",
        "decision.departure_time", "action.important_notification",
    }


def test_compiler_rejects_requested_capability_outside_template_manifest():
    with pytest.raises(WorkflowCompileError, match="unsupported_capability"):
        compiler.compile(task_with_capability("database.delete"))
```

- [ ] **步骤 2：运行测试确认 RED。**

```bash
.venv/bin/python -m pytest backend/tests/workflows/services/test_compiler.py -q
```

- [ ] **步骤 3：实现固定 V1 注册表与编译器。**

注册表只暴露 `medication_cycle`、`medicine_expiry`、`smart_departure` 三个模板及设计指定的组件。编译器根据槽位和请求能力选择模板，不能信任 `template_hint`；为天气、路线生成固定 `degrade` fallback；禁止任意节点、URL、回调名和表达式进入数据库。此任务只编译 Spec，不调用天气、路线、日历、通知或模型 Provider。

- [ ] **步骤 4：运行编译器测试确认 GREEN。**

```bash
.venv/bin/python -m pytest backend/tests/workflows/services/test_compiler.py -q
```

- [ ] **步骤 5：提交。**

```bash
git add backend/apps/workflows/domain/registry.py backend/apps/workflows/services/compiler.py backend/tests/workflows/services/test_compiler.py
git commit -m "feat: compile registered workflow templates"
```

## 任务 4：实现确认、追问与信任策略

**文件：**
- 创建：`backend/apps/workflows/services/policy.py`
- 测试：`backend/tests/workflows/services/test_policy.py`

- [ ] **步骤 1：编写失败策略测试。**

```python
def test_first_r1_departure_requires_confirmation_and_same_active_grant_allows_auto_create(user):
    result = policy.evaluate(user=user, spec=departure_spec, now=now)
    assert result.decision == "needs_confirmation"
    TrustGrant.objects.create(**grant_for(user, departure_spec))
    result = policy.evaluate(user=user, spec=departure_spec, now=now)
    assert result.decision == "auto_create"


def test_medication_never_auto_creates_even_with_matching_grant(user):
    TrustGrant.objects.create(**grant_for(user, medication_spec))
    assert policy.evaluate(user=user, spec=medication_spec, now=now).decision == "needs_confirmation"
```

- [ ] **步骤 2：运行测试确认 RED。**

```bash
.venv/bin/python -m pytest backend/tests/workflows/services/test_policy.py -q
```

- [ ] **步骤 3：实现策略结果。**

返回 `needs_clarification`、`needs_confirmation` 或 `auto_create`，并包含一个最高优先级问题、风险等级、能力签名和撤销期限。缺失必填槽位、冲突或三轮后仍未解决时不创建工作流；R2 始终确认；已撤销、模板版本不兼容、状态非 `active` 或权限范围变化时都不得直接创建。

- [ ] **步骤 4：运行策略测试确认 GREEN。**

```bash
.venv/bin/python -m pytest backend/tests/workflows/services/test_policy.py -q
```

- [ ] **步骤 5：提交。**

```bash
git add backend/apps/workflows/services/policy.py backend/tests/workflows/services/test_policy.py
git commit -m "feat: enforce workflow confirmation policy"
```

## 任务 5：暴露新草稿 API 并保留旧提醒兼容路径

**文件：**
- 创建：`backend/apps/workflows/api/__init__.py`
- 创建：`backend/apps/workflows/api/serializers.py`
- 创建：`backend/apps/workflows/api/views.py`
- 创建：`backend/apps/workflows/api/urls.py`
- 创建：`backend/apps/workflows/services/task_parser.py`
- 创建：`backend/apps/workflows/providers/__init__.py`
- 创建：`backend/apps/workflows/providers/deepseek.py`
- 修改：`backend/config/urls.py`
- 修改：`backend/apps/reminders/api/views.py`
- 测试：`backend/tests/workflows/api/test_workflow_drafts.py`
- 测试：`backend/tests/workflows/services/test_task_parser.py`
- 测试：`backend/tests/reminders/api/test_text_drafts.py`

- [ ] **步骤 1：编写失败 API 测试。**

```python
def test_workflow_draft_returns_compiled_policy_but_never_accepts_client_trust(api_client):
    response = api_client.post("/api/v1/workflow-drafts", {
        "text": "明早九点到公司，坐公交，提前提醒我",
        "trusted": True,
    }, format="json")
    assert response.status_code == 400
    assert "trusted" in response.json()


def test_legacy_endpoint_rejects_new_template_without_silent_once_fallback(api_client):
    response = api_client.post("/api/v1/reminder-drafts", {
        "text": "明早九点到公司，坐公交，提前提醒我",
    }, format="json")
    assert response.status_code == 422
    assert response.json()["code"] == "unsupported_workflow_for_client"


def test_confirm_revalidates_the_persisted_spec_and_is_idempotent(api_client, workflow_draft):
    first = api_client.post(f"/api/v1/workflow-drafts/{workflow_draft.id}/confirm")
    second = api_client.post(f"/api/v1/workflow-drafts/{workflow_draft.id}/confirm")
    assert first.status_code == 201
    assert second.status_code == 200
    assert second.json()["reminder_id"] == first.json()["reminder_id"]
```

- [ ] **步骤 2：运行测试确认 RED。**

```bash
.venv/bin/python -m pytest backend/tests/workflows/api/test_workflow_drafts.py backend/tests/reminders/api/test_text_drafts.py -q
```

- [ ] **步骤 3：实现统一草稿服务和兼容投影。**

`WorkflowTaskParser` 先以固定槽位构造三种 `TaskSpec`；需要模型时只调用 `WorkflowTaskProvider.parse(text, now, timezone)`，并以 `TaskSpec.model_validate` 拒绝模型的未知字段。`POST /api/v1/workflow-drafts` 只接收文本，编译、策略判断并保存 `WorkflowDraft`。确认端点在事务中再次验证 Spec、策略和用户归属，然后创建 `ReminderRule`；重复确认返回同一资源，确认 R0/R1 同时写入同签名 `TrustGrant`。旧接口仍调用 `ReminderIntentParser`，只允许 `legacy_once`；检测到三种新模板时固定返回 422 `unsupported_workflow_for_client`，不得把条件工作流悄悄降为一次提醒。

- [ ] **步骤 4：运行 API 与旧客户端回归测试确认 GREEN。**

```bash
.venv/bin/python -m pytest backend/tests/workflows/api/test_workflow_drafts.py backend/tests/reminders/api/test_text_drafts.py backend/tests/reminders/api/test_voice_drafts.py -q
```

- [ ] **步骤 5：提交。**

```bash
git add backend/apps/workflows backend/apps/reminders/api backend/config/urls.py backend/tests/workflows backend/tests/reminders/api
git commit -m "feat: add typed workflow draft APIs"
```

## 任务 6：完成内核发布门禁与后续拆分

**文件：**
- 修改：`docs/superpowers/specs/2026-08-06-typed-life-assistant-v1-design.md`
- 创建：`docs/superpowers/plans/2026-08-07-workflow-runtime-and-action-center.md`
- 创建：`docs/superpowers/plans/2026-08-07-medication-expiry-workflows.md`
- 创建：`docs/superpowers/plans/2026-08-07-smart-departure-workflow.md`
- 创建：`docs/superpowers/plans/2026-08-07-workflow-ios-client.md`

- [ ] **步骤 1：先增加部署前的迁移和安全回归。**

```bash
.venv/bin/python -m pytest backend/tests/workflows backend/tests/reminders backend/tests/accounts -q
.venv/bin/python backend/manage.py check
.venv/bin/python backend/manage.py makemigrations --check --dry-run
git diff --check
```

预期：所有测试通过；迁移清单干净；未记录用户原文、模型链路或任意可执行节点。

- [ ] **步骤 2：记录内核边界并创建后续独立计划。**

后续 Runtime 计划负责 Dispatcher、Runner、Run/NodeRun、Outbox 和 Action Center；用药/有效期计划负责领域模型、实例、阈值和 OCR 确认编排；智能出门计划负责和风、高德、EventKit 和降级；iOS 计划负责真实 API 仓储、设备回执、本地通知与真机验证。外部 Provider 密钥缺失时只能实现显式 `unavailable`/静态降级，不能伪造实时天气、路线或日历结果。

- [ ] **步骤 3：提交内核验收文档。**

```bash
git add docs/superpowers
git commit -m "docs: plan typed workflow rollout"
```

## 覆盖检查

- Schema、白名单、DAG、失败策略和能力签名对应设计第 6、7、9 节。
- 追问、确认、R0/R1 信任与 R2 强制确认对应第 8 节。
- 兼容迁移和 API 对应第 11、14、20 节。
- Dispatcher、药品、有效期、出门、Outbox、EventKit 和真机验收按设计第 10、12、13、18 节拆到后续独立计划，避免在本内核变更中留下假实现。
