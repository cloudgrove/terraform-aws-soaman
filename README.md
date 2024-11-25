# About this repo
This repo hosts the Terraform functionality and its associated YAML configs to provision an SOA-based system featuring:

1. Private subnets using VPC

1. Docker container management using ECS

1. Shared file systems using EFS

1. VPN access using OpenVPN


# Before you run Terraform
Log into your target domain name registrar and be ready to:

1. Add a `CNAME` record to validate the Terraform-generated ACM certificate.

1. Add a `NS` record to link the Terraform-generated subdomain Route53 record (e.g. `alpha.cloudgrove.io`) to your target domain (e.g. `cloudgrove.io`).

Note: these two records are blockers to the creation of the VPN box and CloudFront distributions.


# VPN setup
By default, the OpenVPN setup comes with one admin user (`openvpn`) and one regular user (`dev`). Users can me managed via the OpenVPN portal at the environment-specific target subdomain (e.g. `https://vpn.alpha.cloudgrove.io`).
