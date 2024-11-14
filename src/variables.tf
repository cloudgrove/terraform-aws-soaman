variable "aws_access_key" {
  description = "The AWS access key"
  type        = string
  default     = ""
}

variable "aws_secret_key" {
  description = "The AWS secret key"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_region" {
  description = "The target AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "The target domain name"
  type        = string
  default     = "cloudgrove.io"
}
