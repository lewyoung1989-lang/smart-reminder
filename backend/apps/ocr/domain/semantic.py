from pydantic import BaseModel, ConfigDict, Field


class StrictSchema(BaseModel):
    model_config = ConfigDict(extra="forbid")


class EvidenceField(StrictSchema):
    value: str = Field(min_length=1, max_length=200)
    line_ids: list[str] = Field(min_length=1, max_length=3)


class MedicineSemanticData(StrictSchema):
    medicine_name: EvidenceField | None
    specification: EvidenceField | None
    manufacturer: EvidenceField | None = None
    batch_number: EvidenceField | None
    production_date_text: EvidenceField | None
    expiry_date_text: EvidenceField | None
    ambiguities: list[str] = Field(default_factory=list, max_length=10)
