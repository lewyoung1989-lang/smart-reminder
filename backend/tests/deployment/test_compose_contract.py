from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]


class ComposeLoader(yaml.SafeLoader):
    pass


ComposeLoader.add_constructor("!reset", lambda loader, node: [])


def load_production_compose():
    path = REPO_ROOT / "deploy/tencent/compose.production.yaml"
    return yaml.load(path.read_text(), Loader=ComposeLoader)


def test_internal_services_publish_no_host_ports():
    services = load_production_compose()["services"]
    for name in ("postgres", "redis", "minio", "api"):
        assert services[name]["ports"] == []
    assert services["nginx"]["ports"] == ["80:80", "443:443"]


def test_production_services_restart_and_rotate_logs():
    services = load_production_compose()["services"]
    for name in ("postgres", "redis", "api", "worker", "beat", "nginx"):
        assert services[name]["restart"] == "unless-stopped"
        assert services[name]["logging"]["options"] == {
            "max-size": "10m",
            "max-file": "5",
        }


def test_minio_is_private_initialized_and_not_profile_gated():
    services = load_production_compose()["services"]
    assert services["minio"]["ports"] == []
    assert not services["minio"].get("profiles")
    assert (
        services["minio-init"]["depends_on"]["minio"]["condition"]
        == "service_healthy"
    )
    assert services["minio-init"]["restart"] == "no"


def test_ocr_worker_is_isolated_and_resource_limited():
    service = load_production_compose()["services"]["ocr-worker"]
    assert service["image"].startswith("smart-reminder-ocr:")
    assert "-Q ocr" in service["command"]
    assert "--concurrency=1" in service["command"]
    assert service["cpus"] == 1.0
    assert service["mem_limit"] == "1200m"
    assert service["ports"] == []


def test_nginx_redirects_http_and_forwards_https_metadata():
    config = (REPO_ROOT / "deploy/tencent/nginx/aipupu.cloud.conf").read_text()
    assert "return 301 https://$host$request_uri;" in config
    assert (
        "ssl_certificate /etc/letsencrypt/live/aipupu.cloud/fullchain.pem;" in config
    )
    assert "proxy_pass http://api:8000;" in config
    assert "proxy_set_header X-Forwarded-Proto https;" in config
    assert "proxy_set_header Authorization $http_authorization;" in config


def test_file_domain_is_put_only_and_does_not_log_signatures():
    config = (
        REPO_ROOT / "deploy/tencent/nginx/aipupu.cloud.conf"
    ).read_text()
    assert "server_name files.aipupu.cloud;" in config
    assert "proxy_pass http://minio:9000;" in config
    assert "proxy_set_header Host $http_host;" in config
    assert "limit_except PUT" in config
    assert "access_log off;" in config
    assert "client_max_body_size 9m;" in config


def test_api_healthcheck_uses_the_allowed_production_host():
    services = load_production_compose()["services"]
    command = services["api"]["healthcheck"]["test"][-1]
    assert "'Host':'aipupu.cloud'" in command
