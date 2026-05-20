# ============================================================================
# Secret Source Type Tracking (No Secret Retrieval)
# ============================================================================
# This file documents which secret source is being used for audit/compliance.
# 
# IMPORTANT: This module does NOT fetch secrets from Vault or Azure.
# Secrets should be retrieved OUTSIDE this module and passed via var.secret_values
#
# This keeps secrets out of Terraform state and ensures proper separation of concerns.

locals {
  # Determine the source type for tracking and tagging purposes only
  source_type = var.use_vault_source ? "vault" : (
    var.use_azure_keyvault_source ? "azure_keyvault" : "direct"
  )
}

# ============================================================================
# CORRECT USAGE PATTERN (How to use this module)
# ============================================================================
#
# ✅ CORRECT - Fetch secrets OUTSIDE module, pass to module:
#
# data "external" "vault_secrets" {
#   program = ["bash", "${path.module}/scripts/fetch-from-vault.sh"]
#
#   query = {
#     vault_addr  = var.vault_addr
#     vault_token = var.vault_token
#     secret_path = var.vault_secret_path
#   }
# }
#
# module "secrets_manager" {
#   source = "./path/to/module"
#
#   name           = "my-app-secrets"
#   secret_values  = jsondecode(data.external.vault_secrets.result.secrets)
#   use_vault_source = true  # For tracking only
#
#   tags = {
#     SecretSource = local.source_type
#   }
# }
#
# ============================================================================
#
# ❌ WRONG - Module should NOT do this:
#   - Call Vault data sources directly
#   - Call Azure Key Vault data sources directly
#   - Decode JSON inside module
#   - Store secrets in local values
#
# Why? Terraform state will capture them regardless of sensitive() wrapping
#
# ============================================================================
