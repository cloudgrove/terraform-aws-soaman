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
# Hosted zones
#

resource "aws_route53_zone" "main" {
  name = local.subdomain
}

#
# Certificates
#

resource "aws_acm_certificate" "main" {
  domain_name       = "*.${local.subdomain}"
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

#
# Modules
#

module "iam" {
  source     = "./modules/iam"
  config_dir = "${path.module}/config"
}

module "s3" {
  source     = "./modules/s3"
  config_dir = "${path.module}/config"
  env        = var.env
  prefix     = var.s3_prefix
}

module "ses" {
  source     = "./modules/ses"
  aws_region = var.aws_region
  zone_id    = aws_route53_zone.main.zone_id
  domain     = aws_route53_zone.main.name
  addresses  = [local.devops_email]
}

module "soa" {
  source          = "./modules/soa"
  config_dir      = "${path.module}/config"
  aws_region      = var.aws_region
  zone_id         = aws_route53_zone.main.zone_id
  domain          = "${var.subdomain_api_prefix}.${aws_route53_zone.main.name}"
  env             = var.env
  certificate_arn = aws_acm_certificate.main.arn
}

module "vpn" {
  source              = "./modules/openvpn"
  vpc_id              = module.soa.vpcs["master"].id
  public_subnet_id    = element(values(module.soa.public_subnets).*.id, 1)
  zone_id             = aws_route53_zone.main.zone_id
  domain              = "${var.subdomain_vpn_prefix}.${aws_route53_zone.main.name}"
  email               = local.devops_email
  admin_password      = var.vpn_admin_password
  dev_password        = var.vpn_dev_password
  ssh_key_name        = aws_key_pair.devops.key_name
  efs_security_groups = module.soa.cluster_security_groups
}
