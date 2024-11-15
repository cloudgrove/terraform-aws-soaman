locals {
  cluster_dir        = "${var.config_dir}/clusters/"
  cluster_file_paths = fileset(path.module, "${local.cluster_dir}/**/*.yml")
  cluster_configs = {
    for file_path in local.cluster_file_paths :
    try(yamldecode(file(file_path)).name, replace(file_path, "/${local.cluster_dir}|.yml/", "")) => yamldecode(file(file_path))
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
# EFS
#

resource "aws_efs_file_system" "cluster" {
  for_each = local.cluster_configs

  creation_token = each.key
  encrypted      = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "ecs-${each.value.vpc}.${each.key}"
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

  name   = "ecs-${each.value.vpc}.${each.key}.efs"
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
  name               = "AmazonECSTaskExecution"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
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
  description = "Policy to create log groups"
  policy      = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid      = "LogGroupCreation"
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "*"
      },
      {
        Sid      = "ContainerChannel"
        Effect   = "Allow"
        Action   = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Sid    = "EfsMount",
        Effect = "Allow",
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeMountTargets",
        ],
        Resource = "*",
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "ecs_task_extra" {
  name       = "AmazonECSTaskLogGroupCreation"
  roles      = [aws_iam_role.ecs_task_execution.name]
  policy_arn = aws_iam_policy.ecs_task_extra.arn
}
