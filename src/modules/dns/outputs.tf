output "certificate_arn" {
  value = aws_acm_certificate.main.arn
}

output "cloudfront_certificate_arn" {
  value = aws_acm_certificate.cloudfront.arn
}

output "zone_id" {
  value = aws_route53_zone.main.zone_id
}
