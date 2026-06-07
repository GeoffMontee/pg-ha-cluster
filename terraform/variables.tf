variable "cloud_provider" {
  description = "Cloud provider to deploy into. Valid values are aws or gcp."
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "gcp"], var.cloud_provider)
    error_message = "cloud_provider must be either aws or gcp."
  }
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "gcp_project_id" {
  description = "GCP project ID. Required when cloud_provider is gcp."
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region for the subnet"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for Compute Engine instances"
  type        = string
  default     = "us-central1-a"
}

variable "owner" {
  description = "Owner tag or label value"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "pg-ha-cluster"
}

variable "create_network" {
  description = "Create a new VPC/network and public subnet/subnetwork"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for the created VPC/network, or the internal CIDR to allow when using an existing network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the created public subnet/subnetwork"
  type        = string
  default     = "10.0.1.0/24"
}

variable "existing_vpc_id" {
  description = "Existing AWS VPC ID to use when create_network is false"
  type        = string
  default     = ""
}

variable "existing_subnet_id" {
  description = "Existing AWS subnet ID to use when create_network is false"
  type        = string
  default     = ""
}

variable "existing_gcp_network" {
  description = "Existing GCP VPC network name or self link to use when create_network is false"
  type        = string
  default     = ""
}

variable "existing_gcp_subnetwork" {
  description = "Existing GCP subnetwork name or self link to use when create_network is false"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH and connect to exposed services"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict this in production!
}

variable "pg_instance_type" {
  description = "Instance or machine type for PostgreSQL nodes. Defaults are cloud-specific."
  type        = string
  default     = null
}

variable "proxy_type" {
  description = "PostgreSQL proxy implementation. Valid values are haproxy, pgpool, proxysql, or pgcat."
  type        = string
  default     = "haproxy"

  validation {
    condition     = contains(["haproxy", "pgpool", "proxysql", "pgcat"], var.proxy_type)
    error_message = "proxy_type must be one of haproxy, pgpool, proxysql, or pgcat."
  }
}

variable "proxy_instance_type" {
  description = "Instance or machine type for the proxy node. Defaults are cloud-specific."
  type        = string
  default     = null
}

variable "proxy_count" {
  description = "Number of proxy nodes to deploy. Use 2 to enable keepalived VRRP with an explicit or generated private VIP."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2], var.proxy_count)
    error_message = "proxy_count must be 1 or 2."
  }
}

variable "proxy_vip" {
  description = "Explicit private VRRP virtual IP for two-node proxy HA. If empty and proxy_count is 2, Terraform derives one from public_subnet_cidr."
  type        = string
  default     = ""
}

variable "proxy_vip_hostnum" {
  description = "Host number inside public_subnet_cidr for the automatically generated private proxy VIP"
  type        = number
  default     = 50
}

variable "create_proxy_public_vip" {
  description = "Reserve a static public IP and attach it to the first proxy node"
  type        = bool
  default     = false
}

variable "postgresql_version" {
  description = "PostgreSQL major version to install"
  type        = string
  default     = "18"
}

variable "pg_volume_size" {
  description = "Root volume size in GB for PostgreSQL nodes"
  type        = number
  default     = 50
}

variable "enable_local_nvme" {
  description = "Mount local NVMe instance storage at /var/lib/postgresql on database nodes"
  type        = bool
  default     = true
}

variable "gcp_pg_local_ssd_count" {
  description = "Number of local SSD scratch disks to attach to each GCP PostgreSQL node"
  type        = number
  default     = 1
}

variable "repmgr_password" {
  description = "Password for repmgr database user"
  type        = string
  sensitive   = true
}

variable "postgres_password" {
  description = "Password for postgres superuser"
  type        = string
  sensitive   = true
}

variable "proxy_admin_password" {
  description = "Password for proxy administration endpoints"
  type        = string
  sensitive   = true
}
