# Terraform — k3s Proxmox Cluster

Provisions k3s server and agent VMs on Proxmox by cloning templates built with Packer (see `packer/k3s-proxmox/`).

Supports two modes:
- **Standalone cluster** — creates a new k3s cluster entirely on Proxmox
- **Join existing cluster** — adds Proxmox VMs as nodes to an existing k3s cluster (e.g. the AWS cluster) via Tailscale

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- Proxmox VE >= 8.0 with API token access
- Packer-built VM templates (VM IDs 9000/9001 by default)
- (Optional) [Tailscale auth key](https://login.tailscale.com/admin/settings/keys) for hybrid cluster networking
- S3 backend configured (see `terraform/state-init/`)

### Proxmox API Token for Terraform

```bash
# On the Proxmox host
pveum useradd terraform@pam -comment "Terraform automation"
pveum user token add terraform@pam terraform-token --privsep=0
pveum aclmod / -user terraform@pam -role PVEVMAdmin
pveum aclmod /storage -user terraform@pam -role PVEDatastoreAdmin
```

## Usage

### 1. Create a variables file

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Proxmox details, IPs, SSH keys, etc.
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Plan and apply

```bash
terraform plan
terraform apply
```

### 4. Get cluster info

```bash
# Server IPs
terraform output server_ipv4_addresses

# k3s join token (for manually adding more nodes)
terraform output -raw k3s_token

# Cluster mode
terraform output cluster_mode
```

## Deployment Modes

### Standalone Cluster (new Proxmox-only cluster)

Leave `k3s_server_url` and `k3s_token` empty in your tfvars:

```hcl
k3s_server_url = ""
k3s_token      = ""
server_count   = 1
agent_count    = 2
```

This creates a self-contained k3s cluster with 1 server + 2 agents. The first server initializes with `--cluster-init`, and subsequent servers/agents join it automatically.

### Join Existing Cluster (hybrid with AWS)

Set `k3s_server_url` and `k3s_token` to your existing cluster's values:

```hcl
# Use the Tailscale IP of your existing k3s server
k3s_server_url     = "https://100.x.y.z:6443"
k3s_token          = "<token from /var/lib/rancher/k3s/server/token>"
tailscale_auth_key  = "tskey-auth-..."

# Only agents needed when joining an existing cluster
server_count = 0
agent_count  = 3
```

To get the join token from an existing server:
```bash
ssh your-k3s-server "sudo cat /var/lib/rancher/k3s/server/token"
```

## Network Architecture

```
                    ┌─────────────────────────────────┐
                    │         Tailscale Mesh           │
                    └──────┬──────────────┬────────────┘
                           │              │
              ┌────────────┴──┐    ┌──────┴──────────────┐
              │  AWS (us-west) │    │  Proxmox (on-prem)  │
              │               │    │                      │
              │  k3s-server-1 │◄──►│  k3s-agent-1         │
              │  k3s-server-2 │    │  k3s-agent-2         │
              │               │    │  k3s-agent-3         │
              └───────────────┘    └──────────────────────┘
```

- Tailscale provides encrypted mesh networking between AWS and Proxmox nodes
- k3s uses Tailscale IPs for inter-node communication
- Proxmox VMs get Tailscale installed automatically via cloud-init

## Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `proxmox_api_url` | — | Proxmox API endpoint |
| `proxmox_node` | `pve` | Target Proxmox node |
| `server_count` | `1` | Number of server nodes |
| `agent_count` | `2` | Number of agent nodes |
| `server_cores` / `agent_cores` | `2` / `2` | CPU cores |
| `server_memory` / `agent_memory` | `4096` / `2048` | Memory (MB) |
| `disk_size` | `20` | Disk size (GB) |
| `server_ips` / `agent_ips` | `[]` | Static IPs in CIDR (empty = DHCP) |
| `k3s_server_url` | `""` | Existing server URL (empty = standalone) |
| `k3s_token` | `""` | Cluster token (empty = auto-generate) |
| `tailscale_auth_key` | `""` | Tailscale auth key for auto-registration |
| `node_label` | `proxmox` | Value for `instance=` node label |

See `variables.tf` for the full list with descriptions.

## Outputs

| Output | Description |
|--------|-------------|
| `server_names` | VM names of server nodes |
| `server_ipv4_addresses` | IP addresses of server nodes |
| `agent_names` | VM names of agent nodes |
| `agent_ipv4_addresses` | IP addresses of agent nodes |
| `k3s_server_url` | API server URL for joining additional nodes |
| `k3s_token` | Cluster join token (sensitive) |
| `cluster_mode` | `standalone` or `joined (<url>)` |
