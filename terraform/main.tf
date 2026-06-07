terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

locals {
  deploy_aws = var.cloud_provider == "aws"
  deploy_gcp = var.cloud_provider == "gcp"

  default_pg_instance_type    = local.deploy_aws ? "i7ie.4xlarge" : "c4d-standard-16"
  default_proxy_instance_type = local.deploy_aws ? "c7i.4xlarge" : "c4-standard-16"

  pg_instance_type    = coalesce(var.pg_instance_type, local.default_pg_instance_type)
  proxy_instance_type = coalesce(var.proxy_instance_type, local.default_proxy_instance_type)

  proxy_client_ports_by_type = {
    haproxy  = [5432, 5433]
    pgpool   = [5432]
    proxysql = [5432]
    pgcat    = [5432]
  }
  proxy_admin_ports_by_type = {
    haproxy  = [7000]
    pgpool   = [9898]
    proxysql = [6032]
    pgcat    = [9930]
  }
  proxy_allowed_ports = toset(concat(
    local.proxy_client_ports_by_type[var.proxy_type],
    local.proxy_admin_ports_by_type[var.proxy_type],
  ))
  proxy_pg_rw_port = local.proxy_client_ports_by_type[var.proxy_type][0]
  proxy_pg_ro_port = var.proxy_type == "haproxy" ? 5433 : 0
  proxy_admin_port = local.proxy_admin_ports_by_type[var.proxy_type][0]
  proxy_private_vip = var.proxy_vip != "" ? var.proxy_vip : (
    var.proxy_count == 2 ? cidrhost(var.public_subnet_cidr, var.proxy_vip_hostnum) : ""
  )

  common_tags = var.owner == "" ? {} : {
    Owner = var.owner
  }

  common_labels = var.owner == "" ? {} : {
    owner = substr(regexreplace(lower(var.owner), "[^a-z0-9_-]", "_"), 0, 63)
  }

  aws_vpc_id    = var.create_network ? try(aws_vpc.pg_cluster[0].id, "") : var.existing_vpc_id
  aws_subnet_id = var.create_network ? try(aws_subnet.public[0].id, "") : var.existing_subnet_id

  gcp_pg_tag        = "${var.project_name}-pg"
  gcp_proxy_tag     = "${var.project_name}-proxy"
  gcp_network       = var.create_network ? try(google_compute_network.pg_cluster[0].self_link, "") : var.existing_gcp_network
  gcp_subnetwork    = var.create_network ? try(google_compute_subnetwork.public[0].self_link, "") : var.existing_gcp_subnetwork
  gcp_machine_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"

  pg_primary_public_ip = local.deploy_aws ? try(aws_instance.pg_primary[0].public_ip, "") : try(google_compute_instance.pg_primary[0].network_interface[0].access_config[0].nat_ip, "")
  pg_primary_private_ip = local.deploy_aws ? try(aws_instance.pg_primary[0].private_ip, "") : try(
    google_compute_instance.pg_primary[0].network_interface[0].network_ip,
    ""
  )
  pg_standby_public_ips = local.deploy_aws ? aws_instance.pg_standby[*].public_ip : [
    for instance in google_compute_instance.pg_standby : instance.network_interface[0].access_config[0].nat_ip
  ]
  pg_standby_private_ips = local.deploy_aws ? aws_instance.pg_standby[*].private_ip : [
    for instance in google_compute_instance.pg_standby : instance.network_interface[0].network_ip
  ]
  proxy_public_ips = local.deploy_aws ? aws_instance.proxy[*].public_ip : [
    for instance in google_compute_instance.proxy : instance.network_interface[0].access_config[0].nat_ip
  ]
  proxy_private_ips = local.deploy_aws ? aws_instance.proxy[*].private_ip : [
    for instance in google_compute_instance.proxy : instance.network_interface[0].network_ip
  ]
  proxy_public_vip = local.deploy_aws ? try(aws_eip.proxy_public_vip[0].public_ip, "") : try(google_compute_address.proxy_public_vip[0].address, "")
}

data "aws_ami" "ubuntu" {
  count       = local.deploy_aws ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "pg_cluster" {
  count                = local.deploy_aws && var.create_network ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge({
    Name = "${var.project_name}-vpc"
  }, local.common_tags)
}

resource "aws_internet_gateway" "pg_cluster" {
  count  = local.deploy_aws && var.create_network ? 1 : 0
  vpc_id = aws_vpc.pg_cluster[0].id

  tags = merge({
    Name = "${var.project_name}-igw"
  }, local.common_tags)
}

resource "aws_subnet" "public" {
  count                   = local.deploy_aws && var.create_network ? 1 : 0
  vpc_id                  = aws_vpc.pg_cluster[0].id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = merge({
    Name = "${var.project_name}-public-subnet"
  }, local.common_tags)
}

resource "aws_route_table" "public" {
  count  = local.deploy_aws && var.create_network ? 1 : 0
  vpc_id = aws_vpc.pg_cluster[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pg_cluster[0].id
  }

  tags = merge({
    Name = "${var.project_name}-public-rt"
  }, local.common_tags)
}

resource "aws_route_table_association" "public" {
  count          = local.deploy_aws && var.create_network ? 1 : 0
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_security_group" "postgresql" {
  count       = local.deploy_aws ? 1 : 0
  name        = "${var.project_name}-postgresql-sg"
  description = "Security group for PostgreSQL cluster nodes"
  vpc_id      = local.aws_vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL internal"
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "PostgreSQL external"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Internal cluster traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge({
    Name = "${var.project_name}-postgresql-sg"
  }, local.common_tags)
}

resource "aws_security_group" "proxy" {
  count       = local.deploy_aws ? 1 : 0
  name        = "${var.project_name}-proxy-sg"
  description = "Security group for PostgreSQL proxy"
  vpc_id      = local.aws_vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  dynamic "ingress" {
    for_each = local.proxy_allowed_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidrs
      description = "PostgreSQL proxy port ${ingress.value}"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge({
    Name = "${var.project_name}-proxy-sg"
  }, local.common_tags)
}

resource "aws_eip" "proxy_public_vip" {
  count  = local.deploy_aws && var.create_proxy_public_vip ? 1 : 0
  domain = "vpc"

  tags = merge({
    Name = "${var.project_name}-proxy-public-vip"
  }, local.common_tags)
}

resource "google_compute_network" "pg_cluster" {
  count                   = local.deploy_gcp && var.create_network ? 1 : 0
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public" {
  count         = local.deploy_gcp && var.create_network ? 1 : 0
  name          = "${var.project_name}-subnet"
  ip_cidr_range = var.public_subnet_cidr
  network       = google_compute_network.pg_cluster[0].self_link
  region        = var.gcp_region
}

resource "google_compute_firewall" "ssh" {
  count   = local.deploy_gcp ? 1 : 0
  name    = "${var.project_name}-ssh"
  network = local.gcp_network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = [local.gcp_pg_tag, local.gcp_proxy_tag]
}

resource "google_compute_firewall" "postgresql_internal" {
  count   = local.deploy_gcp ? 1 : 0
  name    = "${var.project_name}-postgresql-internal"
  network = local.gcp_network

  allow {
    protocol = "all"
  }

  source_ranges = [var.vpc_cidr]
  target_tags   = [local.gcp_pg_tag, local.gcp_proxy_tag]
}

resource "google_compute_firewall" "postgresql_external" {
  count   = local.deploy_gcp ? 1 : 0
  name    = "${var.project_name}-postgresql-external"
  network = local.gcp_network

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = [local.gcp_pg_tag]
}

resource "google_compute_firewall" "proxy" {
  count   = local.deploy_gcp ? 1 : 0
  name    = "${var.project_name}-proxy"
  network = local.gcp_network

  allow {
    protocol = "tcp"
    ports    = [for port in local.proxy_allowed_ports : tostring(port)]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = [local.gcp_proxy_tag]
}

resource "google_compute_address" "proxy_public_vip" {
  count  = local.deploy_gcp && var.create_proxy_public_vip ? 1 : 0
  name   = "${var.project_name}-proxy-public-vip"
  region = var.gcp_region
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "pg_cluster" {
  count      = local.deploy_aws ? 1 : 0
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh.public_key_openssh

  tags = merge({
    Name = "${var.project_name}-key"
  }, local.common_tags)
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/../ansible/inventory/${var.project_name}-key.pem"
  file_permission = "0600"
}

resource "aws_instance" "pg_primary" {
  count                  = local.deploy_aws ? 1 : 0
  ami                    = data.aws_ami.ubuntu[0].id
  instance_type          = local.pg_instance_type
  key_name               = aws_key_pair.pg_cluster[0].key_name
  subnet_id              = local.aws_subnet_id
  vpc_security_group_ids = [aws_security_group.postgresql[0].id]

  root_block_device {
    volume_size = var.pg_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge({
    Name = "${var.project_name}-pg-primary"
    Role = "primary"
  }, local.common_tags)
}

resource "aws_instance" "pg_standby" {
  count                  = local.deploy_aws ? 2 : 0
  ami                    = data.aws_ami.ubuntu[0].id
  instance_type          = local.pg_instance_type
  key_name               = aws_key_pair.pg_cluster[0].key_name
  subnet_id              = local.aws_subnet_id
  vpc_security_group_ids = [aws_security_group.postgresql[0].id]

  root_block_device {
    volume_size = var.pg_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge({
    Name = "${var.project_name}-pg-standby-${count.index + 1}"
    Role = "standby"
  }, local.common_tags)
}

resource "aws_instance" "proxy" {
  count                  = local.deploy_aws ? var.proxy_count : 0
  ami                    = data.aws_ami.ubuntu[0].id
  instance_type          = local.proxy_instance_type
  key_name               = aws_key_pair.pg_cluster[0].key_name
  subnet_id              = local.aws_subnet_id
  vpc_security_group_ids = [aws_security_group.proxy[0].id, aws_security_group.postgresql[0].id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge({
    Name = "${var.project_name}-proxy-${count.index + 1}"
    Role = "proxy"
    Type = var.proxy_type
  }, local.common_tags)
}

resource "aws_eip_association" "proxy_public_vip" {
  count         = local.deploy_aws && var.create_proxy_public_vip ? 1 : 0
  allocation_id = aws_eip.proxy_public_vip[0].id
  instance_id   = aws_instance.proxy[0].id
}

resource "google_compute_instance" "pg_primary" {
  count        = local.deploy_gcp ? 1 : 0
  name         = "${var.project_name}-pg-primary"
  machine_type = local.pg_instance_type
  zone         = var.gcp_zone
  tags         = [local.gcp_pg_tag]
  labels       = merge({ role = "primary" }, local.common_labels)

  boot_disk {
    initialize_params {
      image = local.gcp_machine_image
      size  = var.pg_volume_size
      type  = "pd-balanced"
    }
  }

  dynamic "scratch_disk" {
    for_each = range(var.enable_local_nvme ? var.gcp_pg_local_ssd_count : 0)
    content {
      interface = "NVME"
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.ssh.public_key_openssh}"
  }

  network_interface {
    subnetwork = local.gcp_subnetwork

    access_config {
    }
  }
}

resource "google_compute_instance" "pg_standby" {
  count        = local.deploy_gcp ? 2 : 0
  name         = "${var.project_name}-pg-standby-${count.index + 1}"
  machine_type = local.pg_instance_type
  zone         = var.gcp_zone
  tags         = [local.gcp_pg_tag]
  labels       = merge({ role = "standby" }, local.common_labels)

  boot_disk {
    initialize_params {
      image = local.gcp_machine_image
      size  = var.pg_volume_size
      type  = "pd-balanced"
    }
  }

  dynamic "scratch_disk" {
    for_each = range(var.enable_local_nvme ? var.gcp_pg_local_ssd_count : 0)
    content {
      interface = "NVME"
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.ssh.public_key_openssh}"
  }

  network_interface {
    subnetwork = local.gcp_subnetwork

    access_config {
      nat_ip = count.index == 0 ? try(google_compute_address.proxy_public_vip[0].address, null) : null
    }
  }
}

resource "google_compute_instance" "proxy" {
  count        = local.deploy_gcp ? var.proxy_count : 0
  name         = "${var.project_name}-proxy-${count.index + 1}"
  machine_type = local.proxy_instance_type
  zone         = var.gcp_zone
  tags         = [local.gcp_proxy_tag, local.gcp_pg_tag]
  labels       = merge({ role = "proxy", type = var.proxy_type }, local.common_labels)

  boot_disk {
    initialize_params {
      image = local.gcp_machine_image
      size  = 20
      type  = "pd-balanced"
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.ssh.public_key_openssh}"
  }

  network_interface {
    subnetwork = local.gcp_subnetwork

    access_config {
    }
  }
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    pg_primary_ip          = local.pg_primary_public_ip
    pg_primary_private_ip  = local.pg_primary_private_ip
    pg_standby_ips         = local.pg_standby_public_ips
    pg_standby_private_ips = local.pg_standby_private_ips
    proxy_ips              = local.proxy_public_ips
    proxy_private_ips      = local.proxy_private_ips
    ssh_key_file           = "${var.project_name}-key.pem"
    ssh_user               = "ubuntu"
  })
  filename = "${path.module}/../ansible/inventory/hosts.ini"
}

resource "local_file" "ansible_group_vars" {
  content = templatefile("${path.module}/templates/group_vars.tftpl", {
    cloud_provider         = var.cloud_provider
    vpc_cidr               = var.vpc_cidr
    proxy_type             = var.proxy_type
    proxy_count            = var.proxy_count
    proxy_private_vip      = local.proxy_private_vip
    proxy_public_vip       = local.proxy_public_vip
    proxy_pg_rw_port       = local.proxy_pg_rw_port
    proxy_pg_ro_port       = local.proxy_pg_ro_port
    proxy_admin_port       = local.proxy_admin_port
    postgresql_version     = var.postgresql_version
    pg_primary_private_ip  = local.pg_primary_private_ip
    pg_standby_private_ips = local.pg_standby_private_ips
    proxy_private_ips      = local.proxy_private_ips
    enable_local_nvme      = var.enable_local_nvme
    repmgr_password        = var.repmgr_password
    postgres_password      = var.postgres_password
    proxy_admin_password   = var.proxy_admin_password
  })
  filename = "${path.module}/../ansible/inventory/group_vars/all.yml"
}
