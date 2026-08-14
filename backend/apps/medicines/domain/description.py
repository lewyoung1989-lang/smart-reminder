from datetime import date
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class MedicineDescriptionDraft(BaseModel):
    model_config = ConfigDict(extra="forbid")

    medicine_name: str | None = Field(default=None, min_length=1, max_length=200)
    specification: str | None = Field(default=None, min_length=1, max_length=120)
    manufacturer: str | None = Field(default=None, min_length=1, max_length=200)
    batch_number: str | None = Field(default=None, min_length=1, max_length=100)
    production_date: date | None = None
    expiry_date: date | None = None
    quantity: int | None = Field(default=None, ge=1, le=9999)
    package_unit: str | None = Field(default=None, min_length=1, max_length=16)
    units_per_package: Decimal | None = Field(default=None, gt=0, le=9999999)
    unit_name: str | None = Field(default=None, min_length=1, max_length=16)
    loose_units: Decimal | None = Field(default=None, ge=0, le=999999999)
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
        precision_values = (
            self.package_unit is not None,
            self.units_per_package is not None,
            self.unit_name is not None,
        )
        if any(precision_values) and not all(precision_values):
            raise ValueError("precise package fields must be supplied together")
        if self.loose_units is not None and self.units_per_package is None:
            raise ValueError("loose units require precise package fields")
        if (
            self.loose_units is not None
            and self.units_per_package is not None
            and self.loose_units >= self.units_per_package
        ):
            raise ValueError("loose units must be less than units per package")
        return self
