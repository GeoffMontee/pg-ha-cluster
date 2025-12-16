variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner tag value (required by AWS policy)"
  type        = string
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "pg-ha-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH and connect to services"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict this in production!
}

variable "pg_instance_type" {
  description = "EC2 instance type for PostgreSQL nodes"
  type        = string
  default     = "t3.medium"
}

variable "haproxy_instance_type" {
  description = "EC2 instance type for HAProxy node"
  type        = string
  default     = "t3.small"
}

variable "pg_volume_size" {
  description = "Root volume size in GB for PostgreSQL nodes"
  type        = number
  default     = 50
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

variable "haproxy_stats_password" {
  description = "Password for HAProxy stats page"
  type        = string
  sensitive   = true
}
