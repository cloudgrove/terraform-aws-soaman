output "buckets" {
  description = "S3 bucket resources by configured name, including protected buckets."
  value       = local.buckets
}
