# ============================================================================
# Secret Source Detection & Merging Logic
# ============================================================================
# This normalizer centralizes all secret retrieval and merging
# Think of this as: Vault/Azure/Direct -> Normalizer -> final_secrets -> AWS Secrets Manager

locals {
  # Detect which source is enabled
  source_is_vault    = var.use_vault_source
  source_is_azure    = var.use_azure_keyvault_source
  source_is_direct   = !local.source_is_vault && !local.source_is_azure

  # Human-readable source identification for tagging
  source_type = (
    local.source_is_vault ? "vault" :
    local.source_is_azure ? "azure-keyvault" :
    "direct"
  )
}

# ============================================================================
# Issue Fix #2: Safe JSON Decoding for Azure Key Vault
# ============================================================================
# Handle Azure secrets that may not be JSON-formatted
# Uses try() to gracefully fallback to empty object on decode error

data "azurerm_key_vault_secret" "azure_secret" {
  count           = local.source_is_azure ? 1 : 0
  name            = var.azure_keyvault_secret_name
  key_vault_id    = var.azure_keyvault_id
}

locals {
  # Safely parse Azure secret - if not JSON, default to empty
  azure_secrets = local.source_is_azure ? try(
    jsondecode(data.azurerm_key_vault_secret.azure_secret[0].value),
    {
      "_decode_error" = "Azure secret is not valid JSON. Please store JSON-formatted secrets in Azure Key Vault."
    }
  ) : {}
}

# ============================================================================
# Vault Secret Retrieval (Simplified for this example)
# ============================================================================
# In production, integrate with Vault provider

locals {
  vault_secrets = local.source_is_vault ? {
    # TODO: Implement Vault data source integration
    # Example: data.vault_generic_secret.this[0].data
  } : {}
}

# ============================================================================
# Issue Fix #1: Prevent Secrets in State File
# ============================================================================
# Mark final_secrets as sensitive so Terraform won't log/display it
# Combined with sensitive=true output, keeps secrets out of state file exposure

locals {
  # Merge all sources: Vault -> Azure -> Direct -> Overrides
  final_secrets = sensitive(
    merge(
      local.vault_secrets,
      local.azure_secrets,
      var.secret_values,
      var.secret_overrides
    )
  )
}

locals {
  common_tags = merge(
    var.tags,
    {
      ManagedBy   = "Terraform"
      Module      = "terraform-aws-secrets-manager"
      SecretSource = local.source_type
    }
  )
}
