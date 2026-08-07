FROM python:3.11.13-slim-bookworm

ARG PIP_INDEX_URL=https://pypi.org/simple
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cpu

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    MODELSCOPE_CACHE=/models \
    HF_HOME=/models/huggingface

WORKDIR /srv/funasr

COPY services/funasr/requirements.txt ./requirements.txt
RUN python -m pip install --no-cache-dir \
    --no-deps --index-url "$PYTORCH_INDEX_URL" \
    torch==2.7.1+cpu torchaudio==2.7.1+cpu
RUN python -m pip install --no-cache-dir --index-url "$PIP_INDEX_URL" \
    -r requirements.txt

COPY services/funasr/app ./app
COPY services/funasr/smoke ./smoke

EXPOSE 8000
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
