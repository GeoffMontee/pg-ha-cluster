# PostgreSQL High Availability Cluster

This project deploys a PostgreSQL 18 high availability cluster on AWS or GCP using:

- **Terraform** for cloud infrastructure, VPC/networking, firewall rules/security groups, instances, SSH keys, and generated Ansible inventory.
- **Ansible** for PostgreSQL, repmgr, health checks, and proxy configuration.
- **repmgr** for replication and automatic failover.
- **HAProxy, pgpool-II, ProxySQL, or PgCat** as the PostgreSQL proxy.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │          PostgreSQL Proxy               │
                    │  HAProxy | pgpool-II | ProxySQL | PgCat │
                    │  Port 5432 → PostgreSQL                 │
                    └─────────────────┬───────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
    ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
    │  PostgreSQL 18  │     │  PostgreSQL 18  │     │  PostgreSQL 18  │
    │    PRIMARY      │────▶│   STANDBY 1     │     │   STANDBY 2     │
    │   (repmgr)      │     │   (repmgr)      │◀────│   (repmgr)      │
    └─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Prerequisites

- Python 3.10 or newer.
- Terraform 1.0 or newer.
- Ansible 2.15 or newer.
- Cloud credentials configured for AWS or GCP.
- AWS: credentials with EC2, VPC, security group, and key pair permissions.
- GCP: Application Default Credentials or equivalent credentials with Compute Engine permissions.

## Quick Start

Deploy to AWS with the default AWS instance types:

```bash
python3 deploy_pg_ha_cluster.py deploy \
  --provider aws \
  --aws-region us-east-1 \
  --allowed-cidr YOUR_IP/32
```

Deploy to GCP with the default GCP machine types:

```bash
python3 deploy_pg_ha_cluster.py deploy \
  --provider gcp \
  --gcp-project-id YOUR_GCP_PROJECT \
  --gcp-region us-central1 \
  --gcp-zone us-central1-a \
  --allowed-cidr YOUR_IP/32
```

The deploy command:

- Writes `terraform/generated.auto.tfvars.json`.
- Runs `terraform init` and `terraform apply`.
- Installs Ansible Galaxy collections from `ansible/requirements.yml`.
- Runs `ansible/playbooks/site.yml`.
- Prints Terraform connection outputs.

If passwords are not supplied, the script generates them and stores them in `terraform/generated.auto.tfvars.json`. That file is ignored by Git, but it contains secrets and should be protected.

## Commands

Show Terraform outputs and the repmgr cluster status:

```bash
python3 deploy_pg_ha_cluster.py show
```

Destroy the Terraform-managed infrastructure:

```bash
python3 deploy_pg_ha_cluster.py destroy
```

Prompt before Terraform apply or destroy:

```bash
python3 deploy_pg_ha_cluster.py deploy --provider aws --no-auto-approve
python3 deploy_pg_ha_cluster.py destroy --no-auto-approve
```

Skip Ansible when you only want to provision infrastructure:

```bash
python3 deploy_pg_ha_cluster.py deploy --provider aws --skip-ansible
```

## Command-Line Options

`deploy` provisions infrastructure and optionally configures the cluster with Ansible:

- `--provider {aws,gcp}`: Cloud provider. Defaults to `aws`.
- `--project-name NAME`: Resource name prefix. Defaults to `pg-ha-cluster`.
- `--owner VALUE`: Owner tag or label. Defaults to the local `$USER` value when available.
- `--allowed-cidr CIDR`: CIDR allowed to SSH and connect to exposed services. Can be repeated.
- `--vpc-cidr CIDR`: Created VPC/network CIDR, or the internal CIDR to trust when using an existing network. Defaults to `10.0.0.0/16`.
- `--subnet-cidr CIDR`: CIDR for the created public subnet/subnetwork. Defaults to `10.0.1.0/24`.
- `--existing-vpc ID_OR_SELF_LINK`: Existing AWS VPC ID or GCP VPC network name/self link. Must be used with `--existing-subnet`.
- `--existing-subnet ID_OR_SELF_LINK`: Existing AWS subnet ID or GCP subnetwork name/self link. Must be used with `--existing-vpc`.
- `--proxy-type {haproxy,pgpool,proxysql,pgcat}`: PostgreSQL proxy implementation. Defaults to `haproxy`.
- `--pg-instance-type TYPE`: PostgreSQL node instance or machine type. Defaults are cloud-specific.
- `--proxy-instance-type TYPE`: Proxy node instance or machine type. Defaults are cloud-specific.
- `--postgres-version VERSION`: PostgreSQL major version to install. Defaults to `18`.
- `--pg-volume-size GB`: Root volume size for PostgreSQL nodes. Defaults to `50`.
- `--no-local-nvme`: Disable local NVMe/local SSD mounting for PostgreSQL data.
- `--aws-region REGION`: AWS region. Defaults to `us-east-1`.
- `--gcp-project-id PROJECT`: GCP project ID. Required for GCP unless `GOOGLE_CLOUD_PROJECT` or `GCLOUD_PROJECT` is set.
- `--gcp-region REGION`: GCP region. Defaults to `us-central1`.
- `--gcp-zone ZONE`: GCP zone. Defaults to `us-central1-a`.
- `--gcp-pg-local-ssd-count COUNT`: Number of local SSD scratch disks per GCP PostgreSQL node. Defaults to `1`.
- `--repmgr-password PASSWORD`: repmgr password. Defaults to `PG_HA_REPMGR_PASSWORD` or a generated value.
- `--postgres-password PASSWORD`: postgres superuser password. Defaults to `PG_HA_POSTGRES_PASSWORD` or a generated value.
- `--proxy-admin-password PASSWORD`: Proxy administration password. Defaults to `PG_HA_PROXY_ADMIN_PASSWORD` or a generated value.
- `--skip-ansible`: Run Terraform only.
- `--skip-galaxy`: Skip Ansible Galaxy collection installation.
- `--no-auto-approve`: Prompt before `terraform apply`.

`show` prints Terraform outputs and, by default, repmgr status:

- `--skip-ansible-status`: Only show Terraform outputs.

`destroy` tears down Terraform-managed infrastructure:

- `--no-auto-approve`: Prompt before `terraform destroy`.

## Cloud Defaults

By default, the Terraform configuration creates a VPC/network, a public subnet/subnetwork, firewall rules/security groups, three PostgreSQL nodes, and one proxy node.

AWS defaults:

- PostgreSQL nodes: `i7ie.4xlarge`
- Proxy node: `c7i.4xlarge`
- PostgreSQL data: local NVMe instance store mounted at `/var/lib/postgresql`

GCP defaults:

- PostgreSQL nodes: `c4d-standard-16`
- Proxy node: `c4-standard-16`
- PostgreSQL data: one local SSD scratch disk per database node, mounted at `/var/lib/postgresql`

Override instance types with:

```bash
python3 deploy_pg_ha_cluster.py deploy \
  --provider aws \
  --pg-instance-type i7ie.8xlarge \
  --proxy-instance-type c7i.8xlarge
```

Select a proxy implementation with:

```bash
python3 deploy_pg_ha_cluster.py deploy --provider aws --proxy-type pgcat
```

Proxy-specific exposed ports:

- `haproxy`: PostgreSQL read/write on `5432`, read-only on `5433`, stats on `7000`.
- `pgpool`: PostgreSQL proxy on `5432`, PCP admin on `9898`.
- `proxysql`: PostgreSQL proxy on `5432`, admin interface on `6032`.
- `pgcat`: PostgreSQL proxy on `5432`, Prometheus/admin endpoint on `9930`.

ProxySQL is installed from the target host's configured apt repositories. PgCat is installed with Cargo by the `pgcat` role.

Disable the local NVMe mount if you choose an instance type without local NVMe storage:

```bash
python3 deploy_pg_ha_cluster.py deploy --provider aws --no-local-nvme
```

Install a different PostgreSQL major version:

```bash
python3 deploy_pg_ha_cluster.py deploy --provider aws --postgres-version 17
```

Local NVMe and GCP local SSD are ephemeral. Data is lost if the underlying instance-local storage is lost, so production deployments should include backups, PITR, and a recovery design appropriate for the workload.

## Existing VPC or Subnet

To deploy into an existing AWS VPC and subnet:

```bash
python3 deploy_pg_ha_cluster.py deploy \
  --provider aws \
  --existing-vpc vpc-0123456789abcdef0 \
  --existing-subnet subnet-0123456789abcdef0 \
  --vpc-cidr 10.20.0.0/16 \
  --allowed-cidr YOUR_IP/32
```

To deploy into an existing GCP VPC and subnetwork:

```bash
python3 deploy_pg_ha_cluster.py deploy \
  --provider gcp \
  --gcp-project-id YOUR_GCP_PROJECT \
  --existing-vpc projects/YOUR_GCP_PROJECT/global/networks/YOUR_NETWORK \
  --existing-subnet projects/YOUR_GCP_PROJECT/regions/us-central1/subnetworks/YOUR_SUBNET \
  --vpc-cidr 10.20.0.0/16 \
  --allowed-cidr YOUR_IP/32
```

When using an existing subnet, ensure it can assign public IPs or otherwise provides SSH reachability from the machine running Ansible. The Terraform still creates the required security groups or firewall rules.

## Manual Terraform and Ansible

The deploy script is the supported way to generate Terraform variables. If you need to run the tools directly, first generate infrastructure only:

```bash
python3 deploy_pg_ha_cluster.py deploy --provider aws --skip-ansible
```

Then rerun Terraform or Ansible commands directly as needed:

```bash
cd terraform
terraform plan

cd ../ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```

## Connection Information

After deployment, use:

```bash
python3 deploy_pg_ha_cluster.py show
```

The selected proxy exposes:

- Port `5432` for PostgreSQL client connections.
- Optional proxy-specific read-only or admin ports listed in the proxy defaults above.

## Operations

Check cluster status on any PostgreSQL node:

```bash
sudo -u postgres repmgr -f /etc/repmgr.conf cluster show
sudo -u postgres repmgr -f /etc/repmgr.conf cluster crosscheck
```

View replication lag on the primary:

```bash
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
```

Manual switchover from a standby:

```bash
sudo -u postgres repmgr -f /etc/repmgr.conf standby switchover --siblings-follow
```

Health check endpoints on PostgreSQL nodes:

```bash
curl http://<node-ip>:8008/primary
curl http://<node-ip>:8008/replica
curl http://<node-ip>:8008/health
```

## Directory Structure

```
pg-ha-cluster/
├── deploy_pg_ha_cluster.py
├── test/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── templates/
│       ├── inventory.tftpl
│       └── group_vars.tftpl
└── ansible/
    ├── ansible.cfg
    ├── requirements.yml
    ├── inventory/
    │   ├── hosts.ini
    │   ├── group_vars/
    │   └── *.pem
    ├── playbooks/
    │   └── site.yml
    └── roles/
        ├── common/
        ├── postgresql/
        ├── repmgr/
        ├── pg_healthcheck/
        ├── haproxy/
        ├── pgpool/
        ├── proxysql/
        └── pgcat/
```

## Security Notes

- Restrict `--allowed-cidr` to trusted networks.
- Treat `terraform/generated.auto.tfvars.json`, `terraform.tfvars`, and Terraform state as sensitive.
- Use stronger secret handling, TLS, private subnets, and managed backups before using this for production traffic.
- Review `ansible/roles/postgresql/templates/pg_hba.conf.j2` for your application access model.

## Validation

Useful local checks:

```bash
terraform -chdir=terraform fmt -recursive
terraform -chdir=terraform validate
python3 -m py_compile deploy_pg_ha_cluster.py
ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg" ansible-playbook --syntax-check -i "localhost," ansible/playbooks/site.yml
```

## License

MIT
