# ──────────────────────────────────────────────
# Proxmox connection
# ──────────────────────────────────────────────
variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API endpoint (e.g. https://pve.example.com:8006/api2/json)"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "API token ID (e.g. terraform@pam!terraform-token)"
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

variable "proxmox_node" {
  type        = string
  default     = "pve"
  description = "Target Proxmox node name"
}

# ──────────────────────────────────────────────
# VM template references
# ──────────────────────────────────────────────
variable "server_template_id" {
  type        = number
  default     = 9000
  description = "Proxmox VM ID of the k3s server template (built by Packer)"
}

variable "agent_template_id" {
  type        = number
  default     = 9001
  description = "Proxmox VM ID of the k3s agent template (built by Packer)"
}

# ──────────────────────────────────────────────
# Cluster topology
# ──────────────────────────────────────────────
variable "server_count" {
  type        = number
  default     = 1
  description = "Number of k3s server (control plane) nodes to create"
}

variable "agent_count" {
  type        = number
  default     = 2
  description = "Number of k3s agent (worker) nodes to create"
}

# ──────────────────────────────────────────────
# VM hardware
# ──────────────────────────────────────────────
variable "server_cores" {
  type        = number
  default     = 2
  description = "CPU cores for server VMs"
}

variable "server_memory" {
  type        = number
  default     = 4096
  description = "Memory (MB) for server VMs"
}

variable "agent_cores" {
  type        = number
  default     = 2
  description = "CPU cores for agent VMs"
}

variable "agent_memory" {
  type        = number
  default     = 2048
  description = "Memory (MB) for agent VMs"
}

variable "disk_size" {
  type        = number
  default     = 20
  description = "Root disk size in GB"
}

variable "disk_storage" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage pool for VM disks"
}

# ──────────────────────────────────────────────
# Networking
# ──────────────────────────────────────────────
variable "vm_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Proxmox network bridge for VM NICs"
}

variable "vm_gateway" {
  type        = string
  description = "Default gateway for VMs (e.g. 192.168.1.1)"
}

variable "server_ips" {
  type        = list(string)
  default     = []
  description = "Static IPs for server nodes in CIDR (e.g. [\"192.168.1.50/24\"]). If empty, uses DHCP."
}

variable "agent_ips" {
  type        = list(string)
  default     = []
  description = "Static IPs for agent nodes in CIDR (e.g. [\"192.168.1.51/24\", \"192.168.1.52/24\"]). If empty, uses DHCP."
}

variable "nameserver" {
  type        = string
  default     = "1.1.1.1"
  description = "DNS nameserver for VMs"
}

# ──────────────────────────────────────────────
# SSH
# ──────────────────────────────────────────────
variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys to inject via cloud-init"
}

variable "ssh_user" {
  type        = string
  default     = "debian"
  description = "Default SSH user (matches the Packer template)"
}

# ──────────────────────────────────────────────
# k3s configuration
# ──────────────────────────────────────────────
variable "k3s_version" {
  type        = string
  default     = ""
  description = "k3s version to install (e.g. v1.30.2+k3s1). Empty = latest."
}

variable "k3s_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "k3s cluster token. If empty, a random token is generated for standalone clusters."
}

variable "k3s_server_url" {
  type        = string
  default     = ""
  description = "Existing k3s server URL to join (e.g. https://10.0.0.50:6443). If empty, creates a new standalone cluster."
}

variable "node_label" {
  type        = string
  default     = "proxmox"
  description = "Value for the 'instance' node label"
}

# ──────────────────────────────────────────────
# Tailscale
# ──────────────────────────────────────────────
variable "tailscale_auth_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Tailscale auth key for automatic node registration. If empty, Tailscale must be configured manually."
}

# ──────────────────────────────────────────────
# VM ID range
# ──────────────────────────────────────────────
variable "vm_id_start" {
  type        = number
  default     = 200
  description = "Starting VM ID for provisioned nodes (servers get vm_id_start+N, agents get vm_id_start+100+N)"
}
