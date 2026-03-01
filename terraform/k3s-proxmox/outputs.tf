# ──────────────────────────────────────────────
# Server outputs
# ──────────────────────────────────────────────
output "server_names" {
  description = "Names of the k3s server VMs"
  value       = [for vm in proxmox_virtual_environment_vm.k3s_server : vm.name]
}

output "server_vm_ids" {
  description = "Proxmox VM IDs of the server nodes"
  value       = [for vm in proxmox_virtual_environment_vm.k3s_server : vm.vm_id]
}

output "server_ipv4_addresses" {
  description = "IPv4 addresses of the server nodes (from QEMU guest agent)"
  value       = [for vm in proxmox_virtual_environment_vm.k3s_server : vm.ipv4_addresses]
}

# ──────────────────────────────────────────────
# Agent outputs
# ──────────────────────────────────────────────
output "agent_names" {
  description = "Names of the k3s agent VMs"
  value       = [for vm in proxmox_virtual_environment_vm.k3s_agent : vm.name]
}

output "agent_vm_ids" {
  description = "Proxmox VM IDs of the agent nodes"
  value       = [for vm in proxmox_virtual_environment_vm.k3s_agent : vm.vm_id]
}

output "agent_ipv4_addresses" {
  description = "IPv4 addresses of the agent nodes (from QEMU guest agent)"
  value       = [for vm in proxmox_virtual_environment_vm.k3s_agent : vm.ipv4_addresses]
}

# ──────────────────────────────────────────────
# Cluster info
# ──────────────────────────────────────────────
output "k3s_server_url" {
  description = "k3s API server URL (use this to join additional nodes)"
  value       = local.k3s_server_url
}

output "k3s_token" {
  description = "k3s cluster join token"
  value       = local.k3s_token
  sensitive   = true
}

output "cluster_mode" {
  description = "Whether this is a standalone cluster or joined to an existing one"
  value       = local.is_standalone ? "standalone" : "joined (${var.k3s_server_url})"
}
