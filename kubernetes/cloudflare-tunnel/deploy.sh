#!/bin/bash
# Deploy Cloudflare Tunnel to k3s cluster

set -e

echo "=== Cloudflare Tunnel Deployment ==="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "Error: helm not found"
    exit 1
fi

# Check if values file is provided
VALUES_FILE="${1:-values-production.yaml}"

if [ ! -f "$VALUES_FILE" ]; then
    echo "Error: Values file not found: $VALUES_FILE"
    echo "Usage: $0 [values-file.yaml]"
    echo ""
    echo "Available values files:"
    ls -1 *.yaml 2>/dev/null || echo "  (none found)"
    exit 1
fi

echo "Using values file: $VALUES_FILE"
echo ""

# Deploy secrets sync CronJob first
echo "1. Deploying AWS Secrets Sync CronJob..."
kubectl apply -f ../manifests/aws-secrets-sync.yaml
echo "   Done!"
echo ""

# Create namespace
echo "2. Creating cloudflare-tunnel namespace..."
kubectl create namespace cloudflare-tunnel --dry-run=client -o yaml | kubectl apply -f -
echo "   Done!"
echo ""

# Run the sync job once to get the secret immediately
echo "3. Running initial secret sync (this may take a moment)..."
kubectl create job --from=cronjob/aws-secrets-sync-cron manual-sync-$(date +%s) -n default 2>/dev/null || true
echo "   CronJob will sync secrets every 5 minutes"
echo ""

echo "4. Waiting a few seconds for secret sync..."
sleep 5

# Check if secret exists
if kubectl get secret cloudflare-tunnel-token -n cloudflare-tunnel &> /dev/null; then
    echo "   Secret found!"
else
    echo "   WARNING: Secret not found yet. The CronJob will create it within 5 minutes."
    echo "   You can check with: kubectl get secret -n cloudflare-tunnel"
fi
echo ""

# Deploy Cloudflare Tunnel
echo "5. Deploying Cloudflare Tunnel..."
helm upgrade --install cloudflare-tunnel . \
  --namespace cloudflare-tunnel \
  -f "$VALUES_FILE" \
  --wait \
  --timeout 2m
echo "   Done!"
echo ""

echo "=== Deployment Complete ==="
echo ""
echo "Check status with:"
echo "  kubectl get pods -n cloudflare-tunnel"
echo "  kubectl logs -n cloudflare-tunnel -l app.kubernetes.io/name=cloudflare-tunnel"
echo ""
echo "View tunnel in Cloudflare Dashboard:"
echo "  https://one.dash.cloudflare.com/ > Access > Tunnels"
