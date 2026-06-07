import importlib.util
from pathlib import Path

import pytest


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "deploy_pg_ha_cluster.py"
SPEC = importlib.util.spec_from_file_location("deploy_pg_ha_cluster", SCRIPT_PATH)
deploy_pg_ha_cluster = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(deploy_pg_ha_cluster)


def parse_args(*args):
    return deploy_pg_ha_cluster.build_parser().parse_args(list(args))


@pytest.fixture(autouse=True)
def clear_password_env(monkeypatch):
    for env_var in deploy_pg_ha_cluster.PASSWORD_ENV_VARS.values():
        monkeypatch.delenv(env_var, raising=False)


def test_deploy_defaults_generate_aws_tfvars(monkeypatch):
    monkeypatch.setattr(deploy_pg_ha_cluster, "generated_password", lambda: "generated-secret")

    args = parse_args("deploy")
    tfvars = deploy_pg_ha_cluster.build_tfvars(args)

    assert tfvars["cloud_provider"] == "aws"
    assert tfvars["aws_region"] == "us-east-1"
    assert tfvars["project_name"] == "pg-ha-cluster"
    assert tfvars["proxy_type"] == "haproxy"
    assert tfvars["postgresql_version"] == "18"
    assert tfvars["create_network"] is True
    assert tfvars["enable_local_nvme"] is True
    assert "pg_instance_type" not in tfvars
    assert "proxy_instance_type" not in tfvars
    assert tfvars["repmgr_password"] == "generated-secret"
    assert tfvars["postgres_password"] == "generated-secret"
    assert tfvars["proxy_admin_password"] == "generated-secret"


def test_deploy_overrides_network_postgres_version_and_instances():
    args = parse_args(
        "deploy",
        "--provider",
        "aws",
        "--existing-vpc",
        "vpc-123",
        "--existing-subnet",
        "subnet-123",
        "--allowed-cidr",
        "203.0.113.10/32",
        "--allowed-cidr",
        "198.51.100.0/24",
        "--pg-instance-type",
        "i7ie.8xlarge",
        "--proxy-instance-type",
        "c7i.8xlarge",
        "--proxy-type",
        "pgcat",
        "--postgres-version",
        "17",
        "--no-local-nvme",
        "--repmgr-password",
        "repmgr-secret",
        "--postgres-password",
        "postgres-secret",
        "--proxy-admin-password",
        "proxy-secret",
    )

    tfvars = deploy_pg_ha_cluster.build_tfvars(args)

    assert tfvars["create_network"] is False
    assert tfvars["existing_vpc_id"] == "vpc-123"
    assert tfvars["existing_subnet_id"] == "subnet-123"
    assert tfvars["allowed_ssh_cidrs"] == ["203.0.113.10/32", "198.51.100.0/24"]
    assert tfvars["pg_instance_type"] == "i7ie.8xlarge"
    assert tfvars["proxy_instance_type"] == "c7i.8xlarge"
    assert tfvars["proxy_type"] == "pgcat"
    assert tfvars["postgresql_version"] == "17"
    assert tfvars["enable_local_nvme"] is False
    assert tfvars["repmgr_password"] == "repmgr-secret"
    assert tfvars["postgres_password"] == "postgres-secret"
    assert tfvars["proxy_admin_password"] == "proxy-secret"


def test_existing_network_requires_vpc_and_subnet():
    args = parse_args("deploy", "--existing-vpc", "vpc-123")

    with pytest.raises(SystemExit, match="--existing-vpc and --existing-subnet"):
        deploy_pg_ha_cluster.build_tfvars(args)


@pytest.mark.parametrize("proxy_type", ["haproxy", "pgpool", "proxysql", "pgcat"])
def test_supported_proxy_types_are_written_to_tfvars(proxy_type):
    args = parse_args("deploy", "--proxy-type", proxy_type)

    tfvars = deploy_pg_ha_cluster.build_tfvars(args)

    assert tfvars["proxy_type"] == proxy_type


def test_gcp_requires_project_id_when_env_is_absent(monkeypatch):
    monkeypatch.delenv("GOOGLE_CLOUD_PROJECT", raising=False)
    monkeypatch.delenv("GCLOUD_PROJECT", raising=False)

    args = parse_args("deploy", "--provider", "gcp")

    with pytest.raises(SystemExit, match="--gcp-project-id is required"):
        deploy_pg_ha_cluster.build_tfvars(args)


def test_gcp_existing_network_maps_to_gcp_tfvars():
    args = parse_args(
        "deploy",
        "--provider",
        "gcp",
        "--gcp-project-id",
        "pg-project",
        "--gcp-region",
        "us-east1",
        "--gcp-zone",
        "us-east1-b",
        "--existing-vpc",
        "projects/pg-project/global/networks/existing",
        "--existing-subnet",
        "projects/pg-project/regions/us-east1/subnetworks/existing",
    )

    tfvars = deploy_pg_ha_cluster.build_tfvars(args)

    assert tfvars["cloud_provider"] == "gcp"
    assert tfvars["gcp_project_id"] == "pg-project"
    assert tfvars["gcp_region"] == "us-east1"
    assert tfvars["gcp_zone"] == "us-east1-b"
    assert tfvars["create_network"] is False
    assert tfvars["existing_gcp_network"] == "projects/pg-project/global/networks/existing"
    assert tfvars["existing_gcp_subnetwork"] == "projects/pg-project/regions/us-east1/subnetworks/existing"


def test_show_and_destroy_options_parse():
    show_args = parse_args("show", "--skip-ansible-status")
    destroy_args = parse_args("destroy", "--no-auto-approve")

    assert show_args.command == "show"
    assert show_args.skip_ansible_status is True
    assert destroy_args.command == "destroy"
    assert destroy_args.no_auto_approve is True
