output "pg_primary_public_ip" {
  description = "Public IP of PostgreSQL primary"
  value       = local.pg_primary_public_ip
}

output "pg_primary_private_ip" {
  description = "Private IP of PostgreSQL primary"
  value       = local.pg_primary_private_ip
}

output "pg_standby_public_ips" {
  description = "Public IPs of PostgreSQL standbys"
  value       = local.pg_standby_public_ips
}

output "pg_standby_private_ips" {
  description = "Private IPs of PostgreSQL standbys"
  value       = local.pg_standby_private_ips
}

output "proxy_public_ips" {
  description = "Public IPs of PostgreSQL proxy nodes"
  value       = local.proxy_public_ips
}

output "proxy_private_ips" {
  description = "Private IPs of PostgreSQL proxy nodes"
  value       = local.proxy_private_ips
}

output "proxy_type" {
  description = "Configured PostgreSQL proxy implementation"
  value       = var.proxy_type
}

output "proxy_vip" {
  description = "VRRP virtual IP when two proxy nodes are deployed"
  value       = var.proxy_vip
}

output "ssh_private_key_file" {
  description = "Path to SSH private key"
  value       = local_file.private_key.filename
}

output "connection_info" {
  description = "Connection information"
  value = {
    ssh_to_primary   = "ssh -i ${local_file.private_key.filename} ubuntu@${local.pg_primary_public_ip}"
    ssh_to_standby_1 = "ssh -i ${local_file.private_key.filename} ubuntu@${local.pg_standby_public_ips[0]}"
    ssh_to_standby_2 = "ssh -i ${local_file.private_key.filename} ubuntu@${local.pg_standby_public_ips[1]}"
    ssh_to_proxy_1   = "ssh -i ${local_file.private_key.filename} ubuntu@${local.proxy_public_ips[0]}"
    ssh_to_proxy_2   = var.proxy_count == 2 ? "ssh -i ${local_file.private_key.filename} ubuntu@${local.proxy_public_ips[1]}" : null
    proxy_type       = var.proxy_type
    proxy_vip        = var.proxy_vip
    pg_proxy_port    = var.proxy_vip != "" ? "${var.proxy_vip}:${local.proxy_pg_rw_port}" : "${local.proxy_public_ips[0]}:${local.proxy_pg_rw_port}"
  }
}

output "ansible_command" {
  description = "Command to run Ansible playbook"
  value       = "cd ../ansible && ansible-playbook -i inventory/hosts.ini playbooks/site.yml"
}
