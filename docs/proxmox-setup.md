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

---

## 1. Install Proxmox VE

### Download

Get the latest Proxmox VE ISO from [proxmox.com/downloads](https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso). As of this writing, the latest is **PVE 8.x** (Debian 12 Bookworm based).

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

# Add the no-subscription repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list

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
{"data":{"version":"8.x.x","release":"x.x",...}}
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

Packer needs a Debian 12 netinst ISO on the Proxmox host's `local` storage.

### Download Debian 12 ISO

On each Proxmox host (or just the one you'll build templates on):

```bash
cd /var/lib/vz/template/iso/

# Debian 12 (latest point release)
wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.9.0-amd64-netinst.iso
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
ssh root@10.0.0.219 'ls /var/lib/vz/template/iso/debian-12*'

# 7. Cluster status (if clustered)
ssh root@10.0.0.219 'pvecm status'
```

## Next Steps

- Build VM templates with Packer: [`packer/k3s-proxmox/README.md`](../packer/k3s-proxmox/README.md)
- Provision k3s VMs with Terraform: [`terraform/k3s-proxmox/README.md`](../terraform/k3s-proxmox/README.md)
