from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class StrictSchema(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Schedule(StrictSchema):
    type: Literal["once"] = "once"
    local_datetime: datetime
    timezone: str


class RainCondition(StrictSchema):
    type: Literal["precipitation_probability"] = "precipitation_probability"
    window_minutes: int = Field(ge=15, le=4_320)
    operator: Literal[">="] = ">="
    value: int = Field(ge=0, le=100)


class Precheck(StrictSchema):
    minutes_before: int = Field(ge=0, le=1_440)
    condition: RainCondition


class ReminderDraftData(StrictSchema):
    intent: Literal["create_reminder"] = "create_reminder"
    title: str = Field(min_length=1, max_length=200)
    schedule: Schedule | None
    precheck: Precheck | None
    severity: Literal["alarm", "notification"]
    condition_met_message: str | None = Field(default=None, max_length=500)
    ambiguities: list[str] = Field(default_factory=list)
