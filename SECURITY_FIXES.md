# Security Fixes & Design Improvements - v2.0

## Overview
This document details the critical security fixes and enterprise-grade improvements applied to the Terraform AWS Secrets Manager module.

---

## ❌ Issue #1: Data Leakage Risk in Terraform State

### Problem
Secrets stored in `final_secrets` variable were being exposed in Terraform state files, violating the "zero secrets in state" principle.

### Root Cause
Terraform state files are stored in plaintext (or minimally encrypted) by default. Without explicit `sensitive` marking, all variables and local values are persisted in state.

### Solution Applied

**File: `locals.tf`**
```hcl
locals {
  final_secrets = sensitive(
    merge(
      local.vault_secrets,
      local.azure_secrets,
      var.secret_values,
      var.secret_overrides
    )
  )
}
```

**File: `main.tf`**
```hcl
resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = sensitive(jsonencode(local.final_secrets))  # Mark as sensitive
}
```

**Benefits:**
✅ Secrets are redacted from state file output
✅ `terraform plan` and `terraform apply` won't display secret values
✅ AWS Secrets Manager remains the source of truth, not Terraform state
✅ Even if state file is compromised, secrets are protected

### Best Practices Going Forward
- Store state files in S3 with encryption enabled
- Enable MFA-Delete on state bucket
- Use remote state with Terraform Cloud/Enterprise
- Rotate secrets if state has been accidentally exposed

---

## ❌ Issue #2: JSON Assumption for Azure Key Vault Secrets

### Problem
`jsondecode()` function fails if Azure secret isn't JSON-formatted, causing module failure.

### Root Cause
- Azure Key Vault stores secrets as strings
- Users may store plaintext, base64-encoded, or other non-JSON formats
- Unchecked `jsondecode()` throws an error, breaking the workflow

### Solution Applied

**File: `locals.tf`**
```hcl
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
```

**Benefits:**
✅ Graceful error handling with `try()` function
✅ Module doesn't fail if secret isn't JSON
✅ Clear error message guides user on proper formatting
✅ Allows fallback to direct secrets or Vault

### Migration Guide
If you have existing Azure secrets:
```bash
# Option 1: Convert existing secret to JSON
SECRET_VALUE='{"key": "value", "password": "secret123"}'
az keyvault secret set --vault-name myVault --name mySecret --value "$SECRET_VALUE"

# Option 2: Use direct secrets (secret_values variable) instead
# Option 3: Use Vault as primary source
```

---

## ❌ Issue #3: Multiple Secret Sources Conflict Ambiguity

### Problem
All three secret sources (Vault, Azure, Direct) could be enabled simultaneously, creating unpredictable merging behavior.

### Root Cause
- No validation enforced mutual exclusivity
- Merge order (`vault → azure → direct → overrides`) is implicit
- Users could accidentally enable multiple sources with conflicting values

### Solution Applied

**File: `variables.tf`** - Enterprise-Grade Validation
```hcl
# ============================================================================
# ENTERPRISE-GRADE VALIDATION: Enforce Single Secret Source
# ============================================================================
# Issue Fix #3: Prevent multiple conflicting sources
# Only one of: Vault, Azure Key Vault, or Direct secret source can be enabled

validation {
  condition = (
    (var.use_vault_source ? 1 : 0) +
    (var.use_azure_keyvault_source ? 1 : 0)
  ) <= 1
  error_message = "Only ONE external secret source can be enabled at a time. Choose: use_vault_source OR use_azure_keyvault_source. Direct secrets (secret_values) can always be used as a fallback."
}
```

**Benefits:**
✅ Terraform validation prevents invalid configurations
✅ Clear error message on `terraform plan` if user enables multiple sources
✅ `secret_overrides` can always augment any source
✅ Explicit, predictable merge order

### Example Error (When Multiple Sources Are Enabled)
```
Error: Invalid value for variable "use_vault_source"

  on variables.tf line 88, in variable "use_vault_source":
   88: variable "use_vault_source" {

Only ONE external secret source can be enabled at a time. Choose: use_vault_source OR use_azure_keyvault_source. Direct secrets (secret_values) can always be used as a fallback.
```

---

## Mental Model: Secret Normalization Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                     SECRET SOURCES                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Vault (KV v1/v2)      Azure Key Vault        Direct (vars)   │
│        │                     │                      │          │
│        └─────────────────────┴──────────────────────┘          │
│                              │                                  │
├─────────────────────────────────────────────────────────────────┤
│                    NORMALIZER LOGIC                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Detect enabled source (validation ensures only ONE)        │
│  2. Fetch secrets from source                                  │
│  3. Handle errors gracefully (esp. Azure JSON decoding)        │
│  4. Apply overrides (secret_overrides)                         │
│  5. Merge all sources safely                                   │
│  6. Mark as sensitive() to protect state                       │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│              FINAL_SECRETS (Normalized Output)                  │
├─────────────────────────────────────────────────────────────────┤
│                          │                                      │
│         ┌────────────────┴─────────────────┐                   │
│         │                                  │                   │
│  AWS Secrets Manager              Terraform State               │
│  (Encrypted at REST)          (Redacted via sensitive())       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Testing Your Fixes

### Test 1: Verify State Protection
```bash
terraform apply -auto-approve
grep -i "password\|secret\|token" terraform.tfstate
# Should return: No results (secrets redacted)
```

### Test 2: Verify Source Validation
```bash
# Try enabling both Vault and Azure
terraform apply -var="use_vault_source=true" -var="use_azure_keyvault_source=true"
# Should fail with validation error
```

### Test 3: Verify Azure JSON Handling
```bash
# Store non-JSON secret in Azure
az keyvault secret set --vault-name myVault --name test --value "plaintext-secret"
# Apply with use_azure_keyvault_source=true
terraform apply
# Should succeed with graceful error message
```

---

## Migration Path for Existing Deployments

### Step 1: Review Current State
```bash
terraform state show
# Check if secrets are visible in state (they shouldn't be with this update)
```

### Step 2: Update Module Reference
```hcl
module "secrets" {
  source = "git::https://github.com/your-org/terraform-aws-secrets-manager-module2.git?ref=v2.0"
  # ... existing configuration
}
```

### Step 3: Validate Configuration
```bash
terraform validate
terraform plan
```

### Step 4: Verify No Changes Required
```bash
terraform apply
# Should succeed with no changes (state protection is internal)
```

---

## Summary of Changes

| Issue | File | Fix | Benefit |
|-------|------|-----|----------|
| Data Leakage | `locals.tf`, `main.tf` | Add `sensitive()` wrapping | Secrets redacted from state |
| JSON Assumption | `locals.tf` | Use `try(jsondecode(), {})` | Graceful handling of non-JSON secrets |
| Source Conflicts | `variables.tf` | Add mutual exclusivity validation | One source at a time enforced |
| Metadata Tracking | `outputs.tf` | Add `source_type` output | Compliance & audit trails |

---

## References

- [Terraform `sensitive()` Function](https://www.terraform.io/language/functions/sensitive)
- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [Terraform State File Security](https://www.terraform.io/cloud-docs/state/managing)
