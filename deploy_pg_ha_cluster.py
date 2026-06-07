#!/usr/bin/env python3
"""Deploy and manage the PostgreSQL HA cluster with Terraform and Ansible."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent
TERRAFORM_DIR = REPO_ROOT / "terraform"
ANSIBLE_DIR = REPO_ROOT / "ansible"
GENERATED_TFVARS = TERRAFORM_DIR / "generated.auto.tfvars.json"

PASSWORD_ENV_VARS = {
    "repmgr_password": "PG_HA_REPMGR_PASSWORD",
    "postgres_password": "PG_HA_POSTGRES_PASSWORD",
    "proxy_admin_password": "PG_HA_PROXY_ADMIN_PASSWORD",
}


def run(command: list[str], cwd: Path) -> None:
    """Run a command and stream output to the caller's terminal."""
    print(f"+ {' '.join(command)}", flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def run_optional(command: list[str], cwd: Path) -> None:
    """Run a best-effort command used by the show subcommand."""
    try:
        run(command, cwd)
    except subprocess.CalledProcessError as exc:
        print(f"warning: command failed with exit code {exc.returncode}: {' '.join(command)}", file=sys.stderr)


def generated_password() -> str:
    return secrets.token_urlsafe(24)


def password_value(args: argparse.Namespace, field: str) -> str:
    provided = getattr(args, field)
    if provided:
        return provided

    env_var = PASSWORD_ENV_VARS[field]
    from_env = os.environ.get(env_var)
    if from_env:
        return from_env

    return generated_password()


def ensure_generated_dirs() -> None:
    (ANSIBLE_DIR / "inventory" / "group_vars").mkdir(parents=True, exist_ok=True)


def build_tfvars(args: argparse.Namespace) -> dict[str, Any]:
    if bool(args.existing_vpc) != bool(args.existing_subnet):
        raise SystemExit("--existing-vpc and --existing-subnet must be supplied together")
    if args.proxy_count == 2 and not args.proxy_vip:
        raise SystemExit("--proxy-vip is required when --proxy-count 2")

    tfvars: dict[str, Any] = {
        "cloud_provider": args.provider,
        "project_name": args.project_name,
        "create_network": not bool(args.existing_vpc),
        "vpc_cidr": args.vpc_cidr,
        "public_subnet_cidr": args.subnet_cidr,
        "proxy_type": args.proxy_type,
        "proxy_count": args.proxy_count,
        "proxy_vip": args.proxy_vip or "",
        "postgresql_version": args.postgres_version,
        "pg_volume_size": args.pg_volume_size,
        "enable_local_nvme": not args.no_local_nvme,
        "gcp_pg_local_ssd_count": args.gcp_pg_local_ssd_count,
        "repmgr_password": password_value(args, "repmgr_password"),
        "postgres_password": password_value(args, "postgres_password"),
        "proxy_admin_password": password_value(args, "proxy_admin_password"),
    }

    if args.owner:
        tfvars["owner"] = args.owner
    if args.allowed_cidr:
        tfvars["allowed_ssh_cidrs"] = args.allowed_cidr
    if args.pg_instance_type:
        tfvars["pg_instance_type"] = args.pg_instance_type
    if args.proxy_instance_type:
        tfvars["proxy_instance_type"] = args.proxy_instance_type

    if args.provider == "aws":
        tfvars["aws_region"] = args.aws_region
        if args.existing_vpc:
            tfvars["existing_vpc_id"] = args.existing_vpc
            tfvars["existing_subnet_id"] = args.existing_subnet
    else:
        if not args.gcp_project_id:
            raise SystemExit("--gcp-project-id is required when --provider gcp")
        tfvars["gcp_project_id"] = args.gcp_project_id
        tfvars["gcp_region"] = args.gcp_region
        tfvars["gcp_zone"] = args.gcp_zone
        if args.existing_vpc:
            tfvars["existing_gcp_network"] = args.existing_vpc
            tfvars["existing_gcp_subnetwork"] = args.existing_subnet

    return tfvars


def write_tfvars(args: argparse.Namespace) -> None:
    tfvars = build_tfvars(args)
    GENERATED_TFVARS.write_text(json.dumps(tfvars, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote {GENERATED_TFVARS.relative_to(REPO_ROOT)}")

    generated_any = any(
        not getattr(args, field) and not os.environ.get(env_var)
        for field, env_var in PASSWORD_ENV_VARS.items()
    )
    if generated_any:
        print("Generated missing passwords and stored them in the Terraform var file.")


def terraform_init() -> None:
    run(["terraform", "init", "-input=false"], TERRAFORM_DIR)


def terraform_apply(auto_approve: bool) -> None:
    command = ["terraform", "apply", "-input=false"]
    if auto_approve:
        command.append("-auto-approve")
    run(command, TERRAFORM_DIR)


def terraform_destroy(auto_approve: bool) -> None:
    command = ["terraform", "destroy", "-input=false"]
    if auto_approve:
        command.append("-auto-approve")
    run(command, TERRAFORM_DIR)


def terraform_output() -> None:
    run(["terraform", "output"], TERRAFORM_DIR)


def install_ansible_requirements() -> None:
    run(["ansible-galaxy", "collection", "install", "-r", "requirements.yml"], ANSIBLE_DIR)


def run_ansible_playbook() -> None:
    run(["ansible-playbook", "-i", "inventory/hosts.ini", "playbooks/site.yml"], ANSIBLE_DIR)


def show_cluster_status() -> None:
    inventory = ANSIBLE_DIR / "inventory" / "hosts.ini"
    if not inventory.exists():
        print("Ansible inventory has not been generated yet; skipping cluster status.")
        return

    run_optional(
        [
            "ansible",
            "pg_primary",
            "-i",
            "inventory/hosts.ini",
            "-m",
            "ansible.builtin.command",
            "-a",
            "sudo -u postgres repmgr -f /etc/repmgr.conf cluster show",
            "-b",
        ],
        ANSIBLE_DIR,
    )


def deploy(args: argparse.Namespace) -> None:
    ensure_generated_dirs()
    write_tfvars(args)
    terraform_init()
    terraform_apply(auto_approve=not args.no_auto_approve)

    if not args.skip_ansible:
        if not args.skip_galaxy:
            install_ansible_requirements()
        run_ansible_playbook()

    terraform_output()


def show(args: argparse.Namespace) -> None:
    terraform_output()
    if not args.skip_ansible_status:
        show_cluster_status()


def destroy(args: argparse.Namespace) -> None:
    terraform_init()
    terraform_destroy(auto_approve=not args.no_auto_approve)


def add_deploy_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--provider", choices=["aws", "gcp"], default="aws", help="Cloud provider to deploy into")
    parser.add_argument("--project-name", default="pg-ha-cluster", help="Resource name prefix")
    parser.add_argument("--owner", default=os.environ.get("USER", ""), help="Owner tag/label value")
    parser.add_argument("--allowed-cidr", action="append", help="CIDR allowed to SSH and connect to exposed services")
    parser.add_argument("--vpc-cidr", default="10.0.0.0/16", help="Created VPC CIDR, or internal CIDR for existing networks")
    parser.add_argument("--subnet-cidr", default="10.0.1.0/24", help="CIDR for the created public subnet/subnetwork")
    parser.add_argument("--existing-vpc", help="Existing AWS VPC ID or GCP VPC network name/self link")
    parser.add_argument("--existing-subnet", help="Existing AWS subnet ID or GCP subnetwork name/self link")
    parser.add_argument("--proxy-type", choices=["haproxy", "pgpool", "proxysql", "pgcat"], default="haproxy", help="PostgreSQL proxy implementation")
    parser.add_argument("--proxy-count", type=int, choices=[1, 2], default=1, help="Number of proxy nodes to deploy")
    parser.add_argument("--proxy-vip", help="VRRP virtual IP for two-node proxy HA; required when --proxy-count 2")
    parser.add_argument("--pg-instance-type", help="PostgreSQL node instance/machine type")
    parser.add_argument("--proxy-instance-type", help="Proxy node instance/machine type")
    parser.add_argument("--postgres-version", default="18", help="PostgreSQL major version to install")
    parser.add_argument("--pg-volume-size", type=int, default=50, help="Root volume size in GB for PostgreSQL nodes")
    parser.add_argument("--no-local-nvme", action="store_true", help="Disable mounting local NVMe storage for PostgreSQL data")
    parser.add_argument("--aws-region", default="us-east-1", help="AWS region")
    parser.add_argument("--gcp-project-id", default=os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCLOUD_PROJECT"), help="GCP project ID")
    parser.add_argument("--gcp-region", default="us-central1", help="GCP region")
    parser.add_argument("--gcp-zone", default="us-central1-a", help="GCP zone")
    parser.add_argument("--gcp-pg-local-ssd-count", type=int, default=1, help="Local SSD scratch disks per GCP PostgreSQL node")
    parser.add_argument("--repmgr-password", help=f"repmgr password; defaults to ${PASSWORD_ENV_VARS['repmgr_password']} or a generated value")
    parser.add_argument("--postgres-password", help=f"postgres password; defaults to ${PASSWORD_ENV_VARS['postgres_password']} or a generated value")
    parser.add_argument("--proxy-admin-password", help=f"Proxy admin password; defaults to ${PASSWORD_ENV_VARS['proxy_admin_password']} or a generated value")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Deploy and manage the PostgreSQL HA cluster")
    subparsers = parser.add_subparsers(dest="command", required=True)

    deploy_parser = subparsers.add_parser("deploy", help="Provision infrastructure and configure PostgreSQL")
    add_deploy_args(deploy_parser)
    deploy_parser.add_argument("--skip-ansible", action="store_true", help="Only run Terraform")
    deploy_parser.add_argument("--skip-galaxy", action="store_true", help="Skip installing Ansible Galaxy collections")
    deploy_parser.add_argument("--no-auto-approve", action="store_true", help="Prompt before Terraform apply")
    deploy_parser.set_defaults(func=deploy)

    show_parser = subparsers.add_parser("show", help="Show Terraform outputs and cluster status")
    show_parser.add_argument("--skip-ansible-status", action="store_true", help="Only show Terraform outputs")
    show_parser.set_defaults(func=show)

    destroy_parser = subparsers.add_parser("destroy", help="Destroy Terraform-managed infrastructure")
    destroy_parser.add_argument("--no-auto-approve", action="store_true", help="Prompt before Terraform destroy")
    destroy_parser.set_defaults(func=destroy)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
