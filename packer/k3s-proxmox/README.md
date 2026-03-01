# Packer — k3s Proxmox VM Templates

Builds Proxmox VM templates with k3s (server or agent) pre-installed on Debian 12 (Bookworm).

These templates are then cloned by Terraform (see `terraform/k3s-proxmox/`) to create actual k3s cluster nodes.

## Prerequisites

- [Packer](https://developer.hashicorp.com/packer/install) >= 1.10
- Proxmox VE >= 8.0
- Debian 12 netinst ISO uploaded to Proxmox storage (default: `local:iso/debian-12-amd64-netinst.iso`)
- A Proxmox API token with VM creation permissions

### Proxmox API Token Setup

On your Proxmox host:

```bash
# Create a dedicated user for automation
pveum useradd packer@pam -comment "Packer automation"
pveum passwd packer@pam

# Create an API token (save the secret — it's shown only once)
pveum user token add packer@pam packer-token --privsep=0

# Grant permissions
pveum aclmod / -user packer@pam -role PVEVMAdmin
pveum aclmod /storage -user packer@pam -role PVEDatastoreUser
```

### Download the Debian 12 ISO

```bash
# On the Proxmox host, download the ISO into the default storage
cd /var/lib/vz/template/iso/
wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.9.0-amd64-netinst.iso
```

## Files

```
k3s-server.pkr.hcl    # Server template build definition
k3s-agent.pkr.hcl     # Agent template build definition
variables.pkr.hcl     # Shared variables (Proxmox connection, VM specs)
http/
  preseed.cfg          # Debian unattended install configuration
files/
  k3s-install.sh       # Main provisioning script (installs k3s, k9s, Tailscale, Helm)
  config-server.yaml   # k3s server config template (envsubst placeholders)
  config-agent.yaml    # k3s agent config template (envsubst placeholders)
```

## Usage

### 1. Create a variables file

```bash
cp <<'EOF' > k3s-proxmox.pkrvars.hcl
proxmox_api_url          = "https://your-proxmox-host:8006/api2/json"
proxmox_api_token_id     = "packer@pam!packer-token"
proxmox_api_token_secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
proxmox_node             = "pve"
iso_file                 = "local:iso/debian-12.9.0-amd64-netinst.iso"
EOF
```

> **Note:** This file contains secrets. It is gitignored via `*.pkrvars.hcl`.

### 2. Initialize Packer plugins

```bash
packer init .
```

### 3. Build the server template

```bash
packer build -var-file=k3s-proxmox.pkrvars.hcl k3s-server.pkr.hcl
```

### 4. Build the agent template

```bash
packer build -var-file=k3s-proxmox.pkrvars.hcl k3s-agent.pkr.hcl
```

### 5. Verify in Proxmox

After each build completes, you should see a new VM template in the Proxmox UI:

- **VM 9000** — `k3s-server-template`
- **VM 9001** — `k3s-agent-template`

## What Gets Installed

Both templates include:

| Tool | Purpose |
|------|---------|
| k3s | Lightweight Kubernetes (server or agent mode) |
| k9s | Terminal-based Kubernetes UI |
| Tailscale | Mesh VPN for hybrid cluster networking |
| Helm | Kubernetes package manager |
| WireGuard | VPN kernel module (for Tailscale/flannel) |
| cloud-init | First-boot configuration (hostname, SSH keys, network) |
| qemu-guest-agent | Proxmox VM management integration |
| open-iscsi, nfs-common | Storage support for Longhorn/NFS CSI |

k3s is installed but **stopped and disabled** — it gets configured and started on first boot via cloud-init (managed by Terraform).

## Customization

| Variable | Default | Description |
|----------|---------|-------------|
| `proxmox_node` | `pve` | Proxmox node to build on |
| `vm_cores` | `2` | CPU cores |
| `vm_memory` | `2048` | Memory (MB) |
| `vm_disk_size` | `20G` | Root disk size |
| `vm_bridge` | `vmbr0` | Network bridge |
| `server_template_id` | `9000` | VM ID for server template |
| `agent_template_id` | `9001` | VM ID for agent template |
| `disk_storage_pool` | `local-lvm` | Storage pool for VM disks |

See `variables.pkr.hcl` for the full list.
