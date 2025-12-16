terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
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

# Data source for latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
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

# VPC
resource "aws_vpc" "pg_cluster" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "pg_cluster" {
  vpc_id = aws_vpc.pg_cluster.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.pg_cluster.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.pg_cluster.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pg_cluster.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group for PostgreSQL nodes
resource "aws_security_group" "postgresql" {
  name        = "${var.project_name}-postgresql-sg"
  description = "Security group for PostgreSQL cluster nodes"
  vpc_id      = aws_vpc.pg_cluster.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  # PostgreSQL
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL internal"
  }

  # PostgreSQL from allowed external
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "PostgreSQL external"
  }

  # repmgrd communication
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
    description = "repmgr replication"
  }

  # All internal traffic within the cluster
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Internal cluster traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.project_name}-postgresql-sg"
  }
}

# Security Group for HAProxy
resource "aws_security_group" "haproxy" {
  name        = "${var.project_name}-haproxy-sg"
  description = "Security group for HAProxy load balancer"
  vpc_id      = aws_vpc.pg_cluster.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  # HAProxy PostgreSQL frontend (read-write)
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "PostgreSQL read-write port"
  }

  # HAProxy PostgreSQL frontend (read-only)
  ingress {
    from_port   = 5433
    to_port     = 5433
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "PostgreSQL read-only port"
  }

  # HAProxy Stats
  ingress {
    from_port   = 7000
    to_port     = 7000
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "HAProxy stats"
  }

  # Allow traffic to PostgreSQL nodes
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.project_name}-haproxy-sg"
  }
}

# Generate SSH key pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "pg_cluster" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh.public_key_openssh

  tags = {
    Name = "${var.project_name}-key"
  }
}

# Save private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/../ansible/inventory/${var.project_name}-key.pem"
  file_permission = "0600"
}

# PostgreSQL Primary Instance
resource "aws_instance" "pg_primary" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.pg_instance_type
  key_name               = aws_key_pair.pg_cluster.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.postgresql.id]

  root_block_device {
    volume_size = var.pg_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-pg-primary"
    Role = "primary"
  }
}

# PostgreSQL Standby Instances
resource "aws_instance" "pg_standby" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.pg_instance_type
  key_name               = aws_key_pair.pg_cluster.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.postgresql.id]

  root_block_device {
    volume_size = var.pg_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-pg-standby-${count.index + 1}"
    Role = "standby"
  }
}

# HAProxy Instance
resource "aws_instance" "haproxy" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.haproxy_instance_type
  key_name               = aws_key_pair.pg_cluster.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.haproxy.id, aws_security_group.postgresql.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-haproxy"
    Role = "loadbalancer"
  }
}

# Generate Ansible inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    pg_primary_ip     = aws_instance.pg_primary.public_ip
    pg_primary_private_ip = aws_instance.pg_primary.private_ip
    pg_standby_ips    = aws_instance.pg_standby[*].public_ip
    pg_standby_private_ips = aws_instance.pg_standby[*].private_ip
    haproxy_ip        = aws_instance.haproxy.public_ip
    haproxy_private_ip = aws_instance.haproxy.private_ip
    ssh_key_file      = "${var.project_name}-key.pem"
    ssh_user          = "ubuntu"
  })
  filename = "${path.module}/../ansible/inventory/hosts.ini"
}

# Generate Ansible group_vars
resource "local_file" "ansible_group_vars" {
  content = templatefile("${path.module}/templates/group_vars.tftpl", {
    pg_primary_private_ip     = aws_instance.pg_primary.private_ip
    pg_standby_private_ips    = aws_instance.pg_standby[*].private_ip
    haproxy_private_ip        = aws_instance.haproxy.private_ip
    repmgr_password           = var.repmgr_password
    postgres_password         = var.postgres_password
    haproxy_stats_password    = var.haproxy_stats_password
  })
  filename = "${path.module}/../ansible/group_vars/all.yml"
}
