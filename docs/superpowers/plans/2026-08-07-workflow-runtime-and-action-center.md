# 工作流运行时与行动中心实施计划

**目标：** 为已确认的 WorkflowSpec 增加确定性调度、运行记录、通知 Outbox 和行动中心读取接口。

**范围：** 新增 NodeRun、NotificationOutbox、Dispatcher 和 Runner；Dispatcher 以事务和唯一幂等键创建 WorkflowRun，再投递 Celery。Runner 只按注册组件执行，Provider 失败产生 `degraded` 或 `unavailable` 状态并写入 Outbox。

**验收：** 重复调度不产生重复 Run；失败 Source 不会静默结束；Outbox 可重试且去重；行动中心只显示当前用户的待决策与接下来事项。

**任务：**

- [ ] 先为 Rule 级 Dispatcher 写并发、幂等和 next_run_at 推进失败测试。
- [ ] 创建 NodeRun、NotificationOutbox 与迁移，使用唯一 idempotency_key。
- [ ] 实现 select_for_update(skip_locked) 分批调度和 Celery 投递。
- [ ] 实现注册节点 Runner、固定 fallback 与故障通知。
- [ ] 提供认证的行动中心读接口，并增加 API/Outbox 回归测试。
- [ ] 运行后端全量测试、Celery 集成测试与迁移检查。
