# Proxmox VE Setup Guide

Repeatable guide for setting up Proxmox VE hosts from bare metal through automation-ready state. Covers the two-host environment used in this project:

| Host | Hostname | IP | Hardware |
|------|----------|-----|----------|
| spore-nuc | `pve` | 10.0.0.219 | Intel NUC |
| beelink1 | `pve-beelink1` | 10.0.0.120 | Beelink Mini PC |

## Table of Contents

1. [Install Proxmox VE](#1-install-proxmox-ve)
2. [Post-Install Configuration](#2-post-install-configuration)
3. [Storage Configuration](#3-storage-configuration)
4. [Network Configuration](#4-network-configuration)
5. [Create a Proxmox Cluster](#5-create-a-proxmox-cluster)
6. [API Tokens for Automation](#6-api-tokens-for-automation)
7. [Store Tokens in 1Password](#7-store-tokens-in-1password)
8. [Upload ISO Images](#8-upload-iso-images)
9. [Verify Setup](#9-verify-setup)
10. [Appendix: Adding Proxmox VMs to an Existing k3s Cluster](#appendix-adding-proxmox-vms-to-an-existing-k3s-cluster)

---

## 1. Install Proxmox VE

### Download

Get the latest Proxmox VE ISO from [proxmox.com/downloads](https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso). As of this writing, the latest is **PVE 9.x** (Debian 13 Trixie based).

### Create bootable USB

```bash
# macOS
diskutil list                              # identify the USB drive (e.g. /dev/disk4)
diskutil unmountDisk /dev/disk4
sudo dd if=proxmox-ve_*.iso of=/dev/rdisk4 bs=4M status=progress
diskutil eject /dev/disk4

# Linux
sudo dd if=proxmox-ve_*.iso of=/dev/sdX bs=4M status=progress conv=fdatasync
```

### Install

1. Boot from USB
2. Accept the EULA
3. Select the target disk (use the entire disk — Proxmox uses ZFS or ext4/LVM)
4. Set country, timezone, keyboard layout
5. Set the **root password** and admin email
6. Configure networking:
   - **Management interface:** Select the primary NIC
   - **Hostname (FQDN):** e.g. `pve.local` or `pve-beelink1.local`
   - **IP address:** Set a static IP on your LAN (e.g. `10.0.0.219/24` for spore-nuc, `10.0.0.120/24` for beelink1)
   - **Gateway:** Your router (e.g. `10.0.0.1`)
   - **DNS:** `1.1.1.1` or your local DNS
7. Review and install

Repeat on each host.

## 2. Post-Install Configuration

After install, access the web UI at `https://<ip>:8006` and log in as `root`.

### Remove enterprise repo (no subscription)

SSH into each host and run:

```bash
# Disable the enterprise repo (requires paid subscription)
sed -i 's/^deb/# deb/' /etc/apt/sources.list.d/pve-enterprise.list

# Add the no-subscription repo (use 'trixie' for PVE 9.x, 'bookworm' for PVE 8.x)
echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list

# Update and upgrade
apt update && apt full-upgrade -y
```

### Remove subscription nag (optional)

```bash
# This edits the web UI JavaScript to remove the "No valid subscription" popup
sed -Ezi.bak "s/(Ext\.Msg\.show\(\{[^}]+?title: gettext\('No valid sub)/void\(\{ \/\/ \1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy
```

### Install useful packages

```bash
apt install -y vim htop iotop tmux curl wget gnupg2
```

### Enable SSH key auth

From your workstation:

```bash
# Copy your SSH key to each Proxmox host
ssh-copy-id root@10.0.0.219   # spore-nuc
ssh-copy-id root@10.0.0.120   # beelink1
```

## 3. Storage Configuration

Proxmox ships with two default storage entries:

| Storage | Type | Path | Used for |
|---------|------|------|----------|
| `local` | Directory | `/var/lib/vz` | ISOs, container templates, snippets |
| `local-lvm` | LVM-thin | `pve/data` | VM disks, container volumes |

### Verify storage

```bash
pvesm status
```

### Enable snippets on local storage

Snippets are needed for cloud-init user-data files (used by the Terraform module):

```bash
pvesm set local --content iso,vztmpl,snippets
```

Verify:
```bash
pvesm status
# Should show "snippets" in the content column for "local"
```

### Add shared/additional storage (optional)

If you want NFS or CIFS shared storage between hosts:

```bash
# NFS example
pvesm add nfs shared-nfs \
  --server 10.0.0.10 \
  --export /mnt/data/proxmox \
  --content images,iso,vztmpl,snippets \
  --options vers=4.2
```

## 4. Network Configuration

Default Proxmox install creates:

- `vmbr0` — Linux bridge on the management NIC (VMs connect here by default)

### Verify network

```bash
# Show bridges
ip link show type bridge

# Show bridge members
bridge link

# Show Proxmox network config
cat /etc/network/interfaces
```

The default `vmbr0` bridged to the primary NIC is sufficient for most setups. VMs on `vmbr0` will get IPs on the same LAN as the host.

### VLAN support (optional)

If you want VLAN-tagged VM traffic:

```bash
# In /etc/network/interfaces, make vmbr0 VLAN-aware:
auto vmbr0
iface vmbr0 inet static
    address 10.0.0.219/24
    gateway 10.0.0.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
```

Then in VM configs, set the VLAN tag on the network device.

## 5. Create a Proxmox Cluster

**Cluster Status (as of 2026-03-01):** ✅ Complete
- **Cluster Name:** `lightningspore`
- **Nodes:** `pve` (spore-nuc, 10.0.0.219), `pve-beelink1` (beelink1, 10.0.0.120)
- **Quorum:** 2 nodes, 2 votes, `two_node: 1` enabled
- **Notes:** Cluster filesystem (`pmxcfs`) syncing may require manual intervention for `/etc/pve`

A Proxmox cluster lets you manage multiple hosts from one UI, live-migrate VMs, and use shared storage. **All hosts must be able to reach each other on their management IPs.**

> **Important:** Clustering is optional for this project. The Terraform module targets individual nodes by name, so you can run without clustering. Clustering is useful if you want a single web UI and live migration.

### Create the cluster (on the first host)

SSH into `spore-nuc` (10.0.0.219):

```bash
pvecm create homelab-cluster
```

### Join additional hosts

SSH into `pve-beelink1` (10.0.0.120):

```bash
pvecm add 10.0.0.219
# Enter the root password of spore-nuc when prompted
```

### Verify cluster status

```bash
pvecm status
# Expected: 2 nodes, quorate

pvecm nodes
# Should list both nodes
```

### Cluster notes

- All nodes share the same authentication realm after clustering — users/tokens created on one are available on all
- If you cluster the hosts, you only need to create API tokens on one host
- Cluster communication uses Corosync on a dedicated link (defaults to management network)
- For a 2-node cluster, set `pvecm expected 1` to maintain quorum if one node goes down (or use a QDevice)

### 2-node quorum workaround

With only 2 nodes, losing one loses quorum. Options:

```bash
# Option A: Allow operations with 1 node (less safe)
pvecm expected 1   # run this on the surviving node if one goes down

# Option B: Add a QDevice (recommended for production)
# Requires a 3rd lightweight Linux host running corosync-qnetd
apt install corosync-qdevice
pvecm qdevice setup <qdevice-ip>
```

## 6. API Tokens for Automation

Both Packer (template builds) and Terraform (VM provisioning) need API access to Proxmox.

### Create the API token

Run this on a Proxmox host (if clustered, only need to run on one):

```bash
pveum user token add root@pam terraform-token --privsep=0
```

`--privsep=0` means the token inherits root's full permissions. No extra user or ACL grants needed.

### If NOT clustered — repeat on each host

If the hosts are standalone (not in a Proxmox cluster), you must create the token on **each host separately**. Each host will have its own token secret.

### Minimum-privilege alternative

If you prefer not to use root, create a dedicated user with scoped permissions:

```bash
# Create Linux user first (required for PAM realm)
useradd -m -s /bin/bash -c "Terraform automation" terraform

# Create Proxmox user
pveum useradd terraform@pam -comment "Terraform and Packer automation"

# Set password (PAM users need a Linux password)
passwd terraform

# Create a custom role with minimum required privileges
pveum role add TerraformPacker -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt Datastore.AllocateSpace Datastore.Allocate Datastore.AllocateTemplate Datastore.Audit SDN.Use Sys.Modify Sys.Audit"

# Assign the custom role
pveum aclmod / -user terraform@pam -role TerraformPacker
pveum aclmod /storage -user terraform@pam -role PVEDatastoreAdmin

# Create token
pveum user token add terraform@pam terraform-token --privsep=0
```

### Verify token works

From your workstation:

```bash
# Test against spore-nuc
curl -sk "https://10.0.0.219:8006/api2/json/version" \
  -H "Authorization: PVEAPIToken=root@pam!terraform-token=<SECRET>"

# Test against beelink1
curl -sk "https://10.0.0.120:8006/api2/json/version" \
  -H "Authorization: PVEAPIToken=root@pam!terraform-token=<SECRET>"
```

Expected response:
```json
{"data":{"version":"9.x.x","release":"x.x",...}}
```

### Test broader permissions

```bash
# Should return node list
curl -sk "https://10.0.0.219:8006/api2/json/nodes" \
  -H "Authorization: PVEAPIToken=root@pam!terraform-token=<SECRET>"

# Should return storage info
curl -sk "https://10.0.0.219:8006/api2/json/storage" \
  -H "Authorization: PVEAPIToken=root@pam!terraform-token=<SECRET>"
```

## 7. Store Tokens in 1Password

Store the Proxmox API tokens in 1Password so they can be fetched by the Terraform 1Password provider at plan/apply time.

### Store each host's token

Using the 1Password CLI (`op`):

```bash
# For spore-nuc (10.0.0.219)
op item edit "Proxmox - spore-nuc" \
  --vault "lightning-spore" \
  "API Token ID=root@pam!terraform-token" \
  "API Token Secret=<SECRET-FROM-STEP-6>"

# For beelink1 (10.0.0.120)
op item edit "Proxmox - Beelink1" \
  --vault "lightning-spore" \
  "API Token ID=root@pam!terraform-token" \
  "API Token Secret=<SECRET-FROM-STEP-6>"
```

Or create new items if they don't have the right fields:

```bash
op item create \
  --category login \
  --vault "lightning-spore" \
  --title "Proxmox - spore-nuc" \
  --url "https://10.0.0.219:8006/" \
  "username=root" \
  "API Token ID=root@pam!terraform-token" \
  "API Token Secret=<SECRET>"
```

### Verify retrieval

```bash
op item get "Proxmox - spore-nuc" --vault "lightning-spore" --field "API Token Secret"
```

The Terraform module uses the `1password/onepassword` provider to fetch these at plan/apply time. See [`terraform/k3s-proxmox/README.md`](../terraform/k3s-proxmox/README.md).

## 8. Upload ISO Images

Packer needs a Debian 13 (Trixie) netinst ISO on the Proxmox host's `local` storage.

### Download Debian 13 ISO

On each Proxmox host (or just the one you'll build templates on):

```bash
cd /var/lib/vz/template/iso/

# Debian 13 (Trixie — latest point release)
wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.2.0-amd64-netinst.iso
```

### Verify

```bash
ls -lh /var/lib/vz/template/iso/
# Should show the Debian ISO
```

Or in the Proxmox web UI: Datacenter > Storage > local > ISO Images.

## 9. Verify Setup

Run through this checklist on each host before running Packer/Terraform:

```bash
# 1. Host is reachable
ping -c 1 10.0.0.219   # spore-nuc
ping -c 1 10.0.0.120   # beelink1

# 2. Web UI accessible
curl -sk https://10.0.0.219:8006 | head -1   # should return HTML
curl -sk https://10.0.0.120:8006 | head -1

# 3. SSH works
ssh root@10.0.0.219 'hostname'   # pve
ssh root@10.0.0.120 'hostname'   # pve-beelink1

# 4. API token works
curl -sk "https://10.0.0.219:8006/api2/json/nodes" \
  -H "Authorization: PVEAPIToken=root@pam!terraform-token=<SECRET>"

# 5. Storage has snippets enabled
ssh root@10.0.0.219 'pvesm status'
# "local" should include "snippets" in content

# 6. Debian ISO is present
ssh root@10.0.0.219 'ls /var/lib/vz/template/iso/debian-13*'

# 7. Cluster status (if clustered)
ssh root@10.0.0.219 'pvecm status'
```

## Next Steps

- Build VM templates with Packer: [`packer/k3s-proxmox/README.md`](../packer/k3s-proxmox/README.md)
- Provision k3s VMs with Terraform: [`terraform/k3s-proxmox/README.md`](../terraform/k3s-proxmox/README.md)

---

## Appendix: Adding Proxmox VMs to an Existing k3s Cluster

This section covers how to join Proxmox-provisioned VMs into an existing k3s cluster (e.g. one running on AWS EC2 or bare-metal hosts). The Terraform module handles this automatically via cloud-init, but understanding the mechanics is useful for debugging and manual operations.

### How k3s Clustering Works

k3s uses a **server/agent** architecture:

- **Server nodes** run the control plane (API server, scheduler, controller manager, etcd). Multiple servers form an HA cluster.
- **Agent nodes** run workloads only. They connect to a server's API on port 6443 to register and receive pod assignments.

All nodes authenticate to the cluster using a shared **token** (a pre-shared secret). New nodes join by pointing at a server URL + providing the token.

### What You Need to Join

To add nodes to an existing cluster, you need three things:

1. **k3s server URL** — the `https://<ip>:6443` address of an existing server node
2. **k3s join token** — the cluster's shared secret
3. **Network reachability** — the new node must be able to reach the server on port 6443

#### Getting the join token

SSH into any existing k3s **server** node and run:

```bash
sudo cat /var/lib/rancher/k3s/server/token
```

This returns a long string like `K10...::server:abc123...`. The entire string is the token.

#### Getting the server URL

If your cluster uses Tailscale, use the server's **Tailscale IP** (100.x.y.z) so that Proxmox agents can reach the server even across network boundaries:

```bash
# On the server node
tailscale ip -4
# e.g. 100.64.1.5

# The server URL is:
# https://100.64.1.5:6443
```

If all nodes are on the same LAN, use the server's LAN IP instead.

### Joining via Terraform (Recommended)

The Terraform module at `terraform/k3s-proxmox/` handles joining automatically. Set these variables in `terraform.tfvars`:

```hcl
# Point at your existing cluster
k3s_server_url     = "https://100.64.1.5:6443"   # Tailscale IP of an existing server
k3s_token          = "K10...::server:abc123..."   # from /var/lib/rancher/k3s/server/token

# Tailscale key so the new VMs join your tailnet
tailscale_auth_key  = "tskey-auth-..."

# Only agents — servers already exist
server_count = 0
agent_count  = 3
```

Then run:

```bash
cd terraform/k3s-proxmox
tofu init
tofu apply
```

Cloud-init on each new VM will:
1. Register with Tailscale (so it can reach the server via Tailscale IP)
2. Run `curl -sfL https://get.k3s.io | K3S_URL=... K3S_TOKEN=... sh -s -` to install k3s in agent mode and join the cluster

### Joining Manually (Without Terraform)

If you need to join a node manually (e.g. an existing bare-metal machine):

```bash
# 1. Install Tailscale and join your tailnet
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=tskey-auth-... --accept-routes --accept-dns=false

# 2. Install k3s as an agent
curl -sfL https://get.k3s.io | \
  K3S_URL="https://100.64.1.5:6443" \
  K3S_TOKEN="K10...::server:abc123..." \
  INSTALL_K3S_EXEC="agent --node-label=instance=proxmox --node-label=location=proxmox" \
  sh -s -

# 3. Verify on the server
kubectl get nodes
```

### Adding a Server Node (HA)

To add a new **server** (not agent) to an existing HA cluster:

```bash
curl -sfL https://get.k3s.io | \
  K3S_TOKEN="K10...::server:abc123..." \
  K3S_KUBECONFIG_MODE="644" \
  INSTALL_K3S_EXEC="server --server=https://100.64.1.5:6443 --node-label=instance=proxmox" \
  sh -s -
```

Note the difference: agents use `K3S_URL`, servers use `--server=` in `INSTALL_K3S_EXEC`.

### Verifying Cluster Membership

From any server node:

```bash
# List all nodes
kubectl get nodes -o wide

# Check a specific node's status
kubectl describe node k3s-agent-1

# Verify the node is Ready and has the correct labels
kubectl get nodes --show-labels | grep proxmox
```

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Agent can't reach server on :6443 | Network/firewall issue | Check Tailscale is connected: `tailscale status` |
| Node shows `NotReady` | k3s service not running | `sudo systemctl status k3s-agent` / check logs: `sudo journalctl -u k3s-agent -f` |
| "token mismatch" error | Wrong join token | Re-read token from server: `sudo cat /var/lib/rancher/k3s/server/token` |
| Node registered but no pods scheduled | Taints or resource constraints | Check taints: `kubectl describe node <name>` |
| Tailscale not connecting | Auth key expired or wrong | Generate a new key from [Tailscale admin](https://login.tailscale.com/admin/settings/keys) |

### Architecture: Hybrid Cluster with Tailscale

```
  AWS EC2 (us-west-2)                 Proxmox (on-prem)
  ┌──────────────────┐               ┌──────────────────────┐
  │ k3s-server-1     │◄──Tailscale──►│ k3s-agent-1 (VM)     │
  │ k3s-server-2     │   mesh VPN    │ k3s-agent-2 (VM)     │
  │                  │               │ k3s-agent-3 (VM)     │
  └──────────────────┘               └──────────────────────┘
         ▲                                    ▲
         │              Tailscale             │
         ▼                                    ▼
  ┌──────────────────────────────────────────────┐
  │  On-Prem Bare Metal                          │
  │  beelink1, beelink2, laptop, ai-box          │
  └──────────────────────────────────────────────┘
```

All inter-node traffic (kubelet ↔ API server, flannel VXLAN, etc.) flows over Tailscale's encrypted WireGuard tunnels. Nodes don't need to be on the same LAN or have public IPs — Tailscale handles NAT traversal.

---

## 11. USB Device Passthrough

**Status (as of 2026-03-01):** Brother QL-800 label printer connected to `pve-beelink1`

### Overview

Proxmox allows passing physical USB devices through to VMs. This is useful for:
- USB printers (label printers, receipt printers)
- USB storage devices
- USB radio/SDR devices
- Hardware security keys (for VM-internal use)

### Find USB Devices

```bash
# List all USB devices on a Proxmox host
lsusb

# Example output:
# Bus 001 Device 003: ID 04f9:209b Brother Industries, Ltd QL-800 Label Printer
```

### Add USB Device to VM

**Method 1: USB Passthrough by ID (recommended)**

```bash
# Add Brother printer (04f9:209b) to VM 200
qm set 200 -usb3 host=04f9:209b

# The device will appear in the VM as /dev/usb/lp0
```

**Method 2: USB Passthrough by Port**

```bash
# Add device from physical USB port (e.g., port 2 on bus 3)
qm set 200 -usb3 host=3-2
```

### Verify in VM

```bash
# Inside the VM
ls -la /dev/usb/lp*
# Should show: /dev/usb/lp0

# Check printer status
lpinfo -v
```

### Remove USB Device from VM

```bash
qm set 200 -delete usb3
```

### Cluster Considerations

**Important:** USB passthrough only works if the VM is running on the same node as the USB device. In a cluster:

1. **Option A: Move the printer** — Physically plug the USB device into the node where the VM runs
2. **Option B: Migrate the VM** — Use live migration to move the VM to the node with the USB device
   ```bash
   qm migrate <vmid> <target-node> --online
   ```
3. **Option C: USB/IP** — Share the USB device over the network (complex, not covered here)

### Current Setup

- **Printer:** Brother QL-800 Label Printer (USB ID: `04f9:209b`)
- **Connected to:** `pve-beelink1` (10.0.0.120)
- **k3s VM:** VM 200 on `pve` (10.0.0.219)
- **Next Step:** Either migrate VM 200 to `pve-beelink1` or move printer to `pve`

---

## 11. USB Device Passthrough

**Status (as of 2026-03-01):** Brother QL-800 label printer connected to `pve-beelink1`

### Overview

Proxmox allows passing physical USB devices through to VMs. This is useful for:
- USB printers (label printers, receipt printers)
- USB storage devices
- USB radio/SDR devices
- Hardware security keys (for VM-internal use)

### Find USB Devices

```bash
# List all USB devices on a Proxmox host
lsusb

# Example output:
# Bus 001 Device 003: ID 04f9:209b Brother Industries, Ltd QL-800 Label Printer
```

### Add USB Device to VM

**Method 1: USB Passthrough by ID (recommended)**

```bash
# Add Brother printer (04f9:209b) to VM 200
qm set 200 -usb3 host=04f9:209b

# The device will appear in the VM as /dev/usb/lp0
```

**Method 2: USB Passthrough by Port**

```bash
# Add device from physical USB port (e.g., port 2 on bus 3)
qm set 200 -usb3 host=3-2
```

### Verify in VM

```bash
# Inside the VM
ls -la /dev/usb/lp*
# Should show: /dev/usb/lp0

# Check printer status
lpinfo -v
```

### Remove USB Device from VM

```bash
qm set 200 -delete usb3
```

### Cluster Considerations

**Important:** USB passthrough only works if the VM is running on the same node as the USB device. In a cluster:

1. **Option A: Move the printer** — Physically plug the USB device into the node where the VM runs
2. **Option B: Migrate the VM** — Use live migration to move the VM to the node with the USB device
   ```bash
   qm migrate <vmid> <target-node> --online
   ```
3. **Option C: USB/IP** — Share the USB device over the network (complex, not covered here)

### Current Setup

- **Printer:** Brother QL-800 Label Printer (USB ID: `04f9:209b`)
- **Connected to:** `pve-beelink1` (10.0.0.120)
- **k3s VM:** VM 200 on `pve` (10.0.0.219)
- **Next Step:** Either migrate VM 200 to `pve-beelink1` or move printer to `pve`
