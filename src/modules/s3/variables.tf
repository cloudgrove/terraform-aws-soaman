variable "config_dir" {
  description = "The directory that contains configuration files"
  type        = string
}

variable "env" {
  description = "The target environment"
  type        = string
}

variable "prefix" {
  description = "The string prepended to bucket names"
  type        = string
}

variable "protect_buckets" {
  description = "Use buckets with prevent_destroy enabled. Changing this requires explicit bucket state moves; see the S3 migration guide."
  type        = bool
  default     = false
}
