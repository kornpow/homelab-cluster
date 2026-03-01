packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.1"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ──────────────────────────────────────────────
# Proxmox connection
# ──────────────────────────────────────────────
variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API endpoint (e.g. https://pve.example.com:8006/api2/json)"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "API token ID (e.g. packer@pam!packer-token)"
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "API token secret"
}

variable "proxmox_skip_tls_verify" {
  type        = bool
  default     = true
  description = "Skip TLS verification for self-signed Proxmox certs"
}

# ──────────────────────────────────────────────
# Proxmox target
# ──────────────────────────────────────────────
variable "proxmox_node" {
  type        = string
  default     = "pve"
  description = "Proxmox node name to build on"
}

variable "iso_storage_pool" {
  type        = string
  default     = "local"
  description = "Proxmox storage pool that holds ISO images"
}

variable "disk_storage_pool" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage pool for VM disks"
}

# ──────────────────────────────────────────────
# Debian ISO
# ──────────────────────────────────────────────
variable "iso_file" {
  type        = string
  default     = "local:iso/debian-12-amd64-netinst.iso"
  description = "Path to the Debian 12 ISO in Proxmox storage (e.g. local:iso/debian-12-amd64-netinst.iso)"
}

variable "iso_checksum" {
  type        = string
  default     = "none"
  description = "ISO checksum (sha256). Set to 'none' to skip verification."
}

# ──────────────────────────────────────────────
# VM hardware
# ──────────────────────────────────────────────
variable "vm_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores for the template VM"
}

variable "vm_memory" {
  type        = number
  default     = 2048
  description = "Memory in MB for the template VM"
}

variable "vm_disk_size" {
  type        = string
  default     = "20G"
  description = "Root disk size for the template VM"
}

# ──────────────────────────────────────────────
# Networking
# ──────────────────────────────────────────────
variable "vm_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Proxmox network bridge"
}

# ──────────────────────────────────────────────
# Template IDs
# ──────────────────────────────────────────────
variable "server_template_id" {
  type        = number
  default     = 9000
  description = "Proxmox VM ID for the k3s server template"
}

variable "agent_template_id" {
  type        = number
  default     = 9001
  description = "Proxmox VM ID for the k3s agent template"
}

# ──────────────────────────────────────────────
# SSH
# ──────────────────────────────────────────────
variable "ssh_username" {
  type        = string
  default     = "debian"
  description = "SSH user created by the preseed/cloud-init"
}

variable "ssh_password" {
  type        = string
  default     = "packer"
  sensitive   = true
  description = "Temporary SSH password used during build (overwritten by cloud-init on first boot)"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}
