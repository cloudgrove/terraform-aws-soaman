output "private_subnets" {
  value = aws_subnet.private
}

output "public_subnets" {
  value = aws_subnet.public
}

output "security_groups" {
  value = merge(aws_security_group.cluster, aws_security_group.microservice_database)
}

output "vpcs" {
  value = aws_vpc.all
}
