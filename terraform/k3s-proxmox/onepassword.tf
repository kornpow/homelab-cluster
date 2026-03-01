# ──────────────────────────────────────────────
# 1Password provider — fetches Proxmox API tokens
# ──────────────────────────────────────────────
# Authenticates via the 1Password desktop app (biometric).
# Requires "Integrate with other apps" enabled in 1Password
# Settings > Developer.
#
# Set OP_ACCOUNT env var or var.op_account to your 1Password
# account name/ID. Run `op account get` to find it.
# ──────────────────────────────────────────────

data "onepassword_vault" "proxmox" {
  name = var.op_vault
}

data "onepassword_item" "proxmox_creds" {
  vault = data.onepassword_vault.proxmox.uuid
  title = var.op_item_title
}

locals {
  # Extract the API token fields from the 1Password item.
  # The item should have fields named "API Token ID" and "API Token Secret"
  # (added via `op item edit` — see docs/proxmox-setup.md).
  #
  # We search through all sections' fields to find them by label.
  _all_fields = flatten([
    for section in data.onepassword_item.proxmox_creds.section : [
      for field in section.field : {
        label = field.label
        value = field.value
      }
    ]
  ])

  _field_map = { for f in local._all_fields : f.label => f.value }

  op_api_token_id     = lookup(local._field_map, "API Token ID", "")
  op_api_token_secret = lookup(local._field_map, "API Token Secret", "")
}
