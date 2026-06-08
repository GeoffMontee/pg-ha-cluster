# Agent Guidance

## Tests

- Add or update pytest tests under `test/` when changing `deploy_pg_ha_cluster.py` argument parsing, generated Terraform variables, validation rules, or command orchestration.
- Keep tests fast and local. Do not require Terraform, Ansible, cloud credentials, or network access for normal pytest coverage.
- Run targeted checks before finishing changes:
  - `python3 -m py_compile deploy_pg_ha_cluster.py test/test_deploy_pg_ha_cluster.py`
  - `python3 -m pytest test`
  - `terraform -chdir=terraform fmt -recursive`
  - `terraform -chdir=terraform validate`
  - `ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg" ansible-playbook --syntax-check -i "localhost," ansible/playbooks/site.yml`
- If a tool is unavailable locally, document what could not be run and why.

## Documentation

- Keep `README.md` aligned with the script-first workflow. `deploy_pg_ha_cluster.py` is the supported way to generate Terraform configuration.
- Document every user-facing CLI option when adding, removing, or renaming deploy script arguments.
- Update examples whenever defaults change, especially cloud provider defaults, PostgreSQL version, instance types, networking behavior, or secret handling.
- Treat generated Terraform variable files, Terraform state, SSH keys, and Ansible inventory as sensitive in documentation.
- For GCP service account authentication, store only file paths in generated variables. Never copy JSON key contents into repo files.

## Subcommand Behavior

- Preserve the three supported subcommands: `deploy`, `show`, and `destroy`.
- `deploy` should generate Terraform variables from CLI arguments and environment variables, run Terraform, then run Ansible unless explicitly skipped.
- `show` should display Terraform outputs and only attempt Ansible cluster status when inventory exists, unless status is skipped.
- `destroy` should destroy only Terraform-managed infrastructure and should not run Ansible.
- Keep cloud-specific behavior behind provider arguments and generated Terraform variables; avoid hardcoding AWS-only or GCP-only assumptions into shared paths.
- Keep proxy behavior generic in shared paths. Proxy-specific behavior belongs in `ansible/roles/haproxy`, `ansible/roles/pgpool`, `ansible/roles/proxysql`, or `ansible/roles/pgcat`.
- Keep two-proxy HA generic through `proxy_count`, `proxy_vip`, and the `keepalived` role. Do not make VRRP behavior specific to one proxy implementation.
- Keep private and public proxy VIP behavior distinct: the private VIP feeds keepalived/VRRP, while `--proxy-public-vip` reserves a cloud static public IP.
- Keep database nodes private by default. If `--public-db-nodes` is not set, generated inventory must use a jump host and Terraform-owned networks must provide NAT for database node egress.
- Prefer a created bastion as the database SSH jump host even when `--public-db-nodes` is set; this keeps Ansible on private database IPs when a bastion is available.
- When adding subcommand options, prefer explicit flags and test their generated config or command behavior.
