locals {
  app_dir        = var.config_dir
  app_file_paths = fileset("", "${local.app_dir}/**/*.yml")
  app_configs = {
    for file_path in local.app_file_paths :
    try(yamldecode(file(file_path)).name, replace(file_path, "/${local.app_dir}|.yml/", "")) => yamldecode(file(file_path))
  }
}

resource "aws_route53_record" "app" {
  for_each = local.app_configs

  zone_id = var.zone_id
  name    = try("${each.value.subdomain}.${var.domain}", var.domain)
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.app[each.key].domain_name
    zone_id                = aws_cloudfront_distribution.app[each.key].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudfront_distribution" "app" {
  for_each = local.app_configs

  enabled             = try(each.value.enabled, true)
  default_root_object = "index.html"
  comment             = try("${each.value.subdomain}.${var.domain}", var.domain)
  aliases             = [try("${each.value.subdomain}.${var.domain}", "*.${var.domain}")]

  origin {
    domain_name = var.s3_bucket_domain
    origin_id   = var.s3_bucket_domain
    origin_path = each.value.path
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  default_cache_behavior {
    target_origin_id       = var.s3_bucket_domain
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}
