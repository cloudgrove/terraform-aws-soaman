locals {
  cluster_dir        = "${var.config_dir}/clusters/"
  cluster_file_paths = fileset(path.module, "${local.cluster_dir}/**/*.yml")
  cluster_configs = {
    for file_path in local.cluster_file_paths :
    try(yamldecode(file(file_path)).name, replace(file_path, "/${local.cluster_dir}|.yml/", "")) => yamldecode(file(file_path))
  }
  cluster_subnets = merge(flatten([
    for cluster, config in local.cluster_configs : {
      for key, subnet in aws_subnet.private :
      "${cluster}.${subnet.id}" => merge(subnet, { cluster_name = cluster }) if startswith(key, "${config.vpc}.")
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
