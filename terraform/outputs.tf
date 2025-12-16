output "pg_primary_public_ip" {
  description = "Public IP of PostgreSQL primary"
  value       = aws_instance.pg_primary.public_ip
}

output "pg_primary_private_ip" {
  description = "Private IP of PostgreSQL primary"
  value       = aws_instance.pg_primary.private_ip
}

output "pg_standby_public_ips" {
  description = "Public IPs of PostgreSQL standbys"
  value       = aws_instance.pg_standby[*].public_ip
}

output "pg_standby_private_ips" {
  description = "Private IPs of PostgreSQL standbys"
  value       = aws_instance.pg_standby[*].private_ip
}

output "haproxy_public_ip" {
  description = "Public IP of HAProxy load balancer"
  value       = aws_instance.haproxy.public_ip
}

output "haproxy_private_ip" {
  description = "Private IP of HAProxy load balancer"
  value       = aws_instance.haproxy.private_ip
}

output "ssh_private_key_file" {
  description = "Path to SSH private key"
  value       = local_file.private_key.filename
}

output "connection_info" {
  description = "Connection information"
  value = {
    ssh_to_primary    = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.pg_primary.public_ip}"
    ssh_to_standby_1  = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.pg_standby[0].public_ip}"
    ssh_to_standby_2  = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.pg_standby[1].public_ip}"
    ssh_to_haproxy    = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.haproxy.public_ip}"
    haproxy_stats     = "http://${aws_instance.haproxy.public_ip}:7000/stats"
    pg_readwrite_port = "${aws_instance.haproxy.public_ip}:5432"
    pg_readonly_port  = "${aws_instance.haproxy.public_ip}:5433"
  }
}

output "ansible_command" {
  description = "Command to run Ansible playbook"
  value       = "cd ../ansible && ansible-playbook -i inventory/hosts.ini playbooks/site.yml"
}
