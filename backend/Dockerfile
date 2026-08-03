FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY backend/requirements /app/backend/requirements
RUN pip install --no-cache-dir -r /app/backend/requirements/base.txt

COPY backend /app/backend

WORKDIR /app/backend
EXPOSE 8000

CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2"]
