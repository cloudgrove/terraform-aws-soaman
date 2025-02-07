resource "aws_eip" "openvpn" {
  tags = {
    Name = "vpn"
  }
}

resource "aws_route53_record" "openvpn" {
  zone_id = var.zone_id
  name    = var.domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.openvpn.public_ip]
}

resource "aws_eip_association" "openvpn" {
  allocation_id = aws_eip.openvpn.id
  instance_id   = aws_instance.openvpn.id
}

resource "aws_instance" "openvpn" {
  ami           = "ami-080e1f13689e07408"
  instance_type = "t2.micro"
  subnet_id     = var.public_subnet_id
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [
    aws_security_group.openvpn.id,
  ]

  tags = {
    Name = "vpn.public"
  }

  user_data = templatefile("${path.module}/install.sh", {
    admin_username = var.admin_username
    admin_password = var.admin_password
    dev_username   = var.dev_username
    dev_password   = var.dev_password
    domain         = var.domain
    email          = var.email
    public_ip      = aws_eip.openvpn.public_ip
    subnet_cidr    = var.private_subnet_cidr
  })

  depends_on = [aws_route53_record.openvpn, aws_security_group.openvpn]
}

resource "aws_security_group" "openvpn" {
  name   = "ec2-openvpn"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "openvpn" {
  for_each = var.target_security_groups

  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 2000
  to_port                  = 6000
  security_group_id        = each.value.id
  source_security_group_id = aws_security_group.openvpn.id
}
