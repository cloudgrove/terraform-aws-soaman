locals {
  gateway_vpc = local.microservice_configs[var.gateway_service_name].vpc
}

resource "aws_lb_listener" "gateway_service_nlb" {
  for_each = aws_lb.nlb

  load_balancer_arn = aws_lb.nlb[each.key].arn
  protocol          = "TCP"
  port              = 443

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway_service_alb.arn
  }
}

resource "aws_lb_target_group" "gateway_service_alb" {
  name        = "${var.gateway_service_name}-alb"
  vpc_id      = aws_vpc.all[local.gateway_vpc].id
  target_type = "alb"
  protocol    = "TCP"
  port        = 443

  health_check {
    protocol            = "HTTPS"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 3
  }
}

resource "aws_lb_target_group_attachment" "gateway_service_alb" {
  target_id        = aws_lb.alb[local.gateway_vpc].id
  target_group_arn = aws_lb_target_group.gateway_service_alb.arn

  depends_on = [aws_lb_listener.gateway_service]
}

resource "aws_lb_listener" "gateway_service" {
  load_balancer_arn = aws_lb.alb[local.gateway_vpc].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.microservice[var.gateway_service_name].arn
  }
}

resource "aws_lb_listener_rule" "admin_path_block" {
  listener_arn = aws_lb_listener.gateway_service.arn
  priority     = 1

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Access denied"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/admin/*"]
    }
  }

  tags = {
    Name = "block-admin-paths"
  }
}

resource "aws_cloudfront_distribution" "gateway_service" {
  origin {
    domain_name = aws_lb.nlb[local.gateway_vpc].dns_name
    origin_id   = var.domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2"
  default_root_object = ""
  price_class         = "PriceClass_All"
  comment             = var.gateway_service_name

  aliases = [var.domain]

  default_cache_behavior {
    allowed_methods     = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods      = ["GET", "HEAD"]
    target_origin_id    = var.domain

    viewer_protocol_policy    = "redirect-to-https"
    compress                  = true
    cache_policy_id           = aws_cloudfront_cache_policy.gateway_service.id
    origin_request_policy_id  = aws_cloudfront_origin_request_policy.gateway_service.id
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

resource "aws_cloudfront_cache_policy" "gateway_service" {
  name    = var.gateway_service_name

  default_ttl = 200
  max_ttl     = 200
  min_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = [
          "host",
          "origin",
          "x-http-method",
          "x-http-method-override",
          "x-method-override",
        ]
      }
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

resource "aws_cloudfront_origin_request_policy" "gateway_service" {
  name    = var.gateway_service_name

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "allViewer"
  }

  query_strings_config {
    query_string_behavior = "none"
  }
}

resource "aws_route53_record" "gateway_service" {
  name    = var.domain
  zone_id = var.zone_id
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.gateway_service.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}
