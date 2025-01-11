terraform {
  cloud {
    organization = "cloudgrove"

    workspaces {
      tags = ["soaman"]
    }
  }
}
