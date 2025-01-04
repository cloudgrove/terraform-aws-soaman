locals {
  microservice_dir        = "${var.config_dir}/microservices/"
  microservice_file_paths = fileset("", "${local.microservice_dir}/**/*.yml")
  microservice_configs = {
    for file_path in local.microservice_file_paths :
    try(yamldecode(file(file_path)).name, replace(file_path, "/${local.microservice_dir}|.yml/", "")) => yamldecode(file(file_path))
  }
  microservice_queues = merge(flatten([
    for microservice, microservice_config in local.microservice_configs : {
      for queue, queue_config in merge(try(microservice_config.config.default.resources.sqs, {}), try(microservice_config.config[var.env].resources.sqs, {})) :
      "${microservice}-${queue}" => queue_config
    }
  ])...)
}

#
# ECS services
#

resource "aws_ecs_service" "all" {
  for_each = local.microservice_configs

  name                = each.key
  cluster             = aws_ecs_cluster.all[each.value.cluster].arn
  task_definition     = aws_ecs_task_definition.all[each.key].arn
  desired_count       = try(each.value.config[var.env].desired_count, each.value.config.default.desired_count)
  launch_type         = "FARGATE"
  scheduling_strategy = "REPLICA"
  platform_version    = "LATEST"

  enable_execute_command             = true
  deployment_minimum_healthy_percent = 50

  network_configuration {
    subnets = [
      for subnet in [
        for key in keys({
          for k, v in local.private_subnet_configs :
          k => v if v.vpc_name == each.value.vpc && v.subnet_group == each.value.subnet_group
        }) : aws_subnet.private[key]
      ] : subnet.id
    ]
    security_groups = [aws_security_group.alb[each.value.vpc].id, aws_security_group.microservice[each.key].id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.microservice[each.key].arn
    container_name   = each.key
    container_port   = each.value.port
  }

  # Enable this when experimenting/troubleshooting so that task defs don't get overridden
  # lifecycle {
  #   ignore_changes = [task_definition, desired_count]
  # }
}

resource "aws_ecs_task_definition" "all" {
  for_each = local.microservice_configs

  family                   = each.key
  cpu                      = try(each.value.config[var.env].task_definition.cpu, each.value.config.default.task_definition.cpu)
  memory                   = try(each.value.config[var.env].task_definition.memory, each.value.config.default.task_definition.memory)
  task_role_arn            = aws_iam_role.ecs_task_execution.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  dynamic "volume" {
    for_each = can(aws_efs_access_point.microservice_efs[each.key]) ? [1] : []

    content {
      name = "primary"

      efs_volume_configuration {
        file_system_id      = aws_efs_file_system.cluster[each.value.cluster].id
        root_directory      = "/"
        transit_encryption  = "ENABLED"

        authorization_config {
          access_point_id = aws_efs_access_point.microservice_efs[each.key].id
          iam             = "ENABLED"
        }
      }
    }
  }

  container_definitions = jsonencode([merge(
    {
      logConfiguration = {
        logDriver     = "awslogs"
        secretOptions = []
        options       = {
          awslogs-create-group = "true"
          awslogs-group = each.key
          awslogs-region = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    },
    each.value.config.default.task_definition,
    try(each.value.config[var.env].task_definition, {}),
    {
      environment = [
        for k, v in merge(each.value.config.default.variables, try(each.value.config[var.env].variables, {})) : {
          name  = k,
          value = tostring(v)
        }
      ],
      mountPoints = contains(keys(each.value.config.default), "efs") ? [{
        sourceVolume  = "primary"
        containerPath = each.value.config.default.efs.container_path
        readOnly      = false
      }] : [],
    }
  )])
}

resource "aws_security_group" "microservice" {
  for_each = local.microservice_configs

  name        = "ecs-${each.value.vpc}.${each.key}"
  vpc_id      = aws_vpc.all[each.value.vpc].id
}

resource "aws_ecr_repository" "microservice" {
  for_each = local.microservice_configs

  name = each.key
}

#
# Load-balancing resources
#

resource "aws_lb_target_group" "microservice" {
  for_each = local.microservice_configs

  name        = each.key
  vpc_id      = aws_vpc.all[each.value.vpc].id
  target_type = "ip"
  protocol    = "HTTP"
  port        = each.value.port

  health_check {
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }
}

resource "aws_lb_listener" "microservice" {
  for_each = local.microservice_configs

  load_balancer_arn = aws_lb.alb[each.value.vpc].arn
  protocol          = "HTTP"
  port              = each.value.port

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.microservice[each.key].arn
  }
}

resource "aws_vpc_security_group_ingress_rule" "microservice" {
  for_each = local.microservice_configs

  security_group_id = aws_security_group.alb[each.value.vpc].id
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = "0.0.0.0/0"
}

#
# EFS
#

resource "aws_efs_access_point" "microservice_efs" {
  for_each = {
    for microservice, config in local.microservice_configs :
    microservice => config if contains(keys(config.config.default), "efs")
  }

  file_system_id = aws_efs_file_system.cluster[each.value.cluster].id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/ecs/${each.key}"

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0755"
    }
  }

  tags = {
    Name = each.key
  }
}

#
# SQS
#

resource "aws_sqs_queue" "microservice" {
  for_each = local.microservice_queues

  name                      = try(each.value.fifo_queue, false) ? "${each.key}.fifo" : each.key
  fifo_queue                = try(each.value.fifo_queue, false)
  delay_seconds             = try(each.value.delay_seconds, 0)
  max_message_size          = try(each.value.max_message_size, 262144)
  message_retention_seconds = try(each.value.message_retention_seconds, 1209600)
  receive_wait_time_seconds = try(each.value.receive_wait_time_seconds, 0)

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.microservice_dlq[each.key].arn
    maxReceiveCount     = try(each.value.max_receive_count, 5)
  })
}

resource "aws_sqs_queue" "microservice_dlq" {
  for_each = local.microservice_queues

  name                      = try(each.value.fifo_queue, false) ? "${each.key}-dlq.fifo" : "${each.key}-dlq"
  fifo_queue                = try(each.value.fifo_queue, false)
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 1209600
  receive_wait_time_seconds = 0
}

#
# IAM users & policies
#

resource "aws_iam_user" "microservice" {
  for_each = local.microservice_configs

  name = each.key
  path = "/ecs/"
}

data "aws_iam_policy_document" "microservice" {
  for_each = local.microservice_configs

  statement {
    actions   = ["iam:NoAction"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = {
      for k, v in try(each.value.config[var.env], each.value.config.default) :
      k => v if k == "s3" && try(v.read_only, null) != null
    }

    content {
      sid    = "S3ReadOnly"
      effect = "Allow"
      actions = [
				"s3:ListBucket",
        "s3:GetObject",
      ]
      resources = flatten([
      for path in statement.value.read_only : [
        "arn:aws:s3:::${path}",
        "arn:aws:s3:::${path}/*",
      ]
    ])
    }
  }

  dynamic "statement" {
    for_each = {
      for k, v in try(each.value.config[var.env], each.value.config.default) :
      k => v if k == "s3" && try(v.read_write, null) != null
    }

    content {
      sid    = "S3ReadWrite"
      effect = "Allow"
      actions = [
				"s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
      ]
      resources = flatten([
      for path in statement.value.read_write : [
        "arn:aws:s3:::${path}",
        "arn:aws:s3:::${path}/*",
      ]
    ])
    }
  }
}

resource "aws_iam_user_policy" "microservice" {
  for_each = local.microservice_configs

  name   = each.key
  user   = aws_iam_user.microservice[each.key].name
  policy = data.aws_iam_policy_document.microservice[each.key].json
}
