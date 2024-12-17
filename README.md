# About this repo

This repo hosts the Terraform functionality and its associated YAML configs to provision an SOA-based system featuring:

1. Private subnets using VPC

1. Docker container management using ECS

1. Shared file systems using EFS

1. VPN access using OpenVPN


# Before you run Terraform

Log into your target domain name registrar and be ready to:

1. Create the `terraform` IAM user, assign it the `AdministratorAccess` AWS managed policy, generate an access key pair for it, and load these keys into the following environment variables:
    * `TF_VAR_aws_access_key`
    * `TF_VAR_aws_secret_key`


# While Terraform is running

In the domain name registry of choice (e.g. GoDaddy):

1. Add a `CNAME` record in order to validate the Terraform-generated ACM certificate.

1. Add a `NS` record to link the Terraform-generated subdomain Route53 record (e.g. `alpha.cloudgrove.io`) to your target domain (e.g. `cloudgrove.io`).

Note: these two records are blockers to the creation of the VPN box and CloudFront distributions.


# After you run Terraform

1. You can access the VPN box via SSH at the assigned IP address; e.g. `ssh -A ubuntu@44.219.78.190` (Note: make sure the `devops` SSH key is loaded into the SSH agent)

1. You can access the gateway service (running in ECS) from:

    1. the public internet via:

        * the network loadbalancer (NLB) DNS name; e.g. `https://master-02031f326d87c1c6.elb.us-east-1.amazonaws.com` (Note: it is important to specify `https` in the URL)

        * the environment-specific API subdomain; e.g. `https://api.alpha.cloudgrove.io/`

        * SSH by executing the following command:

          ```aws ecs execute-command --region $AWS_DEFAULT_REGION --cluster $CLUSTER --container $CONTAINER --task $TASK --command sh --interactive```

          (Note: make sure that the Shell variables are populated)

        * Note: admin paths, i.e. `admin/*`, are blocked from the public internet

    1. the private network (while connected to VPN) by:

        * navigating to the URL `http://service.master`

        * executing the command `curl http://service.master` from the VPN box

        * Note: admin paths, i.e. `admin/*`, are allowed within the private network


# VPN setup

By default, the OpenVPN setup comes with one admin user (`openvpn`) and one regular user (`dev`). Users can me managed via the OpenVPN portal at the environment-specific target subdomain (e.g. `https://vpn.alpha.cloudgrove.io`).


# Access reuirements

1. To allow a user to access Docker containers running in ECS via SSH (i.e. `aws ecs execute-command ... --command sh --interactive`), they should be assigned the following IAM policy:
    ```
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ecs:ExecuteCommand",
                    "ecs:DescribeTasks"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": "ssm:StartSession",
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "ssmmessages:CreateControlChannel",
                    "ssmmessages:CreateDataChannel",
                    "ssmmessages:OpenControlChannel",
                    "ssmmessages:OpenDataChannel"
                ],
                "Resource": "*"
            }
        ]
    }
    ```
