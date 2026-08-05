# Medicine OCR Accuracy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提高药盒药名和日期候选准确率，同时增加默认关闭的 OCR 原文调试日志，并保证 DeepSeek 只能引用 OCR 证据、失败时安全回退本地规则。

**Architecture:** OCR Worker 对有效期照片生成原图与增强图，RapidOCR 识别后在内存中去重、按布局排序并生成相邻行窗口。本地规则负责确定性日期和候选过滤，DeepSeek 负责有证据约束的药名及缺失字段判断，最终由本地代码验证和合并；原文不持久化，调试日志必须显式开启。

**Tech Stack:** Python 3.13、Django 5.2、Celery 5.5、RapidOCR 3.9.2、OpenCV、NumPy、Pydantic、DeepSeek OpenAI-compatible API、pytest、Docker Compose、journald。

---

## File Map

- Create `backend/apps/ocr/services/debug_logging.py`: 清理并按开关打印 OCR 行。
- Modify `backend/config/settings.py`: OCR 调试、语义 provider 和超时配置。
- Modify `deploy/tencent/env.production.example`: 列出非敏感 OCR 配置默认值。
- Modify `deploy/tencent/compose.production.yaml`: 把 OCR 配置传入 OCR Worker。
- Modify `deploy/tencent/scripts/check_env.py`: 校验布尔开关和语义 provider。
- Create `backend/tests/ocr/services/test_debug_logging.py`: 调试日志隐私边界测试。
- Modify `backend/apps/ocr/services/image_validation.py`: 生成有效期增强图。
- Create `backend/tests/ocr/services/test_image_validation.py`: 图像版本测试。
- Create `backend/apps/ocr/domain/layout.py`: 多版本去重、布局排序和相邻行窗口。
- Create `backend/tests/ocr/domain/test_layout.py`: 坐标与窗口测试。
- Modify `backend/apps/ocr/domain/medicine_parser.py`: 日期格式和药名候选规则。
- Modify `backend/tests/ocr/domain/test_medicine_parser.py`: 真实失败形态的回归测试。
- Create `backend/apps/ocr/domain/semantic.py`: DeepSeek 严格输出 Schema 和证据类型。
- Create `backend/apps/ocr/providers/deepseek.py`: 药盒语义 provider。
- Create `backend/tests/ocr/providers/test_deepseek.py`: Prompt、Schema 和证据校验测试。
- Create `backend/apps/ocr/services/candidate_resolver.py`: 本地结果与语义结果合并。
- Create `backend/apps/ocr/providers/semantic_factory.py`: 可配置语义 provider 工厂。
- Create `backend/tests/ocr/services/test_candidate_resolver.py`: 语义覆盖与失败回退测试。
- Modify `backend/apps/ocr/services/job_runner.py`: 串联图像版本、布局、日志和字段解析。
- Modify `backend/apps/ocr/tasks.py`: 注入语义 provider 并安全回退。
- Modify `backend/tests/ocr/services/test_job_runner.py`: 完整管线测试。
- Modify `backend/tests/ocr/test_tasks.py`: 任务回退和日志测试。
- Modify `backend/tests/ocr/test_settings.py`: 新配置默认值测试。
- Modify `backend/tests/deployment/test_env_contract.py`: 生产环境契约测试。
- Modify `backend/tests/deployment/test_compose_contract.py`: OCR Worker 环境透传测试。

### Task 1: Add Opt-In OCR Text Debug Logging

**Files:**
- Create: `backend/apps/ocr/services/debug_logging.py`
- Create: `backend/tests/ocr/services/test_debug_logging.py`
- Modify: `backend/config/settings.py`
- Modify: `backend/apps/ocr/services/job_runner.py:30-38`
- Modify: `backend/tests/ocr/test_settings.py`

- [ ] **Step 1: Write failing tests for disabled and sanitized logging**

```python
# backend/tests/ocr/services/test_debug_logging.py
import logging

from apps.ocr.domain.types import OCRDocument, OCRLine
from apps.ocr.services.debug_logging import log_ocr_documents


def _document(text):
    return OCRDocument(
        role="expiry",
        lines=(
            OCRLine(
                ((0, 0), (20, 0), (20, 10), (0, 10)),
                text,
                0.98214,
            ),
        ),
    )


def test_debug_logging_is_silent_when_disabled(caplog):
    with caplog.at_level(logging.INFO):
        log_ocr_documents(
            "job-1",
            (_document("有效期至2028.05"),),
            enabled=False,
        )

    assert "有效期至2028.05" not in caplog.text


def test_debug_logging_sanitizes_and_truncates_text(caplog):
    value = "有效期\n至\t" + "2" * 250

    with caplog.at_level(logging.INFO):
        log_ocr_documents("job-1", (_document(value),), enabled=True)

    assert "job_id=job-1 role=expiry line=0 score=0.9821" in caplog.text
    assert "\n至" not in caplog.text
    logged_value = caplog.text.split('text="', 1)[1].split('"', 1)[0]
    assert len(logged_value) == 200
```

- [ ] **Step 2: Run the logging tests and verify RED**

Run:

```bash
.venv/bin/pytest backend/tests/ocr/services/test_debug_logging.py -q
```

Expected: collection fails because `apps.ocr.services.debug_logging` does not exist.

- [ ] **Step 3: Implement the isolated logging helper**

```python
# backend/apps/ocr/services/debug_logging.py
import logging
import re

from apps.ocr.domain.types import OCRDocument


logger = logging.getLogger(__name__)
CONTROL_CHARACTERS = re.compile(r"[\x00-\x1f\x7f]+")
MAX_LOGGED_TEXT_LENGTH = 200


def _safe_text(value: str) -> str:
    return CONTROL_CHARACTERS.sub(" ", value).strip()[:MAX_LOGGED_TEXT_LENGTH]


def log_ocr_documents(
    job_id,
    documents: tuple[OCRDocument, ...],
    *,
    enabled: bool,
) -> None:
    if not enabled:
        return
    for document in documents:
        for index, line in enumerate(document.lines):
            logger.info(
                'ocr_text job_id=%s role=%s line=%d score=%.4f text="%s"',
                job_id,
                document.role,
                index,
                line.score,
                _safe_text(line.text),
            )
```

- [ ] **Step 4: Add the default-off setting and call the helper**

Append to `backend/config/settings.py`:

```python
OCR_DEBUG_TEXT_LOGGING = (
    os.environ.get("OCR_DEBUG_TEXT_LOGGING", "false").lower() == "true"
)
```

After `documents` are complete in `backend/apps/ocr/services/job_runner.py`:

```python
from django.conf import settings

from .debug_logging import log_ocr_documents

# after OCR documents are built
log_ocr_documents(
    job_id,
    tuple(documents),
    enabled=settings.OCR_DEBUG_TEXT_LOGGING,
)
```

Add to `backend/tests/ocr/test_settings.py`:

```python
assert settings.OCR_DEBUG_TEXT_LOGGING is False
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
.venv/bin/pytest \
  backend/tests/ocr/services/test_debug_logging.py \
  backend/tests/ocr/test_settings.py -q
```

Expected: all selected tests pass and the default path emits no recognized text.

- [ ] **Step 6: Commit the logging boundary**

```bash
git add backend/apps/ocr/services/debug_logging.py \
  backend/apps/ocr/services/job_runner.py \
  backend/config/settings.py \
  backend/tests/ocr/services/test_debug_logging.py \
  backend/tests/ocr/test_settings.py
git commit -m "feat: add opt-in OCR text diagnostics"
```

### Task 2: Generate Expiry Image Variants

**Files:**
- Modify: `backend/apps/ocr/services/image_validation.py`
- Create: `backend/tests/ocr/services/test_image_validation.py`

- [ ] **Step 1: Write failing tests for front and expiry variants**

```python
# backend/tests/ocr/services/test_image_validation.py
import cv2
import numpy as np
import pytest

from apps.ocr.services.image_validation import (
    ImageValidationError,
    prepare_ocr_variants,
)


def _jpeg():
    image = np.full((80, 160, 3), 150, dtype=np.uint8)
    cv2.putText(
        image,
        "202801",
        (10, 50),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (130, 130, 130),
        2,
    )
    ok, encoded = cv2.imencode(".jpg", image)
    assert ok
    return encoded.tobytes()


def test_front_uses_only_normalized_image():
    variants = prepare_ocr_variants(_jpeg(), role="front")
    assert len(variants) == 1
    assert cv2.imdecode(np.frombuffer(variants[0], np.uint8), cv2.IMREAD_COLOR) is not None


def test_expiry_adds_contrast_enhanced_variant():
    variants = prepare_ocr_variants(_jpeg(), role="expiry")
    assert len(variants) == 2
    assert variants[0] != variants[1]


def test_expiry_keeps_original_when_enhancement_fails(monkeypatch):
    def fail_enhancement(image):
        raise cv2.error("enhancement_failed")

    monkeypatch.setattr(
        "apps.ocr.services.image_validation._enhance_expiry",
        fail_enhancement,
    )
    variants = prepare_ocr_variants(_jpeg(), role="expiry")
    assert len(variants) == 1


def test_invalid_image_keeps_fixed_error_code():
    with pytest.raises(ImageValidationError, match="image_decode_failed"):
        prepare_ocr_variants(b"not-an-image", role="expiry")
```

- [ ] **Step 2: Run the image tests and verify RED**

Run:

```bash
.venv/bin/pytest backend/tests/ocr/services/test_image_validation.py -q
```

Expected: import fails because `prepare_ocr_variants` does not exist.

- [ ] **Step 3: Refactor decoding and implement CLAHE enhancement**

Replace the public portion of `backend/apps/ocr/services/image_validation.py` with:

```python
def _decode_and_resize(value: bytes):
    if not value:
        raise ImageValidationError("invalid_image")
    if len(value) > settings.OCR_MAX_IMAGE_BYTES:
        raise ImageValidationError("image_too_large")
    image = cv2.imdecode(np.frombuffer(value, dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise ImageValidationError("image_decode_failed")
    height, width = image.shape[:2]
    longest = max(height, width)
    if longest > settings.OCR_MAX_IMAGE_SIDE:
        scale = settings.OCR_MAX_IMAGE_SIDE / longest
        image = cv2.resize(
            image,
            (round(width * scale), round(height * scale)),
            interpolation=cv2.INTER_AREA,
        )
    return image


def _encode_jpeg(image) -> bytes:
    ok, encoded = cv2.imencode(
        ".jpg",
        image,
        [cv2.IMWRITE_JPEG_QUALITY, 90],
    )
    if not ok:
        raise ImageValidationError("image_encode_failed")
    return encoded.tobytes()


def _enhance_expiry(image):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    contrast = cv2.createCLAHE(
        clipLimit=2.0,
        tileGridSize=(8, 8),
    ).apply(gray)
    blurred = cv2.GaussianBlur(contrast, (0, 0), 1.0)
    return cv2.addWeighted(contrast, 1.5, blurred, -0.5, 0)


def prepare_ocr_variants(value: bytes, *, role: str) -> tuple[bytes, ...]:
    image = _decode_and_resize(value)
    variants = [_encode_jpeg(image)]
    if role == "expiry":
        try:
            variants.append(_encode_jpeg(_enhance_expiry(image)))
        except (cv2.error, ImageValidationError):
            # 增强图是可选输入；规范化原图已经可供 OCR 使用。
            pass
    return tuple(variants)


def validate_and_resize(value: bytes) -> bytes:
    return prepare_ocr_variants(value, role="front")[0]
```

Keep `validate_and_resize` as a compatibility wrapper until `job_runner` switches in Task 6.

- [ ] **Step 4: Run image tests and existing OCR tests**

Run:

```bash
.venv/bin/pytest \
  backend/tests/ocr/services/test_image_validation.py \
  backend/tests/ocr/services/test_job_runner.py -q
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit image preprocessing**

```bash
git add backend/apps/ocr/services/image_validation.py \
  backend/tests/ocr/services/test_image_validation.py
git commit -m "feat: enhance expiry images for OCR"
```

### Task 3: Merge OCR Variants And Build Layout Windows

**Files:**
- Create: `backend/apps/ocr/domain/layout.py`
- Create: `backend/tests/ocr/domain/test_layout.py`

- [ ] **Step 1: Write failing layout tests**

```python
# backend/tests/ocr/domain/test_layout.py
from apps.ocr.domain.layout import build_text_windows, merge_documents
from apps.ocr.domain.types import OCRDocument, OCRLine


def _line(text, y, score=0.90):
    return OCRLine(
        ((0, y), (100, y), (100, y + 10), (0, y + 10)),
        text,
        score,
    )


def test_merge_keeps_highest_score_and_layout_order():
    merged = merge_documents(
        "expiry",
        (
            OCRDocument("expiry", (_line("20280108", 30, 0.80),)),
            OCRDocument(
                "expiry",
                (_line("20280108", 30, 0.97), _line("生产日期", 10, 0.95)),
            ),
        ),
    )
    assert [line.text for line in merged.lines] == ["生产日期", "20280108"]
    assert merged.lines[1].score == 0.97


def test_adjacent_label_and_value_create_one_window():
    document = OCRDocument(
        "expiry",
        (_line("生产日期", 10), _line("20280108", 25)),
    )
    windows = build_text_windows(document)
    assert any(window.text == "生产日期20280108" for window in windows)
    assert any(window.line_indices == (0, 1) for window in windows)


def test_distant_lines_are_not_joined():
    document = OCRDocument(
        "expiry",
        (_line("生产日期", 10), _line("20280108", 100)),
    )
    assert all(len(window.line_indices) == 1 for window in build_text_windows(document))
```

- [ ] **Step 2: Run the layout tests and verify RED**

Run:

```bash
.venv/bin/pytest backend/tests/ocr/domain/test_layout.py -q
```

Expected: import fails because `apps.ocr.domain.layout` does not exist.

- [ ] **Step 3: Implement merge and coordinate-aware windows**

```python
# backend/apps/ocr/domain/layout.py
from dataclasses import dataclass
import re

from .types import OCRDocument, OCRLine


@dataclass(frozen=True)
class OCRTextWindow:
    text: str
    score: float
    line_indices: tuple[int, ...]


def _normalized(value: str) -> str:
    return re.sub(r"\s+", "", value).casefold()


def _top(line: OCRLine) -> float:
    return min(point[1] for point in line.box)


def _bottom(line: OCRLine) -> float:
    return max(point[1] for point in line.box)


def _left(line: OCRLine) -> float:
    return min(point[0] for point in line.box)


def _height(line: OCRLine) -> float:
    return max(1.0, _bottom(line) - _top(line))


def merge_documents(
    role: str,
    documents: tuple[OCRDocument, ...],
) -> OCRDocument:
    best = {}
    for document in documents:
        for line in document.lines:
            key = _normalized(line.text)
            if key and (key not in best or line.score > best[key].score):
                best[key] = line
    ordered = sorted(best.values(), key=lambda line: (_top(line), _left(line)))
    return OCRDocument(role=role, lines=tuple(ordered))


def build_text_windows(document: OCRDocument) -> tuple[OCRTextWindow, ...]:
    windows = []
    for index, line in enumerate(document.lines):
        windows.append(OCRTextWindow(line.text, line.score, (index,)))
        if index + 1 >= len(document.lines):
            continue
        following = document.lines[index + 1]
        gap = _top(following) - _bottom(line)
        if gap <= max(_height(line), _height(following)) * 2.5:
            windows.append(
                OCRTextWindow(
                    f"{line.text}{following.text}",
                    min(line.score, following.score),
                    (index, index + 1),
                )
            )
    return tuple(windows)
```

- [ ] **Step 4: Run the layout tests and verify GREEN**

Run:

```bash
.venv/bin/pytest backend/tests/ocr/domain/test_layout.py -q
```

Expected: all three tests pass.

- [ ] **Step 5: Commit the layout layer**

```bash
git add backend/apps/ocr/domain/layout.py \
  backend/tests/ocr/domain/test_layout.py
git commit -m "feat: reconstruct OCR text layout"
```

### Task 4: Improve Deterministic Medicine And Date Parsing

**Files:**
- Modify: `backend/apps/ocr/domain/medicine_parser.py`
- Modify: `backend/tests/ocr/domain/test_medicine_parser.py`

- [ ] **Step 1: Add regression tests for observed failures**

Append to `backend/tests/ocr/domain/test_medicine_parser.py`:

```python
def test_rejects_composition_sentence_as_medicine_name():
    result = extract_candidates(
        (
            OCRDocument(
                "front",
                (
                    line("每片中阿莫西林含量0.25g", 0.99),
                    line("阿莫西林胶囊", 0.94),
                ),
            ),
        )
    )
    assert result.medicine_name == "阿莫西林胶囊"


def test_rejects_bare_dosage_form_as_medicine_name():
    result = extract_candidates(
        (OCRDocument("front", (line("鼻喷雾剂"),)),)
    )
    assert result.medicine_name == ""


def test_parses_dates_split_across_adjacent_lines():
    result = extract_candidates(
        (
            OCRDocument(
                "expiry",
                (
                    line("生产日期"),
                    line("20260108"),
                    line("有效期至"),
                    line("202805"),
                ),
            ),
        )
    )
    assert result.production_date == date(2026, 1, 8)
    assert result.expiry_date == date(2028, 5, 31)


def test_compact_unlabelled_number_is_not_promoted():
    result = extract_candidates(
        (OCRDocument("expiry", (line("20260108"),)),)
    )
    assert result.production_date is None
    assert result.expiry_date is None


def test_conflicting_dates_are_left_for_user_confirmation():
    result = extract_candidates(
        (
            OCRDocument(
                "expiry",
                (
                    line("生产日期20290108"),
                    line("有效期至202805"),
                ),
            ),
        )
    )
    assert result.production_date is None
    assert result.expiry_date is None
```

- [ ] **Step 2: Run the parser tests and verify RED**

Run:

```bash
.venv/bin/pytest backend/tests/ocr/domain/test_medicine_parser.py -q
```

Expected: the composition sentence, bare dosage form and split compact dates fail.

- [ ] **Step 3: Add compact dates, windows and exclusion rules**

Update constants and extraction helpers in `medicine_parser.py`:

```python
from .layout import build_text_windows

DATE_COMPACT = re.compile(
    r"(?<!\d)(20\d{2})(0[1-9]|1[0-2])([0-3]\d)?(?!\d)"
)
NAME_EXCLUSION = re.compile(
    r"每(?:片|粒|袋|支)中|含量|成份|成分|用法|批准文号|请仔细阅读|适应症"
)
BARE_DOSAGE_FORM = re.compile(
    r"^(?:片剂|胶囊剂|颗粒剂|口服液|滴丸|喷雾剂|鼻喷雾剂|软膏|乳膏|糖浆)$"
)
```

Replace `_labelled_date` and the extraction loop with the following structure:

```python
def parse_date_value(text: str, *, allow_month_year: bool) -> date | None:
    ymd = DATE_YMD.search(text)
    if ymd:
        year = int(ymd.group(1))
        month = int(ymd.group(2))
        if ymd.group(3):
            try:
                return date(year, month, int(ymd.group(3)))
            except ValueError:
                return None
        return _month_end(year, month) if allow_month_year else None
    compact = DATE_COMPACT.search(re.sub(r"\s+", "", text))
    if compact:
        year = int(compact.group(1))
        month = int(compact.group(2))
        if compact.group(3):
            try:
                return date(year, month, int(compact.group(3)))
            except ValueError:
                return None
        return _month_end(year, month) if allow_month_year else None
    if allow_month_year:
        month_year = DATE_MY.search(text)
        if month_year:
            return _month_end(
                2000 + int(month_year.group(2)),
                int(month_year.group(1)),
            )
    return None


def _labelled_date(
    text: str,
    label: re.Pattern,
    *,
    allow_month_year: bool,
) -> date | None:
    match = label.search(text)
    if not match:
        return None
    return parse_date_value(
        text[match.end() :],
        allow_month_year=allow_month_year,
    )


def _medicine_name(document: OCRDocument) -> tuple[str, float] | None:
    candidates = []
    for line in document.lines:
        text = re.sub(r"\s+", "", line.text)
        if (
            DOSAGE_FORM.search(text)
            and not EXPIRY_LABEL.search(text)
            and not PRODUCTION_LABEL.search(text)
            and not NAME_EXCLUSION.search(text)
            and not BARE_DOSAGE_FORM.fullmatch(text)
        ):
            xs = [point[0] for point in line.box]
            ys = [point[1] for point in line.box]
            area = (max(xs) - min(xs)) * (max(ys) - min(ys))
            candidates.append(((area, line.score, len(text)), text, line.score))
    selected = max(candidates, key=lambda value: value[0], default=None)
    return None if selected is None else (selected[1], selected[2])


def extract_candidates(
    documents: tuple[OCRDocument, ...],
) -> MedicineCandidates:
    values = {
        "medicine_name": "",
        "specification": "",
        "batch_number": "",
    }
    confidence = {}
    production_date = None
    expiry_date = None

    for document in documents:
        if document.role == "front" and not values["medicine_name"]:
            selected_name = _medicine_name(document)
            if selected_name is not None:
                values["medicine_name"], confidence["medicine_name"] = (
                    selected_name
                )

        for window in build_text_windows(document):
            text = re.sub(r"\s+", "", window.text)
            specification = SPEC.search(text)
            if specification and not values["specification"]:
                values["specification"] = specification.group(1)
                confidence["specification"] = window.score

            batch = BATCH.search(text)
            if batch and not values["batch_number"]:
                values["batch_number"] = batch.group(1)
                confidence["batch_number"] = window.score

            if production_date is None:
                production_date = _labelled_date(
                    text,
                    PRODUCTION_LABEL,
                    allow_month_year=False,
                )
                if production_date is not None:
                    confidence["production_date"] = window.score

            if expiry_date is None:
                expiry_date = _labelled_date(
                    text,
                    EXPIRY_LABEL,
                    allow_month_year=True,
                )
                if expiry_date is not None:
                    confidence["expiry_date"] = window.score

    if production_date and expiry_date and production_date > expiry_date:
        production_date = None
        expiry_date = None
        confidence.pop("production_date", None)
        confidence.pop("expiry_date", None)

    return MedicineCandidates(
        **values,
        production_date=production_date,
        expiry_date=expiry_date,
        confidence=confidence,
    )
```

- [ ] **Step 4: Run parser and layout tests**

Run:

```bash
.venv/bin/pytest \
  backend/tests/ocr/domain/test_medicine_parser.py \
  backend/tests/ocr/domain/test_layout.py -q
```

Expected: all selected tests pass, including all pre-existing date formats.

- [ ] **Step 5: Commit deterministic parsing improvements**

```bash
git add backend/apps/ocr/domain/medicine_parser.py \
  backend/tests/ocr/domain/test_medicine_parser.py
git commit -m "feat: improve medicine OCR field rules"
```

### Task 5: Add Evidence-Constrained DeepSeek Parsing

**Files:**
- Create: `backend/apps/ocr/domain/semantic.py`
- Create: `backend/apps/ocr/providers/deepseek.py`
- Create: `backend/tests/ocr/providers/test_deepseek.py`

- [ ] **Step 1: Write failing provider tests**

```python
# backend/tests/ocr/providers/test_deepseek.py
import json
import pytest

from apps.ocr.domain.types import OCRDocument, OCRLine
from apps.ocr.providers.deepseek import (
    DeepSeekMedicineError,
    DeepSeekMedicineProvider,
    UrllibJsonTransport,
)


class RecordingTransport:
    def __init__(self, response):
        self.response = response
        self.payload = None

    def post_json(self, url, *, headers, payload, timeout):
        self.payload = payload
        return self.response


def _line(text, score=0.95):
    return OCRLine(((0, 0), (1, 0), (1, 1), (0, 1)), text, score)


def _completion(value):
    return {
        "choices": [
            {"message": {"content": json.dumps(value, ensure_ascii=False)}}
        ]
    }


def test_provider_returns_only_fields_supported_by_evidence():
    transport = RecordingTransport(
        _completion(
            {
                "medicine_name": {
                    "value": "阿莫西林胶囊",
                    "line_ids": ["front:1"],
                },
                "specification": None,
                "batch_number": None,
                "production_date_text": None,
                "expiry_date_text": {
                    "value": "202805",
                    "line_ids": ["expiry:1"],
                },
                "ambiguities": [],
            }
        )
    )
    provider = DeepSeekMedicineProvider(
        api_key="test-key",
        transport=transport,
    )
    result = provider.parse(
        (
            OCRDocument(
                "front",
                (_line("每片中阿莫西林含量0.25g"), _line("阿莫西林胶囊")),
            ),
            OCRDocument("expiry", (_line("有效期至"), _line("202805"))),
        )
    )
    assert result.medicine_name.value == "阿莫西林胶囊"
    assert result.expiry_date_text.value == "202805"
    assert transport.payload["response_format"] == {"type": "json_object"}
    assert "禁止猜测" in transport.payload["messages"][0]["content"]


def test_provider_drops_a_field_not_present_in_evidence():
    transport = RecordingTransport(
        _completion(
            {
                "medicine_name": {
                    "value": "图片中不存在的药名",
                    "line_ids": ["front:0"],
                },
                "specification": None,
                "batch_number": None,
                "production_date_text": None,
                "expiry_date_text": None,
                "ambiguities": [],
            }
        )
    )
    provider = DeepSeekMedicineProvider(api_key="test-key", transport=transport)
    result = provider.parse(
        (OCRDocument("front", (_line("阿莫西林胶囊"),)),)
    )
    assert result.medicine_name is None


def test_provider_drops_evidence_from_non_adjacent_lines():
    transport = RecordingTransport(
        _completion(
            {
                "medicine_name": {
                    "value": "阿莫西林胶囊",
                    "line_ids": ["front:0", "front:2"],
                },
                "specification": None,
                "batch_number": None,
                "production_date_text": None,
                "expiry_date_text": None,
                "ambiguities": [],
            }
        )
    )
    provider = DeepSeekMedicineProvider(api_key="test-key", transport=transport)
    result = provider.parse(
        (
            OCRDocument(
                "front",
                (_line("阿莫西林"), _line("说明文字"), _line("胶囊")),
            ),
        )
    )
    assert result.medicine_name is None


def test_provider_rejects_unknown_json_fields_without_leaking_response():
    transport = RecordingTransport(
        _completion(
            {
                "medicine_name": None,
                "specification": None,
                "batch_number": None,
                "production_date_text": None,
                "expiry_date_text": None,
                "ambiguities": [],
                "unexpected": "private-upstream-response",
            }
        )
    )
    provider = DeepSeekMedicineProvider(api_key="test-key", transport=transport)

    with pytest.raises(DeepSeekMedicineError) as captured:
        provider.parse((OCRDocument("front", (_line("阿莫西林胶囊"),)),))

    assert str(captured.value) == "medicine_semantic_invalid_response"
    assert "private-upstream-response" not in str(captured.value)


def test_transport_wraps_timeout_without_leaking_authorization(monkeypatch):
    def timeout(*args, **kwargs):
        raise TimeoutError("private-upstream-detail")

    monkeypatch.setattr("apps.ocr.providers.deepseek.urlopen", timeout)
    transport = UrllibJsonTransport()

    with pytest.raises(DeepSeekMedicineError) as captured:
        transport.post_json(
            "https://api.deepseek.com/chat/completions",
            headers={"Authorization": "Bearer private-api-key"},
            payload={},
            timeout=1,
        )

    assert str(captured.value) == "medicine_semantic_request_failed"
    assert "private-api-key" not in str(captured.value)
    assert "private-upstream-detail" not in str(captured.value)
```

- [ ] **Step 2: Run provider tests and verify RED**

Run:

```bash
.venv/bin/pytest backend/tests/ocr/providers/test_deepseek.py -q
```

Expected: import fails because the semantic types and provider do not exist.

- [ ] **Step 3: Add strict semantic types**

```python
# backend/apps/ocr/domain/semantic.py
from pydantic import BaseModel, ConfigDict, Field


class StrictSchema(BaseModel):
    model_config = ConfigDict(extra="forbid")


class EvidenceField(StrictSchema):
    value: str = Field(min_length=1, max_length=200)
    line_ids: list[str] = Field(min_length=1, max_length=3)


class MedicineSemanticData(StrictSchema):
    medicine_name: EvidenceField | None
    specification: EvidenceField | None
    batch_number: EvidenceField | None
    production_date_text: EvidenceField | None
    expiry_date_text: EvidenceField | None
    ambiguities: list[str] = Field(default_factory=list, max_length=10)
```

- [ ] **Step 4: Implement the OpenAI-compatible provider and evidence filter**

Create `backend/apps/ocr/providers/deepseek.py`:

```python
import json
from typing import Any, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from pydantic import ValidationError

from apps.ocr.domain.semantic import EvidenceField, MedicineSemanticData
from apps.ocr.domain.types import OCRDocument


class DeepSeekMedicineError(Exception):
    pass


class JsonTransport(Protocol):
    def post_json(
        self,
        url: str,
        *,
        headers: dict[str, str],
        payload: dict[str, Any],
        timeout: float,
    ) -> dict[str, Any]:
        raise NotImplementedError


class UrllibJsonTransport:
    def post_json(self, url, *, headers, payload, timeout):
        request = Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
            raise DeepSeekMedicineError("medicine_semantic_request_failed") from error


class DeepSeekMedicineProvider:
    FIELD_NAMES = (
        "medicine_name",
        "specification",
        "batch_number",
        "production_date_text",
        "expiry_date_text",
    )

    def __init__(
        self,
        *,
        api_key: str,
        base_url: str = "https://api.deepseek.com",
        model: str = "deepseek-v4-flash",
        timeout_seconds: float = 8,
        transport: JsonTransport | None = None,
    ):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.transport = transport or UrllibJsonTransport()

    @staticmethod
    def _supported(
        field: EvidenceField | None,
        lines: dict[str, str],
    ) -> EvidenceField | None:
        if field is None or any(
            line_id not in lines for line_id in field.line_ids
        ):
            return None
        references = [line_id.rsplit(":", 1) for line_id in field.line_ids]
        roles = {role for role, index in references}
        try:
            indices = [int(index) for role, index in references]
        except ValueError:
            return None
        if len(roles) != 1 or indices != list(
            range(indices[0], indices[0] + len(indices))
        ):
            return None
        evidence = "".join(lines[line_id] for line_id in field.line_ids)
        normalized_evidence = "".join(evidence.split())
        normalized_value = "".join(field.value.split())
        return field if normalized_value in normalized_evidence else None

    @staticmethod
    def _system_prompt() -> str:
        schema = json.dumps(
            MedicineSemanticData.model_json_schema(),
            ensure_ascii=False,
        )
        return (
            "你是药盒 OCR 字段整理器，只能引用输入行中的原文。"
            "药名必须是具体药品名称，不能选择成分说明、用法、含量句或纯剂型。"
            "日期字段只返回图片中的原始日期文字，禁止补全、推断或改写。"
            "每个非空字段必须给出 line_ids；无法确定时返回 null 并写入 ambiguities。"
            "只输出符合给定 JSON Schema 的 JSON 对象，禁止 Markdown，禁止猜测。"
            f"输出必须符合此 JSON Schema：{schema}"
        )

    def parse(
        self,
        documents: tuple[OCRDocument, ...],
    ) -> MedicineSemanticData:
        if not self.api_key:
            raise DeepSeekMedicineError("medicine_semantic_not_configured")
        lines = {}
        input_lines = []
        for document in documents:
            for index, line in enumerate(document.lines):
                line_id = f"{document.role}:{index}"
                lines[line_id] = line.text
                input_lines.append(
                    {
                        "id": line_id,
                        "text": line.text,
                        "score": round(line.score, 5),
                    }
                )
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": self._system_prompt()},
                {
                    "role": "user",
                    "content": json.dumps(input_lines, ensure_ascii=False),
                },
            ],
            "response_format": {"type": "json_object"},
            "thinking": {"type": "disabled"},
            "temperature": 0,
            "max_tokens": 800,
            "stream": False,
        }
        response = self.transport.post_json(
            f"{self.base_url}/chat/completions",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            payload=payload,
            timeout=self.timeout_seconds,
        )
        try:
            content = response["choices"][0]["message"]["content"]
            parsed = MedicineSemanticData.model_validate_json(content)
        except (KeyError, IndexError, TypeError, ValidationError) as error:
            raise DeepSeekMedicineError("medicine_semantic_invalid_response") from error
        return parsed.model_copy(
            update={
                name: self._supported(getattr(parsed, name), lines)
                for name in self.FIELD_NAMES
            }
        )
```

The fixed exception codes deliberately exclude the API key, OCR text and raw provider response.

- [ ] **Step 5: Run DeepSeek provider tests**

Run:

```bash
.venv/bin/pytest \
  backend/tests/ocr/providers/test_deepseek.py \
  backend/tests/reminders/providers/test_deepseek.py -q
```

Expected: medicine and reminder providers both pass; no existing reminder parsing behavior changes.

- [ ] **Step 6: Commit semantic parsing**

```bash
git add backend/apps/ocr/domain/semantic.py \
  backend/apps/ocr/providers/deepseek.py \
  backend/tests/ocr/providers/test_deepseek.py
git commit -m "feat: add evidence-constrained medicine parsing"
```

### Task 6: Integrate The Hybrid Candidate Resolver

**Files:**
- Create: `backend/apps/ocr/services/candidate_resolver.py`
- Create: `backend/apps/ocr/providers/semantic_factory.py`
- Modify: `backend/apps/ocr/services/job_runner.py`
- Modify: `backend/apps/ocr/tasks.py`
- Modify: `backend/tests/ocr/services/test_job_runner.py`
- Modify: `backend/tests/ocr/test_tasks.py`

- [ ] **Step 1: Write failing resolver and job tests**

Create `backend/tests/ocr/services/test_candidate_resolver.py`:

```python
from datetime import date

from apps.ocr.domain.semantic import EvidenceField, MedicineSemanticData
from apps.ocr.domain.types import OCRDocument, OCRLine
from apps.ocr.providers.deepseek import DeepSeekMedicineError
from apps.ocr.services.candidate_resolver import resolve_candidates


def _line(text, score=0.95):
    return OCRLine(((0, 0), (1, 0), (1, 1), (0, 1)), text, score)


DOCUMENTS = (
    OCRDocument(
        "front",
        (_line("每片中阿莫西林含量0.25g"), _line("阿莫西林胶囊")),
    ),
    OCRDocument("expiry", (_line("有效期至"), _line("202805"))),
)


class SuccessfulSemanticProvider:
    def parse(self, documents):
        assert documents == DOCUMENTS
        return MedicineSemanticData(
            medicine_name=EvidenceField(
                value="阿莫西林胶囊",
                line_ids=["front:1"],
            ),
            specification=None,
            batch_number=None,
            production_date_text=None,
            expiry_date_text=EvidenceField(
                value="202805",
                line_ids=["expiry:1"],
            ),
            ambiguities=[],
        )


class FailingSemanticProvider:
    def parse(self, documents):
        raise DeepSeekMedicineError("medicine_semantic_request_failed")


def test_semantic_name_and_date_fill_validated_candidates():
    result = resolve_candidates(
        DOCUMENTS,
        semantic_provider=SuccessfulSemanticProvider(),
    )
    assert result.medicine_name == "阿莫西林胶囊"
    assert result.expiry_date == date(2028, 5, 31)


def test_semantic_failure_returns_local_candidates():
    result = resolve_candidates(
        (OCRDocument("front", (_line("阿莫西林胶囊"),)),),
        semantic_provider=FailingSemanticProvider(),
    )
    assert result.medicine_name == "阿莫西林胶囊"
```

Append to `backend/tests/ocr/services/test_job_runner.py`:

```python
@pytest.mark.django_db
def test_run_job_merges_duplicate_expiry_variant_lines(user, monkeypatch):
    monkeypatch.setattr(
        "apps.ocr.services.job_runner.prepare_ocr_variants",
        lambda value, role: (b"original", b"enhanced")
        if role == "expiry"
        else (b"original",),
    )

    class VariantProvider:
        def recognize(self, image_bytes, *, role):
            text = "阿莫西林胶囊" if role == "front" else "有效期至2028.05"
            score = 0.98 if image_bytes == b"enhanced" else 0.90
            return OCRDocument(
                role,
                (OCRLine(
                    ((0, 0), (1, 0), (1, 1), (0, 1)),
                    text,
                    score,
                ),),
            )

    job = OCRJob.objects.create(
        user=user,
        image_keys={"front": "front", "expiry": "expiry"},
    )
    run_job(job.id, storage=FakeStorage(), provider=VariantProvider())
    job.refresh_from_db()
    assert job.status == OCRJob.Status.SUCCEEDED
    assert job.candidate.raw_line_count == 2
    assert str(job.candidate.expiry_date) == "2028-05-31"
```

- [ ] **Step 2: Run focused service tests and verify RED**

Run:

```bash
.venv/bin/pytest \
  backend/tests/ocr/services/test_candidate_resolver.py \
  backend/tests/ocr/services/test_job_runner.py \
  backend/tests/ocr/test_tasks.py -q
```

Expected: tests fail because the resolver, semantic factory and multi-variant orchestration are missing.

- [ ] **Step 3: Implement deterministic/semantic field merging**

Create `candidate_resolver.py` with this public contract:

```python
import logging

from apps.ocr.domain.medicine_parser import extract_candidates, parse_date_value
from apps.ocr.domain.types import MedicineCandidates
from apps.ocr.providers.deepseek import DeepSeekMedicineError


logger = logging.getLogger(__name__)


def resolve_candidates(documents, *, semantic_provider=None):
    local = extract_candidates(documents)
    if semantic_provider is None:
        return local
    try:
        semantic = semantic_provider.parse(documents)
    except DeepSeekMedicineError:
        logger.info("ocr_semantic_fallback error_code=semantic_unavailable")
        return local

    medicine_name = (
        semantic.medicine_name.value
        if semantic.medicine_name is not None
        else local.medicine_name
    )
    production_date = local.production_date
    if production_date is None and semantic.production_date_text is not None:
        production_date = parse_date_value(
            semantic.production_date_text.value,
            allow_month_year=False,
        )
    expiry_date = local.expiry_date
    if expiry_date is None and semantic.expiry_date_text is not None:
        expiry_date = parse_date_value(
            semantic.expiry_date_text.value,
            allow_month_year=True,
        )
    if production_date and expiry_date and production_date > expiry_date:
        production_date = None
        expiry_date = None

    return MedicineCandidates(
        medicine_name=medicine_name,
        specification=(
            local.specification
            or (semantic.specification.value if semantic.specification else "")
        ),
        batch_number=(
            local.batch_number
            or (semantic.batch_number.value if semantic.batch_number else "")
        ),
        production_date=production_date,
        expiry_date=expiry_date,
        confidence=local.confidence,
    )
```

Task 4 already exposes `parse_date_value`; import that public function here rather than duplicating date parsing.

- [ ] **Step 4: Add the semantic factory**

Create `backend/apps/ocr/providers/semantic_factory.py`:

```python
from django.conf import settings

from .deepseek import DeepSeekMedicineProvider


def get_medicine_semantic_provider():
    if settings.OCR_SEMANTIC_PROVIDER == "none":
        return None
    if settings.OCR_SEMANTIC_PROVIDER == "deepseek":
        return DeepSeekMedicineProvider(
            api_key=settings.DEEPSEEK_API_KEY,
            base_url=settings.DEEPSEEK_BASE_URL,
            model=settings.DEEPSEEK_MODEL,
            timeout_seconds=settings.OCR_SEMANTIC_TIMEOUT_SECONDS,
        )
    raise ValueError("unsupported_ocr_semantic_provider")
```

- [ ] **Step 5: Update job orchestration**

Add these imports to `job_runner.py`, change its signature to `run_job(job_id, *, storage, provider, semantic_provider=None)`, and replace the current single-image recognition block with:

```python
from django.conf import settings

from apps.ocr.domain.layout import merge_documents

from .candidate_resolver import resolve_candidates
from .debug_logging import log_ocr_documents
from .image_validation import prepare_ocr_variants


documents = []
for role in ("front", "expiry"):
    key = job.image_keys.get(role)
    if not key:
        continue
    variants = prepare_ocr_variants(storage.get_bytes(key), role=role)
    recognized = tuple(
        provider.recognize(image, role=role) for image in variants
    )
    documents.append(merge_documents(role, recognized))

merged_documents = tuple(documents)
log_ocr_documents(
    job_id,
    merged_documents,
    enabled=settings.OCR_DEBUG_TEXT_LOGGING,
)
candidates = resolve_candidates(
    merged_documents,
    semantic_provider=semantic_provider,
)
```

Add `from apps.ocr.providers.semantic_factory import get_medicine_semantic_provider` to `tasks.py`, then inject the provider into the existing task call:

```python
job = run_job(
    job_id,
    storage=get_object_storage(),
    provider=get_ocr_provider(),
    semantic_provider=get_medicine_semantic_provider(),
)
```

Do not initialize RapidOCR or DeepSeek in the API process; this import and construction remain in the OCR task path.

- [ ] **Step 6: Run service and task tests**

Run:

```bash
.venv/bin/pytest \
  backend/tests/ocr/services/test_job_runner.py \
  backend/tests/ocr/test_tasks.py \
  backend/tests/ocr/domain/test_medicine_parser.py \
  backend/tests/ocr/providers/test_deepseek.py -q
```

Expected: all selected tests pass; a semantic timeout does not mark the OCR job failed.

- [ ] **Step 7: Commit hybrid orchestration**

```bash
git add backend/apps/ocr/services/candidate_resolver.py \
  backend/apps/ocr/providers/semantic_factory.py \
  backend/apps/ocr/services/job_runner.py \
  backend/apps/ocr/tasks.py \
  backend/apps/ocr/domain/medicine_parser.py \
  backend/tests/ocr/services/test_candidate_resolver.py \
  backend/tests/ocr/services/test_job_runner.py \
  backend/tests/ocr/test_tasks.py
git commit -m "feat: combine OCR rules with DeepSeek evidence"
```

### Task 7: Wire Production Configuration And Validate Deployment Contracts

**Files:**
- Modify: `backend/config/settings.py`
- Modify: `deploy/tencent/env.production.example`
- Modify: `deploy/tencent/compose.production.yaml`
- Modify: `deploy/tencent/scripts/check_env.py`
- Modify: `backend/tests/ocr/test_settings.py`
- Modify: `backend/tests/deployment/test_env_contract.py`
- Modify: `backend/tests/deployment/test_compose_contract.py`

- [ ] **Step 1: Write failing configuration contract tests**

Append these assertions to the existing default/configuration tests:

```python
# backend/tests/ocr/test_settings.py
assert settings.OCR_SEMANTIC_PROVIDER == "deepseek"
assert settings.OCR_SEMANTIC_TIMEOUT_SECONDS == 8
assert settings.OCR_DEBUG_TEXT_LOGGING is False

# backend/tests/deployment/test_env_contract.py
assert values["OCR_SEMANTIC_PROVIDER"] == "deepseek"
assert values["OCR_SEMANTIC_TIMEOUT_SECONDS"] == "8"
assert values["OCR_DEBUG_TEXT_LOGGING"] == "false"

# backend/tests/deployment/test_compose_contract.py
environment = load_production_compose()["services"]["ocr-worker"]["environment"]
assert environment["OCR_SEMANTIC_PROVIDER"] == "${OCR_SEMANTIC_PROVIDER:-deepseek}"
assert environment["OCR_SEMANTIC_TIMEOUT_SECONDS"] == "${OCR_SEMANTIC_TIMEOUT_SECONDS:-8}"
assert environment["OCR_DEBUG_TEXT_LOGGING"] == "${OCR_DEBUG_TEXT_LOGGING:-false}"
```

Append to `backend/tests/deployment/test_env_contract.py`:

```python
def test_validator_rejects_invalid_ocr_debug_flag(tmp_path):
    values = valid_example_values()
    values["OCR_DEBUG_TEXT_LOGGING"] = "yes"
    result = run_validator(tmp_path, values)
    assert result.returncode == 1
    assert "OCR_DEBUG_TEXT_LOGGING" in result.stderr


def test_validator_rejects_unknown_ocr_semantic_provider(tmp_path):
    values = valid_example_values()
    values["OCR_SEMANTIC_PROVIDER"] = "unknown"
    result = run_validator(tmp_path, values)
    assert result.returncode == 1
    assert "OCR_SEMANTIC_PROVIDER" in result.stderr


def test_validator_rejects_invalid_ocr_semantic_timeout(tmp_path):
    values = valid_example_values()
    values["OCR_SEMANTIC_TIMEOUT_SECONDS"] = "zero"
    result = run_validator(tmp_path, values)
    assert result.returncode == 1
    assert "OCR_SEMANTIC_TIMEOUT_SECONDS" in result.stderr
```

- [ ] **Step 2: Run configuration tests and verify RED**

Run:

```bash
.venv/bin/pytest \
  backend/tests/ocr/test_settings.py \
  backend/tests/deployment/test_env_contract.py \
  backend/tests/deployment/test_compose_contract.py -q
```

Expected: failures identify missing OCR semantic and debug configuration.

- [ ] **Step 3: Add settings and production environment values**

Append to `settings.py`:

```python
OCR_SEMANTIC_PROVIDER = os.environ.get("OCR_SEMANTIC_PROVIDER", "deepseek")
OCR_SEMANTIC_TIMEOUT_SECONDS = float(
    os.environ.get("OCR_SEMANTIC_TIMEOUT_SECONDS", "8")
)
```

Add to `env.production.example`:

```dotenv
OCR_SEMANTIC_PROVIDER=deepseek
OCR_SEMANTIC_TIMEOUT_SECONDS=8
OCR_DEBUG_TEXT_LOGGING=false
```

Add to `x-ocr-environment` in `compose.production.yaml`:

```yaml
OCR_SEMANTIC_PROVIDER: ${OCR_SEMANTIC_PROVIDER:-deepseek}
OCR_SEMANTIC_TIMEOUT_SECONDS: ${OCR_SEMANTIC_TIMEOUT_SECONDS:-8}
OCR_DEBUG_TEXT_LOGGING: ${OCR_DEBUG_TEXT_LOGGING:-false}
```

Append these checks inside `validate` in `check_env.py` before `return errors`:

```python
if values.get("OCR_DEBUG_TEXT_LOGGING") not in {None, "", "true", "false"}:
    errors.append("OCR_DEBUG_TEXT_LOGGING must be true or false")
if values.get("OCR_SEMANTIC_PROVIDER") not in {
    None,
    "",
    "deepseek",
    "none",
}:
    errors.append("OCR_SEMANTIC_PROVIDER must be deepseek or none")
try:
    semantic_timeout = float(values.get("OCR_SEMANTIC_TIMEOUT_SECONDS", "8"))
    if semantic_timeout <= 0:
        raise ValueError
except ValueError:
    errors.append("OCR_SEMANTIC_TIMEOUT_SECONDS must be a positive number")
```

- [ ] **Step 4: Run configuration tests and Compose validation**

Run:

```bash
.venv/bin/pytest \
  backend/tests/ocr/test_settings.py \
  backend/tests/deployment/test_env_contract.py \
  backend/tests/deployment/test_compose_contract.py -q
APP_VERSION=test \
DJANGO_SECRET_KEY=test-django-secret \
POSTGRES_PASSWORD=test-postgres-secret \
DEEPSEEK_API_KEY=test-deepseek-key \
CERTBOT_EMAIL=owner@example.com \
S3_ACCESS_KEY_ID=test-app-user \
S3_SECRET_ACCESS_KEY=test-app-secret \
MINIO_ROOT_USER=test-root-user \
MINIO_ROOT_PASSWORD=test-root-secret \
docker compose \
  --env-file deploy/tencent/env.production.example \
  -f compose.yaml -f deploy/tencent/compose.production.yaml config --quiet
```

Expected: tests pass and Compose exits `0` without printing the supplied placeholder secrets.

- [ ] **Step 5: Commit production configuration**

```bash
git add backend/config/settings.py \
  deploy/tencent/env.production.example \
  deploy/tencent/compose.production.yaml \
  deploy/tencent/scripts/check_env.py \
  backend/tests/ocr/test_settings.py \
  backend/tests/deployment/test_env_contract.py \
  backend/tests/deployment/test_compose_contract.py
git commit -m "build: configure hybrid medicine OCR"
```

### Task 8: Full Verification, Deployment And Real-Image Diagnosis

**Files:**
- Verify all modified OCR and deployment files.
- No committed credential or production environment files.

- [ ] **Step 1: Format and run the complete backend suite**

Run:

```bash
.venv/bin/python -m black --check backend 2>/dev/null || true
.venv/bin/pytest backend -q
.venv/bin/python backend/manage.py check
git diff --check
```

Expected: all backend tests pass, Django reports no issues and Git reports no whitespace errors. If Black is not installed, do not install it only for this task; keep the repository's existing formatting convention.

- [ ] **Step 2: Run Flutter regression checks because the API contract is unchanged**

Run:

```bash
cd app
/Users/liuyang/Desktop/own/smart-reminder/.tools/flutter/bin/flutter test --no-pub
/Users/liuyang/Desktop/own/smart-reminder/.tools/flutter/bin/flutter analyze --no-pub
```

Expected: all Flutter tests pass and analysis reports `No issues found!`.

- [ ] **Step 3: Review privacy and evidence constraints**

Run:

```bash
rg -n "ocr_text|OCR_DEBUG_TEXT_LOGGING|line_ids|DeepSeekMedicine" backend deploy/tencent
rg -n "image_keys|upload_url|Authorization|DEEPSEEK_API_KEY" backend/apps/ocr/services/debug_logging.py
```

Expected: the debug logger references only job ID, role, line index, score and sanitized text; it contains no code that logs image keys, signed URLs, headers or API keys.

- [ ] **Step 4: Push the reviewed `main` commit and deploy its exact SHA**

Run locally:

```bash
git status --short
DEPLOY_SHA=$(git rev-parse HEAD)
git push origin main
ssh -i /Users/liuyang/.ssh/id_ed25519_smart_reminder \
  -o IdentitiesOnly=yes -o BatchMode=yes ubuntu@aipupu.cloud \
  "cd /opt/smart-reminder/app && \
   test -z \"\$(git status --porcelain)\" && \
   git fetch origin main && \
   git merge --ff-only FETCH_HEAD && \
   ./deploy/tencent/scripts/deploy.sh '$DEPLOY_SHA' \
     /opt/smart-reminder/shared/.env.production"
```

Expected: migrations, OCR smoke check, API health, Nginx validation and container replacement all complete successfully.

- [ ] **Step 5: Enable raw OCR logging only for one controlled reproduction**

On Tencent Cloud, enable the flag without reading any existing secret value, recreate only `ocr-worker`, and verify the effective boolean:

```bash
cd /opt/smart-reminder/app
OCR_ENV_FILE=/opt/smart-reminder/shared/.env.production
sed -i '/^OCR_DEBUG_TEXT_LOGGING=/d' "$OCR_ENV_FILE"
printf '%s\n' 'OCR_DEBUG_TEXT_LOGGING=true' >> "$OCR_ENV_FILE"
chmod 600 "$OCR_ENV_FILE"
export APP_VERSION=$(git rev-parse --short=12 HEAD)
docker compose \
  --env-file "$OCR_ENV_FILE" \
  -f compose.yaml -f deploy/tencent/compose.production.yaml \
  up -d --force-recreate ocr-worker
docker compose \
  --env-file "$OCR_ENV_FILE" \
  -f compose.yaml -f deploy/tencent/compose.production.yaml \
  exec -T ocr-worker python -c \
  'from django.conf import settings; assert settings.OCR_DEBUG_TEXT_LOGGING is True'
```

Capture one front and one expiry photo, stop on the review screen without confirming, then run:

```bash
journalctl -t smart-reminder/ocr-worker --since "10 minutes ago" \
  --no-pager | grep "ocr_text"
```

Expected: every recognized line includes role, index, score and sanitized text. No image key, signed URL or credential appears.

- [ ] **Step 6: Disable debug logging and retest the same images**

Run on Tencent Cloud:

```bash
cd /opt/smart-reminder/app
OCR_ENV_FILE=/opt/smart-reminder/shared/.env.production
sed -i '/^OCR_DEBUG_TEXT_LOGGING=/d' "$OCR_ENV_FILE"
printf '%s\n' 'OCR_DEBUG_TEXT_LOGGING=false' >> "$OCR_ENV_FILE"
chmod 600 "$OCR_ENV_FILE"
export APP_VERSION=$(git rev-parse --short=12 HEAD)
docker compose \
  --env-file "$OCR_ENV_FILE" \
  -f compose.yaml -f deploy/tencent/compose.production.yaml \
  up -d --force-recreate ocr-worker
docker compose \
  --env-file "$OCR_ENV_FILE" \
  -f compose.yaml -f deploy/tencent/compose.production.yaml \
  exec -T ocr-worker python -c \
  'from django.conf import settings; assert settings.OCR_DEBUG_TEXT_LOGGING is False'
```

Retest one task and verify it contains `ocr_complete` but no new `ocr_text` lines. The earlier controlled OCR text remains subject to the existing seven-day journald retention policy.

- [ ] **Step 7: Complete acceptance with three medicine-box styles**

For each of printed date, dot-matrix date and split label/value date:

1. Capture front and expiry photos.
2. Confirm the candidate name is a concrete medicine name, not a composition sentence or pure dosage form.
3. Confirm visible production and expiry dates are populated when their source text is recognizable.
4. Confirm no candidate value exists outside its OCR evidence.
5. Edit any remaining low-confidence value and confirm inventory creation and image deletion.

Expected: all five checks pass for each style, or the exact unresolved OCR lines are retained only in the controlled diagnostic window for the next parser fixture.

- [ ] **Step 8: Commit any acceptance fixtures, then leave the tree clean**

Only sanitized synthetic text fixtures may be committed. Do not commit real medicine photos, raw user OCR logs or environment files.

```bash
git status --short
git log --oneline -8
```

Expected: working tree is clean and `main` contains the staged implementation commits in task order.
