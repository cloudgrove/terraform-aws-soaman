variable "domain_name" {
  description = "The target domain name"
  type        = string
  default     = "cloudgrove.io"
}

output "domain_name" {
  value = var.domain_name
}
