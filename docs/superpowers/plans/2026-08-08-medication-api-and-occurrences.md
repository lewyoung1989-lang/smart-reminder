# 周期用药 API 与服药实例实施计划

> **面向执行代理：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项完成。步骤使用复选框跟踪。

**目标：** 提供经认证的每日用药计划创建、未来 30 天实例物化和“已服/跳过”状态回写 API。

**架构：** `MedicationPlan` 是健康计划事实来源。创建 API 必须消费当前用户已确认的 `medication_cycle` 工作流草稿，不能由客户端直接绕过 R2 确认。物化服务将计划时区中的本地日期和 `HH:MM` 槽位转换为 UTC，使用稳定索引与幂等键创建实例。动作 API 在事务和行锁内，只允许计划所有者将待处理实例一次性转为 `taken` 或 `skipped`；OCR 和库存不写入此流程。

**技术栈：** Django 5、Django REST Framework、`zoneinfo`、pytest。

---

## 文件边界

| 文件 | 职责 |
| --- | --- |
| `backend/apps/medication/services/occurrences.py` | 本地日历、UTC、30 天窗口和幂等实例。 |
| `backend/apps/medication/api/serializers.py` | 拒绝未知字段的计划与动作输入。 |
| `backend/apps/medication/api/views.py` | 所有者隔离的计划、实例和动作 HTTP 接口。 |
| `backend/apps/medication/api/urls.py` | 用药 API 路由。 |
| `backend/config/urls.py` | 挂载路由，不改旧提醒路径。 |
| `backend/tests/medication/test_occurrences.py` | 时区、窗口和重复物化测试。 |
| `backend/tests/medication/api/test_medication.py` | 创建、隔离、动作幂等和冲突测试。 |

## 任务 1：物化每日实例

- [x] **步骤 1：写失败测试。**

```python
def test_materialize_occurrences_creates_each_local_slot_once(user):
    plan = create_plan(user, schedule_json={"times": ["08:00", "20:30"]})
    now = datetime(2026, 8, 8, 1, tzinfo=timezone.utc)
    assert len(materialize_occurrences(plan, now=now, days=2)) == 4
    assert materialize_occurrences(plan, now=now, days=2) == []
```

- [x] **步骤 2：运行失败测试。**

运行：`../../.venv/bin/python -m pytest backend/tests/medication/test_occurrences.py -q`

预期：因 `materialize_occurrences` 不存在而失败。

- [x] **步骤 3：实现服务。**

```python
def materialize_occurrences(plan, *, now, days=30):
    local_now = now.astimezone(ZoneInfo(plan.timezone))
    for local_day in each_local_day(local_now.date(), days):
        for time_text in plan.schedule_json["times"]:
            scheduled_at = to_utc(local_day, time_text, plan.timezone)
            MedicationOccurrence.objects.get_or_create(
                plan=plan, index=stable_index(scheduled_at),
                defaults={"scheduled_at": scheduled_at, "idempotency_key": stable_key(plan, scheduled_at)},
            )
```

- [x] **步骤 4：运行测试。**

运行：`../../.venv/bin/python -m pytest backend/tests/medication/test_occurrences.py -q`

预期：PASS。

## 任务 2：创建计划并读取自己的实例

- [x] **步骤 1：写失败 API 测试。**

```python
def test_create_plan_materializes_30_day_window(api_client, user, medicine):
    api_client.force_authenticate(user)
    response = api_client.post("/api/v1/medication/plans", {
        "medicine_id": str(medicine.id), "dosage_text": "一次一片",
        "timezone": "Asia/Shanghai", "times": ["08:00", "20:30"],
    }, format="json")
    assert response.status_code == status.HTTP_201_CREATED
    assert MedicationOccurrence.objects.filter(plan_id=response.data["id"]).count() == 60
```

- [x] **步骤 2：运行失败测试。**

运行：`../../.venv/bin/python -m pytest backend/tests/medication/api/test_medication.py::test_create_plan_materializes_30_day_window -q`

预期：404。

- [x] **步骤 3：实现认证端点。**

```python
with transaction.atomic():
    medicine = MedicineItem.objects.get(id=data["medicine_id"], owner=request.user)
    plan = MedicationPlan(owner=request.user, medicine=medicine, **plan_fields(data))
    plan.full_clean()
    plan.save()
    materialize_occurrences(plan, now=timezone.now())
```

路由为 `medication/plans`；药品不存在或不属于用户时返回校验错误，不泄露资源。

- [x] **步骤 4：运行 API 测试。**

运行：`../../.venv/bin/python -m pytest backend/tests/medication/api/test_medication.py -q`

预期：PASS，包含跨用户药品不可创建与只读取自己实例。

## 任务 3：记录已服或跳过

- [x] **步骤 1：写失败测试。**

```python
def test_mark_taken_is_idempotent(api_client, user, occurrence):
    api_client.force_authenticate(user)
    url = f"/api/v1/medication/occurrences/{occurrence.id}/actions"
    assert api_client.post(url, {"action": "taken"}, format="json").status_code == 200
    assert api_client.post(url, {"action": "taken"}, format="json").status_code == 200
    assert IntakeEvent.objects.filter(occurrence=occurrence).count() == 1
```

- [x] **步骤 2：运行失败测试。**

运行：`../../.venv/bin/python -m pytest backend/tests/medication/api/test_medication.py::test_mark_taken_is_idempotent -q`

预期：404。

- [x] **步骤 3：实现行锁动作。**

```python
occurrence = MedicationOccurrence.objects.select_for_update().get(
    id=occurrence_id, plan__owner=request.user
)
if occurrence.status == "pending":
    occurrence.status, occurrence.acted_at = action, timezone.now()
    occurrence.save(update_fields=["status", "acted_at"])
    IntakeEvent.objects.create(occurrence=occurrence, user=request.user, action=action)
elif occurrence.status != action:
    return Response({"code": "medication_occurrence_already_actioned"}, status=409)
```

不得扣库存、不得接收客户端 `acted_at`、不得把 `missed` 改为已服或跳过。

- [x] **步骤 4：运行回归。**

运行：`../../.venv/bin/python -m pytest backend/tests/medication -q`

预期：PASS。

## 任务 4：审阅与提交

- [x] **步骤 1：运行门禁。**

运行：`../../.venv/bin/python -m pytest backend/tests/medication backend/tests/workflows backend/tests/medicines -q && ../../.venv/bin/python backend/manage.py check && ../../.venv/bin/python backend/manage.py makemigrations --check --dry-run && git diff --check`

预期：全部通过，无新迁移。

- [x] **步骤 2：审阅安全边界。**

逐项确认：所有 API 均认证；查询和动作均过滤 `plan__owner=request.user`；计划调用 `full_clean()`；实例生成 30 天；动作持有行锁且只有一条 `IntakeEvent`；未修改 OCR 或库存代码。

- [x] **步骤 3：提交。**

运行：`git add backend/apps/medication backend/config/urls.py backend/tests/medication && git commit -m "feat: add medication occurrence APIs"`
