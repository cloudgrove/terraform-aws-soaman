variable "admin_username" {
  description = ""
  type        = string
  default     = "openvpn"
}

variable "admin_password" {
  description = ""
  type        = string
  sensitive   = true
}

variable "dev_username" {
  description = ""
  type        = string
  default     = "dev"
}

variable "dev_password" {
  description = ""
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "The target domain name for the VPN server"
  type        = string
}

variable "email" {
  description = "The email address used for alerts"
  type        = string
}

variable "private_subnet_cidr" {
  description = "The CIDR block representing the private subnet to which VPN clients should have access"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_id" {
  description = "The AWS ID of the public subnet where the EC2 instance resides"
  type        = string
}

variable "ssh_key_name" {
  description = "The AWS name of the target SSH key"
  type        = string
}

variable "target_security_groups" {
  description = "A map containing the security groups whose resources are to be accessed"
  type        = map
  default     = {}
}

variable "vpc_id" {
  description = "The ID of the target VPC"
  type        = string
}

variable "zone_id" {
  description = "The ID of the target hosted zone"
  type        = string
}
