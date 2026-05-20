output "secret_arn" {
  description = "ARN of the secret (for IAM policies, Lambda access, applications)"
  value       = aws_secretsmanager_secret.this.arn
  sensitive   = false
}

output "secret_name" {
  description = "Name of the secret (for application lookups and AWS CLI)"
  value       = aws_secretsmanager_secret.this.name
  sensitive   = false
}

output "secret_id" {
  description = "ID of the secret (same as name, use for AWS API calls)"
  value       = aws_secretsmanager_secret.this.id
  sensitive   = false
}

output "kms_key_id" {
  description = "KMS key ID used for encryption"
  value       = aws_secretsmanager_secret.this.kms_key_id
  sensitive   = false
}

output "replica_regions" {
  description = "List of regions where secret is replicated"
  value       = var.replica_regions
  sensitive   = false
}

# ============================================================================
# Enterprise Metadata Outputs
# ============================================================================
# Issue Fix #3: Source tracking for compliance & audit

output "source_type" {
  description = "Secret source type (vault, azure-keyvault, or direct)"
  value       = local.source_type
  sensitive   = false
}

output "secret_version_id" {
  description = "Version ID of the secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret_version.this.version_id
  sensitive   = false
}
