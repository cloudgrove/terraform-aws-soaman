output "original_key_arn" {
  value = data.aws_kms_key.main.arn
}

output "replica_key_arn" {
  value = aws_kms_replica_key.replica.arn
}
