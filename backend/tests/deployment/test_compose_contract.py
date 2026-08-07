from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]


class ComposeLoader(yaml.SafeLoader):
    pass


ComposeLoader.add_constructor("!reset", lambda loader, node: [])


def load_production_compose():
    path = REPO_ROOT / "deploy/tencent/compose.production.yaml"
    return yaml.load(path.read_text(), Loader=ComposeLoader)


def load_local_compose():
    path = REPO_ROOT / "compose.yaml"
    return yaml.safe_load(path.read_text())


def test_python_images_accept_a_configurable_package_index():
    services = load_local_compose()["services"]
    for name in (
        "api",
        "worker",
        "ocr-worker",
        "beat",
        "funasr-model-init",
        "funasr",
    ):
        assert services[name]["build"]["args"]["PIP_INDEX_URL"] == (
            "${PIP_INDEX_URL:-https://pypi.org/simple}"
        )

    for dockerfile in (
        "backend/Dockerfile",
        "backend/Dockerfile.ocr",
        "services/funasr/Dockerfile",
    ):
        content = (REPO_ROOT / dockerfile).read_text()
        assert "ARG PIP_INDEX_URL=https://pypi.org/simple" in content
        assert '--index-url "$PIP_INDEX_URL"' in content

    ocr_build_args = services["ocr-worker"]["build"]["args"]
    assert ocr_build_args["DEBIAN_MIRROR"] == (
        "${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
    )
    assert ocr_build_args["DEBIAN_SECURITY_MIRROR"] == (
        "${DEBIAN_SECURITY_MIRROR:-http://deb.debian.org/debian-security}"
    )
    ocr_dockerfile = (REPO_ROOT / "backend/Dockerfile.ocr").read_text()
    assert "ARG DEBIAN_MIRROR=http://deb.debian.org/debian" in ocr_dockerfile
    assert (
        "ARG DEBIAN_SECURITY_MIRROR=http://deb.debian.org/debian-security"
        in ocr_dockerfile
    )


def test_funasr_isolates_the_pytorch_index_from_general_dependencies():
    services = load_local_compose()["services"]
    expected_index = (
        "${PYTORCH_INDEX_URL:-https://download.pytorch.org/whl/cpu}"
    )
    for name in ("funasr-model-init", "funasr"):
        assert services[name]["build"]["args"]["PYTORCH_INDEX_URL"] == (
            expected_index
        )

    requirements = (
        REPO_ROOT / "services/funasr/requirements.txt"
    ).read_text()
    assert "--extra-index-url" not in requirements
    dockerfile = (REPO_ROOT / "services/funasr/Dockerfile").read_text()
    assert (
        "ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cpu"
        in dockerfile
    )
    torch_install = dockerfile.index(
        '--no-deps --index-url "$PYTORCH_INDEX_URL"'
    )
    general_install = dockerfile.index('--index-url "$PIP_INDEX_URL"')
    assert torch_install < general_install


def test_internal_services_publish_no_host_ports():
    services = load_production_compose()["services"]
    for name in ("postgres", "redis", "minio", "api", "funasr"):
        assert services[name]["ports"] == []
    assert services["nginx"]["ports"] == ["80:80", "443:443"]


def test_production_services_use_journald_with_stable_tags():
    services = load_production_compose()["services"]
    for name, service in services.items():
        assert service["logging"] == {
            "driver": "journald",
            "options": {"tag": f"smart-reminder/{name}"},
        }

    for name in ("postgres", "redis", "api", "worker", "beat", "nginx"):
        assert services[name]["restart"] == "unless-stopped"


def test_gunicorn_access_log_excludes_query_strings_and_headers():
    command = load_production_compose()["services"]["api"]["command"]

    assert "--access-logfile -" in command
    assert "--error-logfile -" in command
    assert "%(U)s" in command
    assert "%(q)s" not in command
    assert "%(r)s" not in command
    assert "x-request-id" in command.lower()
    assert "level=INFO" in command


def test_ocr_services_are_private_initialized_and_profile_gated():
    services = load_production_compose()["services"]
    assert services["minio"]["ports"] == []
    assert services["minio"]["profiles"] == ["ocr"]
    assert services["minio-init"]["profiles"] == ["ocr"]
    assert services["ocr-worker"]["profiles"] == ["ocr"]
    assert services["beat"]["profiles"] == ["ocr"]
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
    assert service["environment"]["OCR_SEMANTIC_PROVIDER"] == (
        "${OCR_SEMANTIC_PROVIDER:-deepseek}"
    )
    assert service["environment"]["OCR_SEMANTIC_TIMEOUT_SECONDS"] == (
        "${OCR_SEMANTIC_TIMEOUT_SECONDS:-8}"
    )
    assert service["environment"]["OCR_DEBUG_TEXT_LOGGING"] == (
        "${OCR_DEBUG_TEXT_LOGGING:-false}"
    )


def test_nginx_redirects_http_and_forwards_https_metadata():
    config = (REPO_ROOT / "deploy/tencent/nginx/aipupu.cloud.conf").read_text()
    assert "return 301 https://$host$request_uri;" in config
    assert (
        "ssl_certificate /etc/letsencrypt/live/aipupu.cloud/fullchain.pem;" in config
    )
    assert "proxy_pass http://api:8000;" in config
    assert "proxy_set_header X-Forwarded-Proto https;" in config
    assert "proxy_set_header Authorization $http_authorization;" in config


def test_nginx_access_log_is_correlated_without_private_request_data():
    config = (REPO_ROOT / "deploy/tencent/nginx/aipupu.cloud.conf").read_text()
    log_format = config.split("log_format smart_reminder", 1)[1].split(";", 1)[0]

    assert "$uri" in log_format
    assert "$request_uri" not in log_format
    assert "$args" not in log_format
    assert "$query_string" not in log_format
    assert "$remote_addr" not in log_format
    assert "$http_authorization" not in log_format
    assert "$smart_request_id" in log_format
    assert "level=INFO" in log_format
    assert config.count("access_log /dev/stdout smart_reminder;") == 3
    before_first_server = config.split("server {", 1)[0]
    assert "access_log " not in before_first_server
    assert "error_log /dev/stderr crit;" in config
    assert config.count("proxy_set_header X-Request-ID $smart_request_id;") == 2
    assert config.count("add_header X-Request-ID $smart_request_id always;") == 2
    assert "~^[A-Za-z0-9._-]{1,128}$" in config
    assert "default $request_id;" in config

    bootstrap = (REPO_ROOT / "deploy/tencent/nginx/bootstrap.conf").read_text()
    assert "access_log off;" in bootstrap


def test_file_domain_is_put_only_and_does_not_log_signatures():
    config = (
        REPO_ROOT / "deploy/tencent/nginx/aipupu.cloud.conf"
    ).read_text()
    assert "server_name files.aipupu.cloud;" in config
    assert "resolver 127.0.0.11" in config
    assert "set $minio_upstream http://minio:9000;" in config
    assert "proxy_pass $minio_upstream;" in config
    assert "proxy_set_header Host $http_host;" in config
    assert "limit_except PUT" in config
    assert "access_log off;" not in config
    assert "access_log /dev/stdout smart_reminder;" in config
    assert "client_max_body_size 9m;" in config


def test_api_healthcheck_uses_the_allowed_production_host():
    services = load_production_compose()["services"]
    command = services["api"]["healthcheck"]["test"][-1]
    assert "'Host':'aipupu.cloud'" in command


def test_backend_services_receive_auth_cache_and_jwt_configuration():
    services = load_production_compose()["services"]
    for name in ("api", "worker", "ocr-worker", "beat"):
        environment = services[name]["environment"]
        assert environment["AUTH_CACHE_URL"] == (
            "${AUTH_CACHE_URL:-redis://redis:6379/4}"
        )
        assert environment["JWT_SIGNING_KEY"] == (
            "${JWT_SIGNING_KEY:?JWT_SIGNING_KEY is required}"
        )


def test_funasr_uses_one_immutable_image_and_read_only_model_volume():
    services = load_production_compose()["services"]
    expected_image = "smart-reminder-funasr:${APP_VERSION:?APP_VERSION is required}"

    assert services["funasr"]["image"] == expected_image
    assert services["funasr-model-init"]["image"] == expected_image
    model_mount = services["funasr"]["volumes"][0]
    assert model_mount == {
        "type": "volume",
        "source": "funasr_models",
        "target": "/models",
        "read_only": True,
    }
    assert services["funasr-model-init"]["restart"] == "no"
    assert services["funasr"]["restart"] == "unless-stopped"


def test_funasr_is_single_process_and_resource_bounded_for_four_gb_host():
    service = load_production_compose()["services"]["funasr"]

    for variable in (
        "OMP_NUM_THREADS",
        "MKL_NUM_THREADS",
        "OPENBLAS_NUM_THREADS",
        "NUMEXPR_NUM_THREADS",
    ):
        assert service["environment"][variable] == "2"
    assert service["command"].count("--workers") == 1
    assert "--workers 1" in service["command"]
    assert 1 <= service["cpus"] <= 2
    assert service["mem_reservation"] == "1400m"
    assert service["mem_limit"] == "2600m"
    assert 64 <= service["pids_limit"] <= 256


def test_model_init_has_same_resource_envelope_as_funasr():
    services = load_production_compose()["services"]
    inference = services["funasr"]
    model_init = services["funasr-model-init"]

    for key in (
        "cpus",
        "mem_reservation",
        "mem_limit",
        "pids_limit",
    ):
        assert model_init[key] == inference[key]
    for key in (
        "OMP_NUM_THREADS",
        "MKL_NUM_THREADS",
        "OPENBLAS_NUM_THREADS",
        "NUMEXPR_NUM_THREADS",
    ):
        assert model_init["environment"][key] == "2"


def test_nginx_check_uses_production_config_without_host_ports():
    service = load_production_compose()["services"]["nginx-check"]
    assert service["image"] == "nginx:1.27-alpine"
    assert service.get("ports", []) == []
    assert service["profiles"] == ["production"]
    assert service["restart"] == "no"
    assert "asr_proxy" in service["networks"]
    assert any(
        mount.endswith(
            "deploy/tencent/nginx/aipupu.cloud.conf:/etc/nginx/conf.d/default.conf:ro"
        )
        for mount in service["volumes"]
    )


def test_asr_proxy_network_has_fixed_nginx_source_address():
    compose = load_production_compose()
    services = compose["services"]

    assert compose["networks"]["asr_proxy"] == {
        "driver": "bridge",
        "ipam": {"config": [{"subnet": "172.29.0.0/24"}]},
    }
    assert set(services["api"]["networks"]) == {"default", "asr_proxy"}
    assert services["nginx"]["networks"] == {
        "asr_proxy": {"ipv4_address": "172.29.0.10"}
    }
    assert "asr_proxy" in services["funasr"]["networks"]
    assert set(services["minio"]["networks"]) == {"default", "asr_proxy"}


def test_api_receives_complete_asr_production_environment():
    environment = load_production_compose()["services"]["api"]["environment"]
    expected = {
        "OCR_ENABLED": "${OCR_ENABLED:-false}",
        "ASR_PROVIDER": "${ASR_PROVIDER:-funasr}",
        "ASR_BASE_URL": "${ASR_BASE_URL:-http://funasr:8000}",
        "ASR_MODEL": "${ASR_MODEL:-paraformer-zh}",
        "ASR_TIMEOUT_SECONDS": "${ASR_TIMEOUT_SECONDS:-20}",
        "ASR_MAX_AUDIO_BYTES": "${ASR_MAX_AUDIO_BYTES:-4194304}",
        "ASR_MAX_REQUEST_BYTES": "${ASR_MAX_REQUEST_BYTES:-5242880}",
        "ASR_MIN_DURATION_SECONDS": "${ASR_MIN_DURATION_SECONDS:-0.3}",
        "ASR_MAX_DURATION_SECONDS": "${ASR_MAX_DURATION_SECONDS:-20}",
        "ASR_GLOBAL_CONCURRENCY": "${ASR_GLOBAL_CONCURRENCY:-1}",
        "ASR_CONCURRENCY_PER_USER": "${ASR_CONCURRENCY_PER_USER:-1}",
        "ASR_LEASE_TTL_SECONDS": "${ASR_LEASE_TTL_SECONDS:-25}",
        "ASR_USER_RATE": "${ASR_USER_RATE:-10/min}",
        "ASR_IP_RATE": "${ASR_IP_RATE:-30/min}",
        "ASR_REDIS_URL": "${ASR_REDIS_URL:-redis://redis:6379/0}",
        "ASR_THROTTLE_REDIS_URL": (
            "${ASR_THROTTLE_REDIS_URL:-redis://redis:6379/2}"
        ),
        "ASR_TRUSTED_PROXY_IPS": (
            "${ASR_TRUSTED_PROXY_IPS:-172.29.0.10}"
        ),
    }

    for key, value in expected.items():
        assert environment[key] == value


def test_api_does_not_depend_on_profile_gated_ocr_services():
    dependencies = load_production_compose()["services"]["api"].get(
        "depends_on", {}
    )
    assert "minio" not in dependencies
    assert "minio-init" not in dependencies
    assert "ocr-worker" not in dependencies


def test_worker_is_single_process_and_does_not_prefetch_work():
    command = load_production_compose()["services"]["worker"]["command"]
    assert "--concurrency=1" in command
    assert "--prefetch-multiplier=1" in command


def test_nginx_upload_and_trusted_forwarding_match_asr_boundary():
    config = (REPO_ROOT / "deploy/tencent/nginx/aipupu.cloud.conf").read_text()
    api_server = config.split("server_name aipupu.cloud;", 1)[1]

    assert "client_max_body_size 6m;" in api_server
    assert "proxy_set_header X-Forwarded-For $remote_addr;" in api_server
