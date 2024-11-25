locals {
  devops_email = "devops@${var.domain_name}"
  subdomain    = "${var.env}.${var.domain_name}"
}
