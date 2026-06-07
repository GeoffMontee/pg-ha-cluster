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

output "haproxy_public_ip" {
  description = "Public IP of HAProxy load balancer"
  value       = local.haproxy_public_ip
}

output "haproxy_private_ip" {
  description = "Private IP of HAProxy load balancer"
  value       = local.haproxy_private_ip
}

output "ssh_private_key_file" {
  description = "Path to SSH private key"
  value       = local_file.private_key.filename
}

output "connection_info" {
  description = "Connection information"
  value = {
    ssh_to_primary    = "ssh -i ${local_file.private_key.filename} ubuntu@${local.pg_primary_public_ip}"
    ssh_to_standby_1  = "ssh -i ${local_file.private_key.filename} ubuntu@${local.pg_standby_public_ips[0]}"
    ssh_to_standby_2  = "ssh -i ${local_file.private_key.filename} ubuntu@${local.pg_standby_public_ips[1]}"
    ssh_to_haproxy    = "ssh -i ${local_file.private_key.filename} ubuntu@${local.haproxy_public_ip}"
    haproxy_stats     = "http://${local.haproxy_public_ip}:7000/stats"
    pg_readwrite_port = "${local.haproxy_public_ip}:5432"
    pg_readonly_port  = "${local.haproxy_public_ip}:5433"
  }
}

output "ansible_command" {
  description = "Command to run Ansible playbook"
  value       = "cd ../ansible && ansible-playbook -i inventory/hosts.ini playbooks/site.yml"
}
