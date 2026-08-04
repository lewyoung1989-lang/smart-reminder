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


def test_nginx_redirects_http_and_forwards_https_metadata():
    config = (REPO_ROOT / "deploy/tencent/nginx/aipupu.cloud.conf").read_text()
    assert "return 301 https://$host$request_uri;" in config
    assert (
        "ssl_certificate /etc/letsencrypt/live/aipupu.cloud/fullchain.pem;" in config
    )
    assert "proxy_pass http://api:8000;" in config
    assert "proxy_set_header X-Forwarded-Proto https;" in config
    assert "proxy_set_header Authorization $http_authorization;" in config
