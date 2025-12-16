# PostgreSQL High Availability Cluster

This project deploys a production-ready PostgreSQL 17 high availability cluster on AWS using:

- **Terraform** - Infrastructure provisioning (4 EC2 instances, VPC, security groups)
- **Ansible** - Configuration management and application deployment
- **repmgr** - PostgreSQL replication manager for automatic failover
- **HAProxy** - Load balancer for read/write splitting

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │            HAProxy (LB)                 │
                    │  Port 5432 (R/W) → Primary              │
                    │  Port 5433 (R/O) → All nodes            │
                    │  Port 7000 (Stats)                      │
                    └─────────────────┬───────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
    ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
    │  PostgreSQL 17  │     │  PostgreSQL 17  │     │  PostgreSQL 17  │
    │    PRIMARY      │────▶│   STANDBY 1     │     │   STANDBY 2     │
    │   (repmgr)      │     │   (repmgr)      │◀────│   (repmgr)      │
    └─────────────────┘     └─────────────────┘     └─────────────────┘
           │                        ▲                       ▲
           │         Streaming      │                       │
           └────────Replication─────┴───────────────────────┘
```

## Features

- **Automatic Failover**: repmgrd monitors cluster health and promotes standby if primary fails
- **Read/Write Splitting**: HAProxy routes writes to primary, reads to all nodes
- **Health Checks**: Custom HTTP endpoints for HAProxy to detect node status
- **Connection Pooling**: HAProxy manages connections efficiently
- **Monitoring**: HAProxy stats dashboard, repmgr cluster status commands

## Prerequisites

- AWS account with appropriate permissions
- Terraform >= 1.0
- Ansible >= 2.15
- SSH key pair (generated automatically)

## Quick Start

### 1. Clone and Configure

```bash
cd pg-ha-cluster/terraform

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

**Required variables in `terraform.tfvars`**:

```hcl
aws_region     = "us-east-1"
project_name   = "pg-ha-cluster"
allowed_ssh_cidrs = ["YOUR_IP/32"]  # Restrict this!

# Strong passwords
repmgr_password        = "your-strong-repmgr-password"
postgres_password      = "your-strong-postgres-password"
haproxy_stats_password = "your-strong-stats-password"
```

### 2. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy
terraform apply
```

### 3. Configure Cluster with Ansible

```bash
cd ../ansible

# Install required Ansible collections
ansible-galaxy install -r requirements.yml

# Run the playbook
ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```

### 4. Verify Deployment

```bash
# Check cluster status
ssh -i inventory/pg-ha-cluster-key.pem ubuntu@<primary-ip> \
    "sudo -u postgres repmgr cluster show"

# Expected output:
#  ID | Name         | Role    | Status    | Upstream | Location | Priority
# ----+--------------+---------+-----------+----------+----------+----------
#  1  | pg-primary   | primary | * running |          | default  | 100
#  2  | pg-standby-1 | standby |   running | pg-primary | default | 90
#  3  | pg-standby-2 | standby |   running | pg-primary | default | 80
```

## Connection Information

After deployment, Terraform outputs connection details:

```bash
terraform output connection_info
```

### Endpoints

| Service | Port | Description |
|---------|------|-------------|
| HAProxy R/W | 5432 | Read/Write (primary only) |
| HAProxy R/O | 5433 | Read-only (load balanced) |
| HAProxy Stats | 7000 | Monitoring dashboard |
| PostgreSQL Direct | 5432 | Direct node access |
| Health Check | 8008 | Node health endpoints |

### Connect to PostgreSQL via HAProxy

```bash
# Read-write connection (goes to primary)
psql -h <haproxy-ip> -p 5432 -U postgres -d postgres

# Read-only connection (load balanced)
psql -h <haproxy-ip> -p 5433 -U postgres -d postgres
```

### HAProxy Stats Dashboard

```
http://<haproxy-ip>:7000/stats
Username: admin
Password: <haproxy_stats_password from tfvars>
```

## Operations

### Check Cluster Status

```bash
# On any PostgreSQL node
sudo -u postgres repmgr cluster show
sudo -u postgres repmgr cluster crosscheck

# View replication lag
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
```

### Manual Failover

```bash
# On standby node you want to promote
sudo -u postgres repmgr standby switchover --siblings-follow

# Or force promotion (use with caution)
sudo -u postgres repmgr standby promote
```

### Rejoin Failed Primary as Standby

```bash
# After old primary comes back online
sudo -u postgres repmgr node rejoin -d 'host=<new-primary> dbname=repmgr user=repmgr' --force-rewind
```

### Health Check Endpoints

```bash
# Check if node is primary
curl http://<node-ip>:8008/primary

# Check if node can accept reads
curl http://<node-ip>:8008/replica

# Detailed health info
curl http://<node-ip>:8008/health
```

## Directory Structure

```
pg-ha-cluster/
├── terraform/
│   ├── main.tf              # Main infrastructure
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Output values
│   ├── terraform.tfvars.example
│   └── templates/
│       ├── inventory.tftpl  # Ansible inventory template
│       └── group_vars.tftpl # Ansible vars template
│
└── ansible/
    ├── ansible.cfg          # Ansible configuration
    ├── requirements.yml     # Galaxy dependencies
    ├── inventory/           # Generated by Terraform
    ├── group_vars/          # Generated by Terraform
    ├── playbooks/
    │   └── site.yml         # Main playbook
    └── roles/
        ├── common/          # Base system configuration
        ├── postgresql/      # PostgreSQL 17 installation
        ├── repmgr/          # repmgr configuration
        ├── pg_healthcheck/  # HTTP health endpoints
        └── haproxy/         # Load balancer
```

## Customization

### Instance Types

Edit `terraform.tfvars`:

```hcl
pg_instance_type      = "r6i.large"   # Memory-optimized for production
haproxy_instance_type = "t3.medium"
pg_volume_size        = 100           # GB
```

### PostgreSQL Configuration

Edit `ansible/roles/postgresql/defaults/main.yml`:

```yaml
postgresql_shared_buffers: "4GB"
postgresql_effective_cache_size: "12GB"
postgresql_max_connections: 500
```

### HAProxy Tuning

Edit `ansible/roles/haproxy/defaults/main.yml`:

```yaml
haproxy_maxconn_global: 10000
haproxy_maxconn_backend: 2000
haproxy_timeout_client: "1h"
```

## Security Considerations

1. **Restrict `allowed_ssh_cidrs`** to your IP only
2. **Use strong passwords** (consider AWS Secrets Manager)
3. **Enable SSL/TLS** for PostgreSQL connections in production
4. **Use private subnets** with NAT gateway for production
5. **Enable encryption at rest** (already enabled for EBS)
6. **Review pg_hba.conf** and restrict access appropriately

## Troubleshooting

### Replication Not Working

```bash
# Check replication status on primary
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# Check standby status
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"

# View repmgr logs
sudo tail -f /var/log/repmgr/repmgr.log
```

### HAProxy Backend Down

```bash
# Test health check endpoint directly
curl -v http://<node-ip>:8008/primary

# Check HAProxy logs
sudo journalctl -u haproxy -f

# Verify PostgreSQL is listening
sudo ss -tlnp | grep 5432
```

### Connection Issues

```bash
# Test direct PostgreSQL connection
psql -h <node-ip> -U postgres -d postgres

# Check pg_hba.conf
sudo cat /etc/postgresql/17/main/pg_hba.conf

# View PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-17-main.log
```

## Cleanup

```bash
cd terraform
terraform destroy
```

## License

MIT

## Contributing

Pull requests welcome! Please ensure:
- Terraform validates: `terraform validate`
- Ansible syntax check: `ansible-playbook --syntax-check playbooks/site.yml`
- Follow existing code style
