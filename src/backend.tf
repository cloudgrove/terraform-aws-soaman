terraform {
  cloud {
    organization = "cloudgrove"

    # Note:
    # - There are multiple workspaces tagged as "infrastructure-manager", each one manages a different environment.
    # - The command `terraform init` lets one select the target Terraform workspace locally.
    # - In the case of CI/CD, the TF_WORKSPACE environment variable is used to specify the target workspace.
    workspaces {
      tags = ["infrastructure-manager"]
    }
  }
}
