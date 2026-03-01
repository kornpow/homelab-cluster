# k3s Hybrid Cluster Infrastructure

Infrastructure-as-code for a hybrid k3s Kubernetes cluster spanning AWS EC2, Proxmox VMs, and on-premises hardware. Manages cluster provisioning (Packer + Terraform), application deployments (Helm), and supporting infrastructure (DNS, TLS, secrets, container registry).

## Architecture

```
                        ┌──────────────────────────────────────────────┐
                        │              Tailscale Mesh VPN              │
                        └──┬──────────────┬───────────────┬────────────┘
                           │              │               │
              ┌────────────┴──┐    ┌──────┴────────┐   ┌──┴──────────────┐
              │  AWS us-west-2 │    │  Proxmox VMs  │   │  On-Prem Hosts  │
              │               │    │               │   │                 │
              │  server-1     │    │  agent-1      │   │  beelink1       │
              │  server-2     │    │  agent-2      │   │  beelink2       │
              │               │    │  agent-3      │   │  laptop         │
              └───────┬───────┘    └───────┬───────┘   │  ai-box         │
                      │                    │           └────────┬────────┘
                      └────────────┬───────┘                    │
                                   │                            │
                        ┌──────────┴────────────────────────────┘
                        │           k3s Cluster
                        │  ┌─────────────────────────────┐
                        │  │  Traefik Ingress             │
                        │  │  Cloudflare Tunnel           │
                        │  │  cert-manager (Let's Encrypt) │
                        │  │  ECR image sync              │
                        │  └─────────────────────────────┘
                        │  ┌─────────────────────────────┐
                        │  │  Applications                │
                        │  │  resume, lnbits, wordpress,  │
                        │  │  home-assistant, labelprinter,│
                        │  │  webhook, pixel-promo, etc.  │
                        │  └─────────────────────────────┘
                        └───────────────────────────────────
```

## Repository Structure

```
.
├── packer/
│   ├── k3s-cluster/        # AWS AMI templates (Ubuntu 22.04 ARM64)
│   └── k3s-proxmox/        # Proxmox VM templates (Debian 13 amd64)
├── terraform/
│   ├── state-init/          # S3 backend bootstrap
│   ├── security/            # AWS security groups, IAM roles, secrets
│   ├── k3s-node/            # AWS EC2 k3s server instances
│   └── k3s-proxmox/         # Proxmox k3s server + agent VMs
├── kubernetes/
│   ├── namespaces/          # Namespace definitions
│   ├── traefik/             # Ingress controller config
│   ├── cloudflare-tunnel/   # Cloudflare Tunnel (alt ingress)
│   ├── cert-manager/        # TLS certificate issuers
│   ├── letencrypt/          # Let's Encrypt issuer setup
│   ├── manifests/           # Cluster-level CronJobs (ECR login, secrets sync)
│   ├── helpers/             # Debug pod
│   ├── resume/              # Personal resume site (Helm)
│   ├── lnbits/              # Lightning Network payments (Helm)
│   ├── wordpress/           # WordPress sites (Helm, Bitnami)
│   ├── home-assistant/      # Home automation (Helm)
│   ├── labelprinter/        # Label printer app (Helm)
│   ├── webhook/             # LightningSpore webhook (Helm)
│   ├── pixel-promo/         # Pixel ad board (Helm)
│   ├── coracle/             # Nostr client (Helm)
│   └── bostr/               # Nostr bouncer (Helm)
├── docker/
│   ├── ecr-login/           # ECR + kubectl image (for CronJobs)
│   └── debugger/            # Debug container image
└── scripts/
    └── create-kubeconfig.sh # Fetch kubeconfig from server
```

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| [mise](https://mise.jdx.dev/) | Tool version manager (manages all tools below) | [mise.jdx.dev](https://mise.jdx.dev/getting-started.html) |
| OpenTofu >= 1.5 | Infrastructure provisioning | `mise install` (or [opentofu.org](https://opentofu.org/docs/intro/install/)) |
| Packer >= 1.10 | VM template building | `mise install` (or [hashicorp.com](https://developer.hashicorp.com/packer/install)) |
| 1Password CLI | Secret management | `mise install` (or [1password.com](https://developer.1password.com/docs/cli/get-started/)) |
| Helm >= 3 | Kubernetes package management | [helm.sh](https://helm.sh/docs/intro/install/) |
| kubectl | Kubernetes CLI | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| AWS CLI v2 | AWS resource management | [aws.amazon.com](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| docker buildx | Multi-arch container builds | [docker.com](https://docs.docker.com/build/install-buildx/) |

> **Note:** Run `mise install` in the repo root to install Packer, 1Password CLI, and uv (Python) at the pinned versions from `mise.toml`.

**Accounts / access required:**
- AWS account with credentials configured (`us-west-2`)
- Proxmox VE server with API token (for Proxmox nodes)
- Tailscale account (for hybrid cluster networking)
- Cloudflare account (for tunnel-based ingress)
- Domain names: `samkorn.me`, `samkorn.xyz`, `lightningspore.com`

## Deployment Order

### 1. Bootstrap Terraform State

```bash
cd terraform/state-init
tofu init && tofu apply
```

Creates the S3 bucket and DynamoDB table used by all other Terraform modules.

### 2. Build VM Templates

**AWS (existing):**
```bash
cd packer/k3s-cluster
packer build k3s-server.pkr.hcl   # -> AMI: k3s-node-<timestamp>
```

**Proxmox (new):**
```bash
cd packer/k3s-proxmox
cp terraform.tfvars.example k3s-proxmox.pkrvars.hcl  # edit with your Proxmox details
packer init .
packer build -var-file=k3s-proxmox.pkrvars.hcl k3s-server.pkr.hcl   # -> VM template 9000
packer build -var-file=k3s-proxmox.pkrvars.hcl k3s-agent.pkr.hcl    # -> VM template 9001
```

See [`packer/k3s-proxmox/README.md`](packer/k3s-proxmox/README.md) for full details.

### 3. Provision Infrastructure

**AWS security resources:**
```bash
cd terraform/security
tofu init && tofu apply
```

**AWS k3s servers:**
```bash
cd terraform/k3s-node
tofu init && tofu apply -var-file=terraform.tfvars
```

**Proxmox k3s nodes:**
```bash
cd terraform/k3s-proxmox
cp terraform.tfvars.example terraform.tfvars   # edit with your values
tofu init && tofu apply
```

See [`terraform/k3s-proxmox/README.md`](terraform/k3s-proxmox/README.md) for standalone vs. join-existing modes.

### 4. Get Kubeconfig

```bash
# From an AWS server
./scripts/create-kubeconfig.sh

# Or directly
scp <server-ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Edit the server URL to match your server's public/Tailscale IP
```

### 5. Deploy Cluster Infrastructure

```bash
# Namespaces
kubectl apply -f kubernetes/namespaces/

# cert-manager + Let's Encrypt issuers
kubernetes/letencrypt/enable.sh

# Traefik configuration
kubectl apply -f kubernetes/traefik/

# ECR image pull secret rotation
kubectl apply -f kubernetes/manifests/ecr-login.yaml

# Cloudflare Tunnel (see its README for full setup)
kubernetes/cloudflare-tunnel/deploy.sh
```

### 6. Deploy Applications

```bash
# Example: deploy the resume site
cd kubernetes/resume
helm upgrade --install resume .

# Example: deploy labelprinter
cd kubernetes/labelprinter
helm upgrade --install labelprinter .
```

See the `kubernetes/Makefile` for a full list of Helm install commands.

## Creating k3s Nodes on Proxmox

This is the most common operation for expanding the cluster. Full documentation:

- **Build VM templates:** [`packer/k3s-proxmox/README.md`](packer/k3s-proxmox/README.md)
- **Provision VMs:** [`terraform/k3s-proxmox/README.md`](terraform/k3s-proxmox/README.md)

**Quick start (join existing cluster):**

```bash
# 1. Build templates (one-time)
cd packer/k3s-proxmox
packer init .
packer build -var-file=k3s-proxmox.pkrvars.hcl k3s-server.pkr.hcl
packer build -var-file=k3s-proxmox.pkrvars.hcl k3s-agent.pkr.hcl

# 2. Provision VMs
cd ../../terraform/k3s-proxmox
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars:
#   k3s_server_url    = "https://<tailscale-ip-of-existing-server>:6443"
#   k3s_token         = "<from: sudo cat /var/lib/rancher/k3s/server/token>"
#   tailscale_auth_key = "tskey-auth-..."
#   server_count      = 0
#   agent_count       = 3

tofu init
tofu apply

# 3. Verify
kubectl get nodes
```

## Application Secrets

Secrets are created manually via `kubectl`. Replace paths below with your actual credential locations.

```bash
# nginx config
kubectl create configmap nginx-config --from-file=nginx.conf

# Resume content
kubectl delete configmap resume-markdown
kubectl create configmap resume-markdown --from-file=resume-app/RESUME.md
kubectl create configmap nginx-html --from-file=public/index.html

# LNbits
kubectl create secret generic lnbits-env --from-file=<path-to-lnbits>/.env
kubectl create secret generic lnd-creds \
    --from-file=<path-to-creds>/lnd/tls.cert \
    --from-file=<path-to-creds>/lnd/admin.macaroon

# PostgreSQL
kubectl create secret generic postgres-creds \
    --from-literal=password=<your-password> \
    --from-literal=postgres-password=<your-admin-password>

# App dotenv files
kubectl create secret generic pixel-promo-dotenv --from-file=<path-to-app>/.env
kubectl create secret generic webhook-dotenv --from-file=<path-to-app>/.env
```

## Resources

- [k3s.rocks](https://github.com/askblaker/k3s.rocks.git) — k3s reference architecture
- [k3s docs](https://docs.k3s.io/) — Official k3s documentation
- [bpg/proxmox Terraform provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) — Proxmox Terraform provider docs
- [Packer Proxmox builder](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox) — Packer Proxmox plugin docs
