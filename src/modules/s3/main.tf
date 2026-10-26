locals {
  bucket_dir        = "${var.config_dir}/buckets"
  bucket_file_paths = fileset(local.bucket_dir, "**/*.yml")
  bucket_configs = {
    for file_path in local.bucket_file_paths :
    try(yamldecode(file("${local.bucket_dir}/${file_path}")).name, trimsuffix(file_path, ".yml")) => yamldecode(file("${local.bucket_dir}/${file_path}"))
  }
  buckets = merge(aws_s3_bucket.all, aws_s3_bucket.protected)
}

resource "aws_s3_bucket" "all" {
  for_each = var.protect_buckets ? {} : local.bucket_configs

  bucket = "${var.prefix}.${var.env}.${each.key}"
}

# Lifecycle values must be literal, so protected buckets need a separate resource.
resource "aws_s3_bucket" "protected" {
  for_each = var.protect_buckets ? local.bucket_configs : {}

  bucket = "${var.prefix}.${var.env}.${each.key}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "all" {
  for_each = local.bucket_configs

  bucket = local.buckets[each.key].id

  rule {
    object_ownership = try(each.value.object_ownership, "BucketOwnerPreferred")
  }
}

resource "aws_s3_bucket_public_access_block" "all" {
  for_each = local.bucket_configs

  bucket                  = local.buckets[each.key].id
  block_public_acls       = try(each.value.access.block_public_acls, try(regex("public", each.value.access.acl) != "public", true))
  block_public_policy     = try(each.value.access.block_public_policy, try(regex("public", each.value.access.acl) != "public", true))
  ignore_public_acls      = try(each.value.access.ignore_public_acls, try(regex("public", each.value.access.acl) != "public", true))
  restrict_public_buckets = try(each.value.access.restrict_public_buckets, try(regex("public", each.value.access.acl) != "public", true))
}

resource "aws_s3_bucket_acl" "all" {
  for_each = {
    for key, config in local.bucket_configs :
    key => config if try(config.object_ownership, "BucketOwnerPreferred") != "BucketOwnerEnforced"
  }

  bucket = local.buckets[each.key].id
  acl    = try(each.value.access.acl, "private")

  depends_on = [
    aws_s3_bucket_ownership_controls.all,
    aws_s3_bucket_public_access_block.all,
  ]
}

resource "aws_s3_bucket_cors_configuration" "all" {
  for_each = {
    for key, config in local.bucket_configs :
    key => config if try(length(config.cors), 0) > 0
  }

  bucket = local.buckets[each.key].id

  cors_rule {
    allowed_methods = try(each.value.cors.allowed_methods, [])
    allowed_origins = try(each.value.cors.allowed_origins, [])
    allowed_headers = try(each.value.cors.allowed_headers, [])
    expose_headers  = try(each.value.cors.expose_headers, [])
    max_age_seconds = try(each.value.cors.max_age_seconds, 3000)
  }
}

resource "aws_s3_bucket_versioning" "all" {
  for_each = {
    for key, config in local.bucket_configs :
    key => config if try(config.versioning, null) != null
  }

  bucket = local.buckets[each.key].id

  versioning_configuration {
    status = each.value.versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "all" {
  for_each = {
    for key, config in local.bucket_configs :
    key => config if try(config.encryption, null) != null
  }

  bucket = local.buckets[each.key].id

  rule {
    bucket_key_enabled       = try(each.value.encryption.bucket_key_enabled, false)
    blocked_encryption_types = try(each.value.encryption.blocked_encryption_types, null)

    apply_server_side_encryption_by_default {
      sse_algorithm     = each.value.encryption.sse_algorithm
      kms_master_key_id = try(each.value.encryption.kms_master_key_id, null)
    }
  }
}

locals {
  bucket_policy_statements = {
    for key, config in local.bucket_configs : key => concat(
      try(regex("public", config.access.acl) != null, false) ? [{
        Sid       = "AllowPublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${local.buckets[key].arn}/*"
      }] : [],
      try(config.require_tls, false) ? [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.buckets[key].arn, "${local.buckets[key].arn}/*"]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }] : [],
      [for statement in try(config.statements, []) : merge({
        Sid       = statement.sid
        Principal = statement.principal
        Effect    = statement.effect
        Action    = statement.actions
        Resource  = statement.resource
        }, try(statement.condition, null) == null ? {} : {
        Condition = statement.condition
      })]
    )
  }
}

# S3 has one policy per bucket; compose generated and custom statements together.
resource "aws_s3_bucket_policy" "all" {
  for_each = {
    for key, statements in local.bucket_policy_statements :
    key => statements if length(statements) > 0
  }

  bucket = local.buckets[each.key].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = each.value
  })

  depends_on = [aws_s3_bucket_public_access_block.all]
}
