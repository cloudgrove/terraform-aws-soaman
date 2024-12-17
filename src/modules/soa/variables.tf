variable "aws_region" {
  description = "The target AWS region"
  type        = string
}

variable "certificate_arn" {
  description = "The AWS ARN of the target SSL/TLS certificate from ACM"
  type        = string
}

variable "config_dir" {
  description = "The directory that contains configuration files"
  type        = string
}

variable "domain" {
  description = "The target domain name for the gateway"
  type        = string
}

variable "env" {
  description = "The target environment"
  type        = string
}

variable "gateway_service_name" {
  description = "The name of the gateway service running in ECS"
  type        = string
  default     = "gateway-service"
}

variable "zone_id" {
  description = "The ID of the target hosted zone"
  type        = string
}
