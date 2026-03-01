# k3s-server.pkr.hcl — Builds a Proxmox VM template with k3s server pre-installed.
# Uses Debian 13 (Trixie) as the base OS with cloud-init for first-boot config.

source "proxmox-iso" "k3s-server" {
  # ── Proxmox connection ───────────────────────
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = var.proxmox_skip_tls_verify
  node                     = var.proxmox_node

  # ── VM settings ──────────────────────────────
  vm_id                = var.server_template_id
  vm_name              = "k3s-server-template"
  template_description = "k3s server node — Debian 13 — built ${local.timestamp}"

  boot_iso {
    iso_file         = var.iso_file
    iso_checksum     = var.iso_checksum
    unmount          = true
  }

  boot       = "order=scsi0;ide2;net0"
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
    "hostname=k3s-server ",
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
  sources = ["source.proxmox-iso.k3s-server"]

  provisioner "shell" {
    inline = [
      "echo 'packer' | sudo -S sh -c 'echo \"debian ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/debian && chmod 440 /etc/sudoers.d/debian'",
      "sudo systemctl enable qemu-guest-agent || true",
      "sudo apt-get install -y cloud-init || true",
      "sudo systemctl enable cloud-init || true",
    ]
  }

  provisioner "file" {
    source      = "files/"
    destination = "/home/debian"
  }

  provisioner "shell" {
    inline = ["chmod +x /home/debian/k3s-install.sh"]
  }

  provisioner "shell" {
    inline = ["/home/debian/k3s-install.sh server"]
  }
}
