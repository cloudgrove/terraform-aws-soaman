variable "aws_region" {
  description = "The target AWS region"
  type        = string
  default     = "us-east-1"
}

variable "config_dir" {
  description = "The directory that contains configuration files"
  type        = string
  default     = "config"
}

variable "devops_ssh_key" {
  description = "The SSH public key used by DevOps to access EC2 instances"
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBSfpLd7V352Qx+lQGntER+N2My6jIgux1xzglsbk6PE devops@cloudgrove.io"
}

variable "domain_name" {
  description = "The target domain name"
  type        = string
  default     = "cloudgrove.io"
}

variable "env" {
  description = "The target environment"
  type        = string
  default     = "alpha"
}

variable "s3_prefix" {
  description = "The string prepended to bucket names"
  type        = string
  default     = "cloudgrove"
}

variable "vpn_admin_password" {
  description = "The password of the VPN admin account"
  type        = string
  default     = "inject in TF_VAR_vpn_admin_password or add as a TFC var"
  sensitive   = true
}

variable "vpn_dev_password" {
  description = "The password of the VPN developer account"
  default     = "inject in TF_VAR_vpn_dev_password or add as a TFC var"
  type        = string
  sensitive   = true
}

variable "vpn_instance_ami" {
  description = "The ID of the EC2 AMI to be used for the VPN server"
  type        = string
  default     = "ami-080e1f13689e07408"
}

variable "vpn_instance_type" {
  description = "The type of EC2 instance to be used for the VPN server"
  type        = string
  default     = "t3.micro"
}

variable "vpn_subdomain_prefix" {
  description = "The VPN subdomain prefix"
  type        = string
  default     = "vpn"
}

variable "vpn_vpc" {
  description = "The target VPC to access via VPN"
  type        = string
  default     = "master"
}
