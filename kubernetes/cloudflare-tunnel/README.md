# Cloudflare Tunnel for k3s

This Helm chart deploys Cloudflare Tunnel (cloudflared) to expose services in your k3s cluster through Cloudflare's network.

## Overview

Cloudflare Tunnel creates an outbound-only connection to Cloudflare's edge, allowing you to:
- Expose services without opening firewall ports
- Get DDoS protection and CDN benefits automatically
- Use Cloudflare Access for authentication
- Get automatic SSL/TLS certificates

## Prerequisites

1. A Cloudflare account with a domain
2. Access to Cloudflare Zero Trust dashboard

## Setup Instructions

### 1. Create a Cloudflare Tunnel

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Access** > **Tunnels**
3. Click **Create a tunnel**
4. Name your tunnel (e.g., `k3s-cluster`)
5. Select **Docker** as the connector
6. Copy the tunnel token (it looks like `eyJhIjoi...`)
7. Save the tunnel - don't configure ingress rules yet

### 2. Configure DNS

After creating the tunnel, add DNS records for each service you want to expose:
- Go to your domain's DNS settings in Cloudflare
- Create CNAME records pointing to your tunnel
- Example: `wordpress.yourdomain.com` CNAME to `<tunnel-id>.cfargotunnel.com`

### 3. Deploy the Helm Chart

Create a `values-custom.yaml` file:

```yaml
cloudflare:
  accountId: "your-account-id"
  tunnelToken: "your-tunnel-token-here"
  tunnelId: "your-tunnel-id"

tunnel:
  ingress:
    # WordPress example
    - hostname: "wordpress.yourdomain.com"
      service: "http://wordpress.wordpress.svc.cluster.local:80"
    
    # LNBits example  
    - hostname: "lnbits.yourdomain.com"
      service: "http://lnbits.lnbits.svc.cluster.local:3000"
    
    # Resume site example
    - hostname: "resume.yourdomain.com"
      service: "http://resume.resume.svc.cluster.local:80"
    
    # Catch-all (required)
    - service: "http_status:404"

# Increase replicas for high availability
replicaCount: 2
```

Deploy:

```bash
# Add namespace if needed
kubectl create namespace cloudflare-tunnel --dry-run=client -o yaml | kubectl apply -f -

# Deploy the chart
helm upgrade --install cloudflare-tunnel ./cloudflare-tunnel \
  --namespace cloudflare-tunnel \
  -f values-custom.yaml
```

### 4. Verify Deployment

```bash
# Check pod status
kubectl get pods -n cloudflare-tunnel

# Check logs
kubectl logs -n cloudflare-tunnel -l app.kubernetes.io/name=cloudflare-tunnel

# Check tunnel status in Cloudflare dashboard
# Go to Zero Trust > Access > Tunnels > Your tunnel
```

## Finding Internal Service URLs

To find the correct service URLs for your cluster services:

```bash
# List all services
kubectl get services --all-namespaces

# For a specific namespace
kubectl get services -n wordpress

# Service URL format: http://<service-name>.<namespace>.svc.cluster.local:<port>
```

## Security Considerations

- **Token Security**: Store the tunnel token in a secure secret management system (e.g., AWS Secrets Manager, Vault)
- **Access Control**: Enable Cloudflare Access policies for sensitive services
- **Network Policies**: Consider using Kubernetes Network Policies to restrict cloudflared pod access

## Troubleshooting

### Tunnel shows as "DOWN" in dashboard

```bash
# Check pod logs
kubectl logs -n cloudflare-tunnel deployment/cloudflare-tunnel

# Verify token is correct
echo "your-token" | base64 -d  # Should show valid JSON
```

### Services return 502 errors

1. Verify the internal service URL is correct
2. Check if the target service is running: `kubectl get pods -n <namespace>`
3. Test connectivity from the cloudflared pod: `kubectl exec -it -n cloudflare-tunnel deployment/cloudflare-tunnel -- curl -v <service-url>`

### High latency

Cloudflare Tunnel is outbound-only, so latency depends on:
- Your server's connection to Cloudflare's edge
- Geographic distance to Cloudflare's nearest data center
- Consider enabling Argo Smart Routing in Cloudflare

## Migration from Existing Ingress

If you're currently using Traefik with public IPs:

1. Set up Cloudflare Tunnel alongside existing ingress
2. Test services through Cloudflare
3. Update DNS to point to Cloudflare Tunnel
4. Once verified, you can remove public IPs or keep both for redundancy

## Additional Resources

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [cloudflared GitHub](https://github.com/cloudflare/cloudflared)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
