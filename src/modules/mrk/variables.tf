variable "destination" {
  description = "The AWS region where the KMS key is to be replicated"
  type        = string
}

variable "alias" {
  description = "The alias of the KMS key to be replicated"
  type        = string
  default     = "alias/default"
}

variable "origin" {
  description = "The AWS region where the KMS key is originally located"
  type        = string
}
