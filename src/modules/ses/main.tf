resource "aws_ses_configuration_set" "main" {
  name = "main"
  reputation_metrics_enabled = true
}

resource "aws_ses_domain_identity" "main" {
  domain = var.domain
}

resource "aws_ses_domain_identity_verification" "main" {
  domain = aws_ses_domain_identity.main.id

  depends_on = [aws_route53_record.dkim]
}

resource "aws_ses_domain_mail_from" "main" {
  domain = var.domain
  mail_from_domain = "mail.${var.domain}"

  depends_on = [aws_ses_domain_identity.main]
}

resource "aws_ses_domain_dkim" "main" {
  domain = aws_ses_domain_identity.main.domain
}

resource "aws_route53_record" "dkim" {
  count   = 3
  zone_id = var.zone_id
  name    = "${aws_ses_domain_dkim.main.dkim_tokens[count.index]}._domainkey.${aws_ses_domain_identity.main.domain}"
  type    = "CNAME"
  ttl     = 300
  records = ["${aws_ses_domain_dkim.main.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

resource "aws_route53_record" "mx" {
  zone_id = var.zone_id
  name    = "mail.${var.domain}"
  type    = "MX"
  ttl     = 300
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]

  depends_on = [aws_ses_domain_mail_from.main]
}

resource "aws_route53_record" "spf" {
  zone_id = var.zone_id
  name    = "mail.${var.domain}"
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:amazonses.com ~all"]

  depends_on = [aws_ses_domain_mail_from.main]
}

resource "aws_route53_record" "bimi" {
  zone_id = var.zone_id
  name    = "_bimi.${var.domain}"
  type    = "TXT"
  ttl     = 300
  records = [format("v=BIMI1;l=https://%s/bimi/logo.svg;a=https://%s/bimi/auth.svg", var.domain, var.domain)]
}

resource "aws_route53_record" "dmarc" {
  zone_id = var.zone_id
  name    = "_dmarc.${var.domain}"
  type    = "TXT"
  ttl     = 300
  records = [format("v=DMARC1;p=quarantine;rua=mailto:%s", "dmarc_report@${var.domain}")]
}

resource "aws_ses_email_identity" "email_addresses" {
  for_each = toset(var.addresses)

  email = each.value
}
