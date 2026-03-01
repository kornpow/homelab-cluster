#!/bin/bash
# k3s-install.sh — Installs k3s and supporting tools on a Debian Proxmox VM.
# Called by Packer during template build. Accepts one argument: "server" or "agent".
set -euo pipefail

K3S_ROLE="${1:-server}"

echo "==> Updating system packages"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y \
  curl \
  wget \
  gnupg \
  ca-certificates \
  wireguard-tools \
  open-iscsi \
  nfs-common \
  jq \
  unzip

# ── Install k3s ──────────────────────────────
echo "==> Installing k3s (role: ${K3S_ROLE})"
if [ "${K3S_ROLE}" = "server" ]; then
  curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE='644' INSTALL_K3S_EXEC='server' sh -s -
else
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='agent' sh -s -
fi

# Stop k3s — it will be configured and started properly on first boot
sudo systemctl stop k3s* || true
sudo systemctl disable k3s* || true

# ── Install k9s (amd64) ─────────────────────
echo "==> Installing k9s"
K9S_VERSION="v0.32.7"
wget -q "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" -O /tmp/k9s.tar.gz
tar xzf /tmp/k9s.tar.gz -C /tmp
sudo mv /tmp/k9s /usr/local/bin/k9s
rm -f /tmp/k9s.tar.gz

# ── Install Tailscale ────────────────────────
echo "==> Installing Tailscale"
curl -fsSL https://tailscale.com/install.sh | sh

# ── Install Helm ─────────────────────────────
echo "==> Installing Helm"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ── Set up kubeconfig convenience (server only) ──
if [ "${K3S_ROLE}" = "server" ]; then
  echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/debian/.bashrc
fi

# ── Prepare config directory ─────────────────
sudo mkdir -p /etc/rancher/k3s

# ── Clean up ─────────────────────────────────
echo "==> Cleaning up"
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo cloud-init clean || true

echo "==> k3s ${K3S_ROLE} template build complete"
