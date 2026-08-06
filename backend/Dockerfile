FROM python:3.13-slim

ARG PIP_INDEX_URL=https://pypi.org/simple

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY backend/requirements /app/backend/requirements
RUN pip install --no-cache-dir --index-url "$PIP_INDEX_URL" \
    -r /app/backend/requirements/base.txt

COPY backend /app/backend

WORKDIR /app/backend
EXPOSE 8000

CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2"]
