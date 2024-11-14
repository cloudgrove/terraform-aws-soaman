locals {
  network_dir        = "${var.config_dir}/networks/"
  network_file_paths = fileset(path.module, "${local.network_dir}/**/*.yml")
  network_configs = {
    for file_path in local.network_file_paths :
    try(yamldecode(file(file_path)).name, replace(file_path, "/${local.network_dir}|.yml/", "")) => yamldecode(file(file_path))
  }
  private_subnet_configs = merge(flatten([
    for vpc in local.network_configs : [
      for subnet_group, subnets in vpc.subnet_groups.private : {
        for index, subnet in subnets : "${vpc.name}.private-${subnet_group}-${index}" => {
          index             = index
          vpc_name          = vpc.name
          availability_zone = try(vpc.availability_zones[index], null)
          subnet_group      = subnet_group
          cidr_block        = "${vpc.cidr_prefix}.${subnet}"
        } if try(vpc.availability_zones[index], null) != null
      }
    ]
  ])...)
  public_subnet_configs = merge(flatten([
    for vpc in local.network_configs : [
      for subnet_group, subnets in vpc.subnet_groups.public : {
        for index, subnet in subnets : "${vpc.name}.public-${subnet_group}-${index}" => {
          index             = index
          vpc_name          = vpc.name
          availability_zone = try(vpc.availability_zones[index], null)
          subnet_group      = subnet_group
          cidr_block        = "${vpc.cidr_prefix}.${subnet}"
        } if try(vpc.availability_zones[index], null) != null
      }
    ]
  ])...)
}

#
# Internet Gateway
#

resource "aws_internet_gateway" "main" {
  tags = {
    Name = "main"
  }
}

#
# VPCs
#

resource "aws_vpc" "all" {
  for_each = local.network_configs

  cidr_block           = "${each.value.cidr_prefix}.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = each.key
  }
}

resource "aws_internet_gateway_attachment" "main" {
  for_each = aws_vpc.all

  internet_gateway_id = aws_internet_gateway.main.id
  vpc_id              = each.value.id
}

resource "aws_route" "public" {
  for_each = aws_vpc.all

  route_table_id         = each.value.default_route_table_id
  gateway_id             = aws_internet_gateway.main.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route53_zone" "internal" {
  for_each = aws_vpc.all

  name = "${each.key}"

  vpc {
    vpc_id = each.value.id
  }
}

#
# Public subnets
#

resource "aws_subnet" "public" {
  for_each = local.public_subnet_configs

  availability_zone = "${var.aws_region}${each.value.availability_zone}"
  cidr_block        = each.value.cidr_block
  vpc_id            = aws_vpc.all[each.value.vpc_name].id

  tags = {
    Name = each.key
  }
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnet_configs

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_vpc.all[each.value.vpc_name].default_route_table_id
}

#
# Private subnets
#

resource "aws_subnet" "private" {
  for_each = local.private_subnet_configs

  availability_zone = "${var.aws_region}${each.value.availability_zone}"
  cidr_block        = each.value.cidr_block
  vpc_id            = aws_vpc.all[each.value.vpc_name].id

  tags = {
    Name = each.key
  }
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = each.value.vpc_id

  tags = {
    Name = each.key
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.value.tags["Name"]].id
}

resource "aws_eip" "nat" {
  for_each = aws_subnet.private

  tags = {
    Name = each.key
  }
}

resource "aws_nat_gateway" "private" {
  for_each = aws_subnet.private

  subnet_id     = aws_subnet.public[replace(each.value.tags["Name"], "private", "public")].id
  allocation_id = aws_eip.nat[each.value.tags["Name"]].id

  tags = {
    Name = each.key
  }
}

resource "aws_route" "private" {
  for_each = aws_subnet.private

  route_table_id         = aws_route_table.private[each.value.tags["Name"]].id
  nat_gateway_id         = aws_nat_gateway.private[each.value.tags["Name"]].id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_db_subnet_group" "private" {
  for_each = aws_vpc.all

  name       = each.key
  subnet_ids = values(aws_subnet.private)[*].id
}

#
# Application load balancers
#

resource "aws_lb" "alb" {
  for_each = aws_vpc.all

  name               = each.key
  load_balancer_type = "application"
  internal           = true
  subnets            = [for subnet in aws_subnet.private : subnet.id if subnet.vpc_id == each.value.id]
  security_groups    = [aws_security_group.alb[each.key].id]
}

resource "aws_security_group" "alb" {
  for_each = aws_vpc.all

  name   = "ecs-${each.key}.alb"
  vpc_id = each.value.id

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = aws_vpc.all

  security_group_id = aws_security_group.alb[each.key].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_route53_record" "alb" {
  for_each = aws_vpc.all

  zone_id = aws_route53_zone.internal[each.key].id
  name    = "service"
  type    = "CNAME"
  ttl     = "30"
  records = [aws_lb.alb[each.key].dns_name]
}

resource "aws_lb" "nlb" {
  for_each = aws_vpc.all

  name               = each.key
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.public : subnet.id if subnet.vpc_id == each.value.id]
  security_groups    = [aws_security_group.nlb[each.key].id]
}

resource "aws_security_group" "nlb" {
  for_each = aws_vpc.all

  name        = "public-${each.key}.nlb"
  vpc_id      = each.value.id

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
