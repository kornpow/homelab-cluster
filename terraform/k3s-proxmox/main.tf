# ──────────────────────────────────────────────
# Locals
# ──────────────────────────────────────────────
locals {
  # Generate a random token if none provided (standalone cluster mode)
  k3s_token = var.k3s_token != "" ? var.k3s_token : random_password.k3s_token[0].result

  # Determine if this is a standalone cluster or joining an existing one
  is_standalone = var.k3s_server_url == ""

  # The first server's IP (used by agents and additional servers to join)
  first_server_ip = length(var.server_ips) > 0 ? split("/", var.server_ips[0])[0] : ""

  # k3s server URL: either the external one provided, or the first server's IP
  k3s_server_url = local.is_standalone ? (
    local.first_server_ip != "" ? "https://${local.first_server_ip}:6443" : ""
  ) : var.k3s_server_url

  # k3s install channel/version flag
  k3s_version_env = var.k3s_version != "" ? "INSTALL_K3S_VERSION='${var.k3s_version}'" : ""

  # Common k3s flags (includes Tailscale IP binding for proper multi-node networking)
  k3s_node_labels = "--node-label=instance=${var.node_label} --node-label=location=proxmox"
  k3s_extra_server_args = "--node-ip=$(tailscale ip -4) --flannel-iface=tailscale0"
  k3s_extra_agent_args = "--node-ip=$(tailscale ip -4) --flannel-iface=tailscale0"

  # Tailscale setup command (use list form to avoid shell quoting issues in cloud-init)
  tailscale_cmd = var.tailscale_auth_key != "" ? ["sudo", "tailscale", "up", "--authkey=${var.tailscale_auth_key}", "--accept-routes", "--accept-dns=false"] : ["echo", "Tailscale: no auth key provided, skipping auto-registration"]

  # Pre-compute the k3s install command for each server node (with Tailscale IP binding)
  server_k3s_cmd = [
    for i in range(var.server_count) :
    i == 0 && local.is_standalone
    ? "curl -sfL https://get.k3s.io | ${local.k3s_version_env} K3S_TOKEN='${local.k3s_token}' K3S_KUBECONFIG_MODE='644' INSTALL_K3S_EXEC='server --cluster-init ${local.k3s_node_labels} ${local.k3s_extra_server_args}' sh -s -"
    : "curl -sfL https://get.k3s.io | ${local.k3s_version_env} K3S_TOKEN='${local.k3s_token}' K3S_KUBECONFIG_MODE='644' INSTALL_K3S_EXEC='server --server=${local.k3s_server_url} ${local.k3s_node_labels} ${local.k3s_extra_server_args}' sh -s -"
  ]

  # k3s install command for agent nodes (with Tailscale IP binding)
  agent_k3s_cmd = "curl -sfL https://get.k3s.io | ${local.k3s_version_env} K3S_URL='${local.k3s_server_url}' K3S_TOKEN='${local.k3s_token}' INSTALL_K3S_EXEC='agent ${local.k3s_node_labels} ${local.k3s_extra_agent_args}' sh -s -"
}

# ──────────────────────────────────────────────
# Random token for standalone clusters
# ──────────────────────────────────────────────
resource "random_password" "k3s_token" {
  count   = var.k3s_token == "" ? 1 : 0
  length  = 48
  special = false
}

# ══════════════════════════════════════════════
# k3s SERVER nodes
# ══════════════════════════════════════════════
resource "proxmox_virtual_environment_vm" "k3s_server" {
  count     = var.server_count
  name      = "k3s-server-${count.index + 1}"
  node_name = var.proxmox_node
  vm_id     = var.vm_id_start + count.index

  clone {
    vm_id = var.server_template_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.server_cores
    type  = "host"
  }

  memory {
    dedicated = var.server_memory
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    size         = var.disk_size
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = length(var.server_ips) > count.index ? var.server_ips[count.index] : "dhcp"
        gateway = length(var.server_ips) > count.index ? var.vm_gateway : ""
      }
    }

    dns {
      servers = [var.nameserver]
    }

    user_account {
      username = var.ssh_user
      keys     = var.ssh_public_keys
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_config_server[count.index].id
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_data_file_id,
    ]
  }
}

# ── Cloud-init user-data for servers ─────────
resource "proxmox_virtual_environment_file" "cloud_config_server" {
  count        = var.server_count
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = join("\n", ["#cloud-config", yamlencode({
      hostname         = "k3s-server-${count.index + 1}"
      manage_etc_hosts = true
      users = [{
        name                = var.ssh_user
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        shell               = "/bin/bash"
        ssh_authorized_keys = var.ssh_public_keys
      }]
      runcmd = [
        # Wait for network connectivity before attempting downloads
        ["bash", "-c", "for i in $(seq 1 30); do curl -sf --connect-timeout 3 https://get.k3s.io > /dev/null 2>&1 && break; echo \"Waiting for network ($i/30)...\"; sleep 2; done"],
        local.tailscale_cmd,
        ["bash", "-c", local.server_k3s_cmd[count.index]],
      ]
    })])

    file_name = "k3s-server-${count.index + 1}-cloud-init.yaml"
  }
}

# ══════════════════════════════════════════════
# k3s AGENT nodes
# ══════════════════════════════════════════════
resource "proxmox_virtual_environment_vm" "k3s_agent" {
  count     = var.agent_count
  name      = "k3s-agent-${count.index + 1}"
  node_name = var.proxmox_node
  vm_id     = var.vm_id_start + 100 + count.index

  # Agents must wait for the first server to be ready
  depends_on = [proxmox_virtual_environment_vm.k3s_server]

  clone {
    vm_id = var.agent_template_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.agent_cores
    type  = "host"
  }

  memory {
    dedicated = var.agent_memory
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    size         = var.disk_size
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = length(var.agent_ips) > count.index ? var.agent_ips[count.index] : "dhcp"
        gateway = length(var.agent_ips) > count.index ? var.vm_gateway : ""
      }
    }

    dns {
      servers = [var.nameserver]
    }

    user_account {
      username = var.ssh_user
      keys     = var.ssh_public_keys
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_config_agent[count.index].id
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_data_file_id,
    ]
  }
}

# ── Cloud-init user-data for agents ──────────
resource "proxmox_virtual_environment_file" "cloud_config_agent" {
  count        = var.agent_count
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = join("\n", ["#cloud-config", yamlencode({
      hostname         = "k3s-agent-${count.index + 1}"
      manage_etc_hosts = true
      users = [{
        name                = var.ssh_user
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        shell               = "/bin/bash"
        ssh_authorized_keys = var.ssh_public_keys
      }]
      runcmd = [
        # Wait for network connectivity before attempting downloads
        ["bash", "-c", "for i in $(seq 1 30); do curl -sf --connect-timeout 3 https://get.k3s.io > /dev/null 2>&1 && break; echo \"Waiting for network ($i/30)...\"; sleep 2; done"],
        local.tailscale_cmd,
        ["bash", "-c", local.agent_k3s_cmd],
      ]
    })])

    file_name = "k3s-agent-${count.index + 1}-cloud-init.yaml"
  }
}
