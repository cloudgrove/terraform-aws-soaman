locals {
  devops_email = "devops@${var.domain_name}"
  subdomain    = "${var.env}.${var.domain_name}"
}

#
# SSH keys
#

resource "aws_key_pair" "devops" {
  key_name   = "devops-key"
  public_key = var.devops_ssh_key
}

#
# Modules
#

module "appset" {
  source           = "../../modules/appset"
  config_dir       = "${path.module}/config/apps"
  zone_id          = module.dns.zone_id
  domain           = local.subdomain
  s3_bucket_domain = module.s3.buckets["public-assets"].bucket_regional_domain_name
  certificate_arn  = module.dns.certificate_arn
}

module "dns" {
  source = "../../modules/dns"
  domain = local.subdomain
}

module "iam" {
  source     = "../../modules/iam"
  config_dir = "${path.module}/config"
}

module "s3" {
  source     = "../../modules/s3"
  config_dir = "${path.module}/config"
  env        = var.env
  prefix     = var.s3_prefix
}

module "ses" {
  source     = "../../modules/ses"
  aws_region = var.aws_region
  zone_id    = module.dns.zone_id
  domain     = local.subdomain
  addresses  = [local.devops_email]
}

module "soa" {
  source             = "../../modules/soa"
  config_dir         = "${path.module}/config"
  aws_region         = var.aws_region
  zone_id            = module.dns.zone_id
  domain             = local.subdomain
  env                = var.env
  lb_certificate_arn = module.dns.certificate_arn
  cf_certificate_arn = module.dns.cloudfront_certificate_arn
}

module "vpn" {
  source                 = "../../modules/openvpn"
  vpc_id                 = module.soa.vpcs[var.vpn_vpc].id
  public_subnet_id       = element(values(module.soa.public_subnets).*.id, 1)
  zone_id                = module.dns.zone_id
  domain                 = "${var.vpn_subdomain_prefix}.${local.subdomain}"
  email                  = local.devops_email
  admin_password         = var.vpn_admin_password
  dev_password           = var.vpn_dev_password
  instance_ami           = var.vpn_instance_ami
  instance_type          = var.vpn_instance_type
  ssh_key_name           = aws_key_pair.devops.key_name
  target_security_groups = module.soa.security_groups
}
