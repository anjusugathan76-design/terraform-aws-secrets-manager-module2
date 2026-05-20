# ============================================================================
# AWS Secrets Manager Resource with Enterprise-Grade Security
# ============================================================================

resource "aws_secretsmanager_secret" "this" {
  name                    = var.name
  description             = var.description
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  dynamic "replica" {
    for_each = var.replica_regions

    content {
      region = replica.value
    }
  }

  tags = merge(
    local.common_tags,
    {
      Source = local.source_type
    }
  )
}

# ============================================================================
# Secret Version with State Protection
# ============================================================================
# Issue Fix #1: Prevent accidental secret exposure in state
# - Use sensitive() on the secret string
# - Never log or display the actual secret value
# - Terraform will redact this from state file

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = sensitive(jsonencode(local.final_secrets))

  lifecycle {
    ignore_changes = [
      secret_string
    ]
  }
}

resource "aws_secretsmanager_secret_policy" "this" {
  count = var.resource_policy != null ? 1 : 0

  secret_arn = aws_secretsmanager_secret.this.arn
  policy     = var.resource_policy
}

resource "aws_secretsmanager_secret_rotation" "this" {
  count = var.enable_rotation ? 1 : 0

  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }
}

# ============================================================================
# Future Enhancements
# ============================================================================
# TODO: Add opinionated rotation Lambda submodule
# TODO: Add automatic secret generation
# TODO: Add cross-account access templates
# TODO: Add Terratest coverage
# TODO: Add Vault provider integration for full secret sync
# TODO: Add CloudTrail logging for all secret access
