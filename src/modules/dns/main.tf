provider "aws" {
  alias  = "global"
  region = "us-east-1"
}

resource "aws_acm_certificate" "cloudfront" {
  domain_name               = "*.${var.env}.${var.domain}"
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"
  provider                  = aws.global
}

resource "aws_acm_certificate" "main" {
  domain_name               = "*.${var.env}.${var.domain}"
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"
}

resource "aws_route53_zone" "main" {
  name = "${var.env}.${var.domain}"
}

resource "aws_route53_record" "main" {
  for_each = {
    for option in aws_acm_certificate.main.domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    } if can(regex("^([^.]+|\\*)\\.${var.env}\\.${var.domain}$", option.domain_name))
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "time_sleep" "main" {
  create_duration = "60s"

  depends_on = [aws_acm_certificate.main]
}
