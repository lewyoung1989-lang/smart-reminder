from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class Schedule(BaseModel):
    type: Literal["once"] = "once"
    local_datetime: datetime
    timezone: str


class RainCondition(BaseModel):
    type: Literal["precipitation_probability"] = "precipitation_probability"
    window_minutes: int = Field(ge=15, le=4_320)
    operator: Literal[">="] = ">="
    value: int = Field(ge=0, le=100)


class Precheck(BaseModel):
    minutes_before: int = Field(ge=0, le=1_440)
    condition: RainCondition


class ReminderDraftData(BaseModel):
    intent: Literal["create_reminder"] = "create_reminder"
    title: str = Field(min_length=1, max_length=200)
    schedule: Schedule | None
    precheck: Precheck | None
    severity: Literal["alarm", "notification"]
    condition_met_message: str | None = Field(default=None, max_length=500)
    ambiguities: list[str] = Field(default_factory=list)
