variable "certificate_arn" {
  description = "The AWS ARN of the target SSL/TLS certificate from ACM"
  type        = string
}

variable "config_dir" {
  description = "The directory that contains configuration files"
  type        = string
}

variable "domain" {
  description = "The target top domain name for all apps"
  type        = string
}

variable "s3_bucket_domain" {
  description = "The domain name of the S3 bucket hosting the target apps"
  type        = string
}

variable "zone_id" {
  description = "The ID of the target hosted zone"
  type        = string
}
