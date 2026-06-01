output "control_plane_ip" {
  description = "Public IP of the control-plane node."
  value       = linode_instance.control_plane.ip_address
}

output "worker_ips" {
  description = "Public IPs of the worker node(s)."
  value       = linode_instance.worker[*].ip_address
}

output "inventory_path" {
  description = "Where the Ansible inventory was written."
  value       = local_file.ansible_inventory.filename
}
