from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, model_validator

from apps.workflows.domain.schemas import TaskSpec

from .schemas import ReminderDraftData


class NaturalLanguageDraft(BaseModel):
    """模型只选择受支持的草稿类型，不生成可执行工作流节点。"""

    model_config = ConfigDict(extra="forbid")

    draft_type: Literal["reminder", "workflow"]
    reminder: ReminderDraftData | None = None
    workflow: TaskSpec | None = None

    @model_validator(mode="after")
    def exactly_one_draft(self):
        if self.draft_type == "reminder":
            if self.reminder is None or self.workflow is not None:
                raise ValueError("reminder draft_type requires only reminder")
        elif self.workflow is None or self.reminder is not None:
            raise ValueError("workflow draft_type requires only workflow")
        return self
