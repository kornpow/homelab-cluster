# Terraform — k3s Proxmox Cluster

Provisions k3s server and agent VMs on Proxmox by cloning templates built with Packer (see `packer/k3s-proxmox/`).

Supports two modes:
- **Standalone cluster** — creates a new k3s cluster entirely on Proxmox
- **Join existing cluster** — adds Proxmox VMs as nodes to an existing k3s cluster (e.g. the AWS cluster) via Tailscale

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.5 (or Terraform >= 1.5)
- Proxmox VE >= 8.0 with API token access
- Packer-built VM templates (VM IDs 9000/9001 by default)
- 1Password desktop app with "Integrate with other apps" enabled (Settings > Developer)
- (Optional) [Tailscale auth key](https://login.tailscale.com/admin/settings/keys) for hybrid cluster networking
- S3 backend configured (see `terraform/state-init/`)

### Proxmox Host Setup

See [`docs/proxmox-setup.md`](../../docs/proxmox-setup.md) for the full repeatable guide covering:
- Proxmox VE installation
- Post-install configuration
- Multi-host clustering
- API token creation
- Storage and network setup

### Secrets via 1Password

API tokens are fetched from 1Password at plan/apply time using the [1Password Terraform provider](https://github.com/1Password/terraform-provider-onepassword). No secrets in tfvars files.

**Setup:**

1. Store your Proxmox API token in 1Password (see [docs/proxmox-setup.md § Store Tokens](../../docs/proxmox-setup.md#7-store-tokens-in-1password)):
   - Item title: e.g. `Proxmox - spore-nuc`
   - Fields: `API Token ID` and `API Token Secret`
   - Vault: `lightning-spore`

2. Enable app integration in 1Password:
   - 1Password > Settings > Developer > "Integrate with other apps"

3. Set your account (choose one):
   ```bash
   export OP_ACCOUNT="my.1password.com"   # env var
   # or in terraform.tfvars:
   # op_account = "my.1password.com"
   ```

When you run `tofu plan` or `tofu apply`, 1Password will prompt for biometric auth (Touch ID) to release the secrets.

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
