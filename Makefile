.PHONY: install test-backend run-backend compose-up check

install:
	python3 -m venv .venv
	.venv/bin/python -m pip install -r backend/requirements/dev.txt

test-backend:
	.venv/bin/pytest backend -q

run-backend:
	.venv/bin/python backend/manage.py runserver 0.0.0.0:8000

compose-up:
	docker compose up --build

check:
	.venv/bin/python backend/manage.py check
	.venv/bin/python backend/manage.py makemigrations --check --dry-run
