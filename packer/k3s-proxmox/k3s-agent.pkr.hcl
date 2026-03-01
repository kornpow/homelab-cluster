# k3s-agent.pkr.hcl — Builds a Proxmox VM template with k3s agent pre-installed.
# Uses Debian 12 (Bookworm) as the base OS with cloud-init for first-boot config.

source "proxmox-iso" "k3s-agent" {
  # ── Proxmox connection ───────────────────────
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = var.proxmox_skip_tls_verify
  node                     = var.proxmox_node

  # ── VM settings ──────────────────────────────
  vm_id                = var.agent_template_id
  vm_name              = "k3s-agent-template"
  template_description = "k3s agent node — Debian 12 — built ${local.timestamp}"

  iso_file     = var.iso_file
  iso_checksum = var.iso_checksum
  unmount_iso  = true

  qemu_agent = true
  os         = "l26"

  cores  = var.vm_cores
  memory = var.vm_memory

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = var.vm_disk_size
    storage_pool = var.disk_storage_pool
    format       = "raw"
  }

  network_adapters {
    model  = "virtio"
    bridge = var.vm_bridge
  }

  cloud_init              = true
  cloud_init_storage_pool = var.disk_storage_pool

  # ── Preseed (unattended Debian install) ──────
  http_directory = "http"
  boot_wait      = "10s"
  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "hostname=k3s-agent ",
    "domain=local ",
    "interface=auto ",
    "<enter>"
  ]

  # ── SSH ──────────────────────────────────────
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "20m"
}

build {
  sources = ["source.proxmox-iso.k3s-agent"]

  provisioner "file" {
    source      = "files/"
    destination = "/home/debian"
  }

  provisioner "shell" {
    inline = ["chmod +x /home/debian/k3s-install.sh"]
  }

  provisioner "shell" {
    inline = ["/home/debian/k3s-install.sh agent"]
  }
}
