#
# SSH keys
#

resource "aws_key_pair" "devops" {
  key_name   = "devops-key"
  public_key = var.devops_ssh_key
}

#
# EC2 instances
#

module "vpn" {
  source              = "./modules/openvpn"
  vpc_id              = aws_vpc.all["master"].id
  public_subnet_id    = element(values(aws_subnet.public).*.id, 1)
  zone_id             = aws_route53_zone.main.zone_id
  domain              = "${var.vpn_subdomain_prefix}.${aws_route53_zone.main.name}"
  email               = local.devops_email
  admin_password      = var.vpn_admin_password
  dev_password        = var.vpn_dev_password
  ssh_key_name        = aws_key_pair.devops.key_name
  efs_security_groups = aws_security_group.cluster
}
