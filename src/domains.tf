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
# SES
#

module "ses" {
  source     = "./modules/ses"
  aws_region = var.aws_region
  zone_id    = aws_route53_zone.main.zone_id
  domain     = aws_route53_zone.main.name
  addresses  = [local.devops_email]
}
