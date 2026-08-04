.PHONY: install test-backend run-backend compose-up check flutter-analyze flutter-test flutter-build-ios test-deployment

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

flutter-analyze:
	cd app && ../scripts/flutterw analyze

flutter-test:
	cd app && ../scripts/flutterw test

flutter-build-ios:
	cd app && ../scripts/flutterw build ios --simulator --debug

test-deployment:
	.venv/bin/pytest backend/tests/deployment -q
	bash -n deploy/tencent/scripts/bootstrap_tls.sh
	bash -n deploy/tencent/scripts/deploy.sh
	bash -n deploy/tencent/scripts/backup_postgres.sh
	bash -n deploy/tencent/scripts/restore_postgres.sh
