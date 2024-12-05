output "cluster_security_groups" {
  value = aws_security_group.cluster
}

output "private_subnets" {
  value = aws_subnet.private
}

output "public_subnets" {
  value = aws_subnet.public
}

output "vpcs" {
  value = aws_vpc.all
}
