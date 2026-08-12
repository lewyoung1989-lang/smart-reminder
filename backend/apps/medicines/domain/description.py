from datetime import date

from pydantic import BaseModel, ConfigDict, Field, model_validator


class MedicineDescriptionDraft(BaseModel):
    model_config = ConfigDict(extra="forbid")

    medicine_name: str | None = Field(default=None, min_length=1, max_length=200)
    specification: str | None = Field(default=None, min_length=1, max_length=120)
    batch_number: str | None = Field(default=None, min_length=1, max_length=100)
    production_date: date | None = None
    expiry_date: date | None = None
    quantity: int | None = Field(default=None, ge=1, le=9999)
    ambiguities: list[str] = Field(default_factory=list, max_length=10)

    @model_validator(mode="after")
    def validate_dates(self):
        if (
            self.production_date is not None
            and self.expiry_date is not None
            and self.expiry_date < self.production_date
        ):
            raise ValueError("expiry_date cannot precede production_date")
        if self.medicine_name is None and not self.ambiguities:
            raise ValueError("missing medicine name must be explained")
        return self
