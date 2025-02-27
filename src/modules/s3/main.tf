locals {
  bucket_dir        = "${var.config_dir}/buckets/"
  bucket_file_paths = fileset("", "${local.bucket_dir}/**/*.yml")
  bucket_configs = {
    for file_path in local.bucket_file_paths :
    try(yamldecode(file(file_path)).name, replace(file_path, "/${local.bucket_dir}|.yml/", "")) => yamldecode(file(file_path))
  }
}

resource "aws_s3_bucket" "all" {
  for_each = local.bucket_configs

  bucket = "${var.prefix}.${var.env}.${each.value.name}"
}

resource "aws_s3_bucket_ownership_controls" "all" {
  for_each = local.bucket_configs

  bucket = aws_s3_bucket.all[each.value.name].id

  rule {
    object_ownership = try(each.value.object_ownership, "BucketOwnerPreferred")
  }
}

resource "aws_s3_bucket_public_access_block" "all" {
  for_each = local.bucket_configs

  bucket                  = aws_s3_bucket.all[each.value.name].id
  block_public_acls       = try(each.value.access.block_public_acls, try(regex("public", each.value.access.acl) != "public", true))
  block_public_policy     = try(each.value.access.block_public_policy, try(regex("public", each.value.access.acl) != "public", true))
  ignore_public_acls      = try(each.value.access.ignore_public_acls, try(regex("public", each.value.access.acl) != "public", true))
  restrict_public_buckets = try(each.value.access.restrict_public_buckets, try(regex("public", each.value.access.acl) != "public", true))
}

resource "aws_s3_bucket_acl" "all" {
  for_each = local.bucket_configs

  bucket = aws_s3_bucket.all[each.value.name].id
  acl    = try(each.value.access.acl, "private")

  depends_on = [
    aws_s3_bucket_ownership_controls.all,
    aws_s3_bucket_public_access_block.all,
  ]
}

resource "aws_s3_bucket_cors_configuration" "all" {
  for_each = {
    for key, config in local.bucket_configs :
    key => config if length(try(config.cors, [])) > 0
  }

  bucket = aws_s3_bucket.all[each.value.name].id

  cors_rule {
    allowed_methods = try(each.value.cors.allowed_methods, [])
    allowed_origins = try(each.value.cors.allowed_origins, [])
    allowed_headers = try(each.value.cors.allowed_headers, [])
    expose_headers  = try(each.value.cors.expose_headers, [])
    max_age_seconds = try(each.value.cors.max_age_seconds, 3000)
  }
}

resource "aws_s3_bucket_policy" "public" {
  for_each = {
    for key, config in local.bucket_configs :
    key => config if try(regex("public", config.access.acl) != null, false)
  }

  bucket = aws_s3_bucket.all[each.value.name].id

  policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Sid       = "AllowPublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.all[each.value.name].arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "custom" {
  for_each = {
    for key, config in local.bucket_configs :
    key => config if length(try(config.statements, [])) > 0
  }

  bucket = aws_s3_bucket.all[each.value.name].id

  policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      for statement in each.value.statements : {
        Sid       = statement.sid
        Principal = statement.principal
        Effect    = statement.effect
        Action    = statement.actions
        Resource  = statement.resource
      }
    ]
  })
}
