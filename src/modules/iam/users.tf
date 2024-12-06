locals {
  user_dir        = "${var.config_dir}/users/"
  user_file_paths = fileset("", "${local.user_dir}/**/*.yml")
  user_configs = {
    for file_path in local.user_file_paths :
    try(yamldecode(file(file_path)).name, replace(file_path, "/${local.user_dir}|.yml/", "")) => yamldecode(file(file_path))
  }
  user_policies = merge(flatten([
    for user, config in local.user_configs : {
      for policy in try(config.policies, []) :
      "${user}-${policy}" => { user = user, policy = policy }
    }
  ])...)
}

resource "aws_iam_user" "all" {
  for_each = local.user_configs

  name     = each.value.name
}

data "aws_iam_policy_document" "custom_policies" {
  for_each = local.user_configs

  dynamic "statement" {
    for_each = try(each.value.statements, [])

    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_user_policy" "custom_policies" {
  for_each = data.aws_iam_policy_document.custom_policies

  name   = each.key
  user   = each.key
  policy = each.value.json
}


resource "aws_iam_user_policy_attachment" "policies" {
  for_each = local.user_policies

  user       = each.value.user
  policy_arn = each.value.policy
}
