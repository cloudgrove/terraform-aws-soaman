resource "aws_lb_listener_rule" "admin_path_block" {
  for_each = { for k, v in local.cluster_configs : k => v if try(v.entrypoint, null) != null }

  listener_arn = aws_lb_listener.entrypoint[each.key].arn
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

resource "aws_lb_listener" "entrypoint" {
  for_each = { for k, v in local.cluster_configs : k => v if try(v.entrypoint, null) != null }

  load_balancer_arn = aws_lb.alb[each.key].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.lb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.microservice[each.value.entrypoint].arn
  }
}

resource "aws_lb_target_group_attachment" "link" {
  for_each = { for k, v in local.cluster_configs : k => v if try(v.entrypoint, null) != null }

  target_id        = aws_lb.alb[each.key].id
  target_group_arn = aws_lb_target_group.link[each.key].arn

  depends_on = [aws_lb_listener.entrypoint]
}

resource "aws_lb_target_group" "link" {
  for_each = { for k, v in local.cluster_configs : k => v if try(v.entrypoint, null) != null }

  name        = aws_lb.alb[each.key].name
  vpc_id      = aws_vpc.all[each.value.vpc].id
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

resource "aws_lb_listener" "link" {
  for_each = { for k, v in local.cluster_configs : k => v if try(v.entrypoint, null) != null }

  load_balancer_arn = aws_lb.link[each.key].arn
  protocol          = "TCP"
  port              = 443

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.link[each.key].arn
  }
}

resource "aws_lb" "link" {
  for_each = { for k, v in local.cluster_configs : k => v if try(v.entrypoint, null) != null }

  name               = "${each.value.vpc}-${each.key}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.public : subnet.id if subnet.vpc_id == aws_vpc.all[each.value.vpc].id]
  security_groups    = [aws_security_group.link[each.key].id]
}

resource "aws_security_group" "link" {
  for_each = { for k, v in local.cluster_configs : k => v if try(v.entrypoint, null) != null }

  name   = "soa-${each.value.vpc}.${each.key}.nlb"
  vpc_id = aws_vpc.all[each.value.vpc].id

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_cloudfront_distribution" "link" {
  for_each = { for k, v in local.cluster_configs : k => v if try(v.entrypoint, null) != null }

  origin {
    domain_name = aws_lb.link[each.key].dns_name
    origin_id   = local.cluster_domains[each.key]

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
  comment             = local.cluster_domains[each.key]

  aliases = [local.cluster_domains[each.key]]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.cluster_domains[each.key]

    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
    cache_policy_id          = aws_cloudfront_cache_policy.link.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.link.id
  }

  viewer_certificate {
    acm_certificate_arn      = var.cf_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_cloudfront_cache_policy" "link" {
  name        = "soa-link"
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

resource "aws_cloudfront_origin_request_policy" "link" {
  name = "soa-link"

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

resource "aws_route53_record" "link" {
  for_each = { for k, v in local.cluster_configs : k => v if try(v.entrypoint, null) != null }

  name    = local.cluster_domains[each.key]
  zone_id = var.zone_id
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.link[each.key].domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}
