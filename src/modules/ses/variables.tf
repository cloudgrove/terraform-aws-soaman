variable "addresses" {
  description = "The list of email addresses that should be enabled in SES"
  type        = list
  default     = []
}

variable "aws_region" {
  description = "The target AWS region"
  type        = string
}

variable "domain" {
  description = "The target domain name"
  type        = string
}

variable "zone_id" {
  description = "The ID of the target hosted zone"
  type        = string
}
