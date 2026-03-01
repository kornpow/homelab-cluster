terraform {
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = ">= 2.1.0"
    }
  }

  backend "s3" {
    bucket         = "terraform-state-hub-kornpow"
    key            = "state/k3s-proxmox"
    region         = "us-west-2"
    dynamodb_table = "terraform-up-and-running-locks"
    encrypt        = true
  }
}

# ── 1Password provider ──────────────────────
# Authenticates via the 1Password desktop app (biometric/Touch ID).
# Requires "Integrate with other apps" in 1Password > Settings > Developer.
provider "onepassword" {
  account = var.op_account
}

# ── Proxmox provider ────────────────────────
# API token is fetched from 1Password at plan/apply time.
# Falls back to var.proxmox_api_token_id/secret if 1Password fields are empty.
provider "proxmox" {
  endpoint = var.proxmox_api_url
  api_token = format("%s=%s",
    local.op_api_token_id != "" ? local.op_api_token_id : var.proxmox_api_token_id,
    local.op_api_token_secret != "" ? local.op_api_token_secret : var.proxmox_api_token_secret,
  )
  insecure = var.proxmox_skip_tls_verify

  ssh {
    agent    = true
    username = "root"
  }
}
