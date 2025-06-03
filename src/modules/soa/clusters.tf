locals {
  cluster_dir        = "${var.config_dir}/clusters/"
  cluster_file_paths = fileset("", "${local.cluster_dir}/**/*.yml")
  cluster_configs = {
    for file_path in local.cluster_file_paths :
    try(yamldecode(file(file_path)).name, replace(file_path, "/${local.cluster_dir}|.yml/", "")) => yamldecode(file(file_path))
  }
  cluster_domains = {
    for cluster, cluster_config in local.cluster_configs :
    cluster => "${try(cluster_config.subdomain, cluster_config.name)}.${var.domain}"
  }
  cluster_subnets = merge(flatten([
    for cluster, cluster_config in local.cluster_configs : {
      for subnet, subnet_config in local.private_subnet_configs :
      "${cluster}.${subnet}" => merge(subnet_config, { cluster_name = cluster, subnet_name = subnet }) if startswith(subnet, "${cluster_config.vpc}.")
    }
  ])...)
}

#
# ECS
#

resource "aws_ecs_cluster" "all" {
  for_each = local.cluster_configs

  name = each.key

  setting {
    name  = "containerInsights"
    value = try(each.value.container_insights, "disabled")
  }
}

#
# Load balancers
#

resource "aws_lb" "alb" {
  for_each = local.cluster_configs

  name               = "${each.value.vpc}-${each.key}-alb"
  load_balancer_type = "application"
  internal           = true
  subnets            = [for subnet in aws_subnet.private : subnet.id if subnet.vpc_id == aws_vpc.all[each.value.vpc].id]
  security_groups    = [aws_security_group.alb[each.key].id]
}

resource "aws_security_group" "alb" {
  for_each = local.cluster_configs

  name   = "soa-${each.value.vpc}.${each.key}.alb"
  vpc_id = aws_vpc.all[each.value.vpc].id

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = local.cluster_configs

  security_group_id = aws_security_group.alb[each.key].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_route53_record" "alb" {
  for_each = local.cluster_configs

  zone_id = aws_route53_zone.internal[each.value.vpc].id
  name    = each.key
  type    = "CNAME"
  ttl     = "30"
  records = [aws_lb.alb[each.key].dns_name]
}

#
# EFS
#

resource "aws_efs_file_system" "cluster" {
  for_each = local.cluster_configs

  creation_token   = each.key
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "soa-${each.value.vpc}.${each.key}"
  }
}

resource "aws_efs_mount_target" "cluster" {
  for_each = local.cluster_subnets

  file_system_id  = aws_efs_file_system.cluster[each.value.cluster_name].id
  subnet_id       = aws_subnet.private[each.value.subnet_name].id
  security_groups = [aws_security_group.cluster[each.value.cluster_name].id]
}

resource "aws_security_group" "cluster" {
  for_each = local.cluster_configs

  name   = "soa-${each.value.vpc}.${each.key}.efs"
  vpc_id = aws_vpc.all[each.value.vpc].id
}

resource "aws_security_group_rule" "cluster_efs" {
  for_each = local.cluster_configs

  type              = "ingress"
  protocol          = "tcp"
  from_port         = 2049
  to_port           = 2049
  cidr_blocks       = values({ for k, v in aws_subnet.private : k => v if startswith(k, "${each.value.vpc}.") })[*].cidr_block
  security_group_id = aws_security_group.cluster[each.key].id
}

#
# IAM
#

resource "aws_iam_role" "ecs_task_execution" {
  name = "AmazonECSTaskExecution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "ecs_task_execution" {
  name       = "AmazonECSTaskExecution"
  roles      = [aws_iam_role.ecs_task_execution.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "ecs_task_extra" {
  name        = "AmazonECSTaskExtra"
  description = "Policy to manage additional ECS task permissions"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "LogGroupCreation"
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "*"
      },
      {
        Sid    = "ContainerChannel"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      },
      {
        Sid    = "EfsMount"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
        ]
        Resource = "*"
      },
      {
        Sid    = "KmsEncryptDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
        ]
        "Resource" = "*"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "ecs_task_extra" {
  name       = "AmazonECSTaskLogGroupCreation"
  roles      = [aws_iam_role.ecs_task_execution.name]
  policy_arn = aws_iam_policy.ecs_task_extra.arn
}
