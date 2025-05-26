provider "aws" {
  alias  = "origin"
  region = var.origin
}

provider "aws" {
  alias  = "destination"
  region = var.destination
}

data "aws_kms_key" "main" {
  provider = aws.origin
  key_id   = var.alias
}

resource "aws_kms_replica_key" "replica" {
  provider        = aws.destination
  primary_key_arn = data.aws_kms_key.main.arn
}

resource "aws_kms_alias" "replica_alias" {
  provider      = aws.destination
  name          = var.alias
  target_key_id = aws_kms_replica_key.replica.key_id
}
