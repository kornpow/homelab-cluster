terraform {
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
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

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_skip_tls_verify

  ssh {
    agent    = true
    username = "root"
  }
}
