variable "aws_region" {
  description = "The target AWS region"
  type        = string
}

variable "lb_certificate_arn" {
  description = "The AWS ARN of the target ACM certificate for load balancers"
  type        = string
}

variable "cf_certificate_arn" {
  description = "The AWS ARN of the target ACM certificate for CloudFront distributions"
  type        = string
}

variable "config_dir" {
  description = "The directory that contains configuration files"
  type        = string
}

variable "domain" {
  description = "The base domain name for APIs"
  type        = string
}

variable "env" {
  description = "The target environment"
  type        = string
}

variable "zone_id" {
  description = "The ID of the target hosted zone"
  type        = string
}
