variable "config_dir" {
  description = "The directory that contains configuration files"
  type        = string
}

variable "env" {
  description = "The target environment"
  type        = string
}

variable "prefix" {
  description = "The string prepended to bucket names"
  type        = string
}
