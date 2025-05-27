# About this repo
[![CircleCI](https://dl.circleci.com/status-badge/img/gh/cloudgrove/terraform-aws-soaman/tree/develop.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/cloudgrove/terraform-aws-soaman/tree/develop)

`aws-soaman` hosts the Terraform modules necessary to provision the AWS cloud resources for a complete service-oriented architecture (SOA), along with relevant setups (such as VPN, email setup, and web app hosting).

When invoked, `aws-soaman` traverses YAML config files to understand the design parameters (e.g. the size of an RDS database, the replica count of an ECS service, the CIDR of a subnet, etc) before provisioning starts. These YAML files should reside in the Terraform project where `aws-soaman` is installed as a plugin, and not within this repo or its fork, unless they are example files.


# Features

The design of `aws-soaman` enjoys the benefits of multiple features:

1. Private subnets using VPC, to protect resources that should not be accessed directly from the public internet, such as databases.

1. Serverless Docker container management using ECS Fargate, which enables the graceful deployment of microservices without having to maintain a cluster of machines.

1. Cost-effective load balancing using ALB, as all traffic to microservices is routed through one load balancer, instead of having one load balancer for each microservice.

1. Assembled microservice-specific resources in one place--a single YAML file, to ease tracking microservice-related dependencies.

1. Restricted access to microservices, whereby no microservice is accessible from the public internet except for the entrypoint/gateway service. (Note: each ECS cluster can have at most one entrypoint/gateway service.)

1. Restricted access to microservice resources, whereby a microservice resource (e.g. database) is accessible by that microservice only and no other.

1. Inherited microservice default config, to ease managing environment-specific configs.

1. CDN-enabled public traffic via CloudFront, to increase performance and security.

1. Auto-generated DNS routes (for load balancers, RDS instances, CloudFront Distributions, VPN instances) to standardize and ease access to resources.

1. Shared file systems using EFS, to enable scaling up microservices that depend on a file system, such as Jenkins.

1. VPN access using OpenVPN, to enable access to resources on the private network.

1. KMS-based decryption, to enable the use of KMS-encrypted values in config files and protect sensitive data when leveraging VCS.

1. Managed users and their access via YAML, to ease user management and not have to deal with Terraform directly.

1. Email-enabled service using SES, to enable microservices to send emails with proper DNS setup.

1. S3-hosted web apps, to allow developers to deploy web apps for their SOA-based backends.


# Managing environments

`aws-soaman` is built with environments in mind. That is why it supports the `env` attribute. By leveraging this attribute, one does not need to maintain the code for multiple environments in the same codebase. Instead, one can use branch-oriented workflows (such as Gitflow) to derive the environment name and inject it into the `aws-soaman`-invoking code in order to create environment-related resources, and have the setup mirrored across all environments. Here is an example:

| Branch    | Env    | Example Resources |
| --------- | ------ | ----------------- |
| `develop` | `beta` | `https://vpn.beta.cloudgrove.io`, `s3://cloudgrove.beta.public-assets` |
| `master`  | `prod` | `https://vpn.prod.cloudgrove.io`, `s3://cloudgrove.prod.public-assets` |

As for environment-specific capacity (e.g. memory, compute power, replica count, etc), that can be specified in microservice-related YAML config files, where the delta between environments can be captured in a clear fashion.


# Modules

`aws-soaman` has 7 modules:

1. `iam`, for managing IAM users.

1. `s3`, for provisioning and configuring S3 buckets.

1. `dns`, for setting up the SSL/TLS certificate and the environment-specific subdomain.

1. `appset`, for publishing web apps in S3. This modules depends on both `dns` as well as a public S3 bucket created via the `s3` module.

1. `ses`, for configuring SES and setting up DNS records for it. This modules depends on `dns`.

1. `soa`, for provisioning SOA-related resources. This modules depends on `dns`.

1. `openvpn`, for setting up OpenVPN on an EC2 machine. This modules depends on `dns` and `soa`.


# Quick start

There are a couple of alternatives (with sufficient coverage for YAML configs) for quick starts:

1. Download this repo and navigate to `src/examples/complete/`. (This is meant to provide a quick way to get a feel for how things work.)

1. Fork the [infrastructure-manager](https://github.com/cloudgrove/infrastructure-manager) repo and navigate to `src/`. (The codebase can be expanded with more YAML and Terraform/HCL code to add more resources.)

Then, run `terraform init`.


# Running Terraform

Running Terraform here means `terraform apply`.

## Before the run

1. Create the `terraform` IAM user in AWS, assign it the `AdministratorAccess` AWS managed policy, generate an access key pair for it, and load these AWS keys into the relevant environment variables, i.e.:
    * `AWS_ACCESS_KEY_ID`
    * `AWS_SECRET_ACCESS_KEY`

1. If you plan on leveraging KMS to protect your sensitive values, ensure there is a KMS key in each environment account (with the alias name `default` for example) and grant the `terraform` IAM user access to it. For redundancy and disaster prevention, you can manually create a multi-region KMS key in one of the regions (`us-east-1` for instance) and use the `mrk` module to replicate this key in your target region(s). Here is an example invocation (which you can insert in the root `main.tf`, along with the other module invocations) that replicates the `default` key:
```
module "mrk" {
  source      = "cloudgrove/soaman/aws//src/modules/mrk"
  alias       = "alias/default"
  origin      = "us-east-1"
  destination = var.aws_region
}
```

1. Replace the existing KMS-encrypted value for the [Postgres password](https://github.com/cloudgrove/terraform-aws-soaman/blob/develop/src/examples/complete/config/microservices/gateway-service.yml#L24) with your own, if its associated config block is kept.


## During the run

In the domain name registrar of choice (e.g. GoDaddy):

1. Add a new `CNAME` record in order to validate the Terraform-generated ACM certificate. The relevant values can be found in the ACM section of the AWS console under the target certificate, with the column names `CNAME name` and `CNAME value`, or can be retrieved using the following command (after replacing `<DOMAIN>` and `<ENV>`):
```
aws acm describe-certificate \
  --certificate-arn $(aws acm list-certificates --query "CertificateSummaryList[?DomainName=='*.<ENV>.<DOMAIN>'].CertificateArn" --output text) \
  --query "Certificate.DomainValidationOptions[?ValidationStatus=='PENDING_VALIDATION'].{CNAME_Name: ResourceRecord.Name, CNAME_Value: ResourceRecord.Value}" \
  --output text
```

1. Add a new `NS` record to link the Terraform-generated subdomain Route53 record (e.g. `alpha.cloudgrove.io`) to your target domain (e.g. `cloudgrove.io`). The `NS` record would have a value similar to `ns-203.awsdns-25.com`, a value that can be found in the AWS console under the Route53 public hosted zone that Terraform generates, or can be retrieved using the following command (after replacing `<DOMAIN>`):
```
aws route53 list-resource-record-sets \
  --hosted-zone-id $(aws route53 list-hosted-zones-by-name --dns-name <DOMAIN> --query "HostedZones[0].Id" --output text) \
  --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[*].Value" \
  --output text
```

Note: these two records are blockers to the creation of the VPN box and CloudFront distributions.


## After the run

1. You can access the VPN box via SSH at the assigned IP address; e.g. `ssh -A ubuntu@44.33.22.11` (Note: make sure the `devops` SSH key is loaded into the SSH agent).

1. You can access the entrypoint/gateway service (running in ECS) from:

    1. the public internet via:

        * the network load balancer (NLB) DNS name; e.g. `https://master-02031f326d87c1c6.elb.us-east-1.amazonaws.com` (Note: it is important to specify `https` in the URL)

        * the environment-specific API subdomain; e.g. `https://api.alpha.cloudgrove.io/`

        * SSH by executing the following command:

          ```aws ecs execute-command --region $AWS_DEFAULT_REGION --cluster $CLUSTER --container $CONTAINER --task $TASK --command sh --interactive```

          (Note: make sure that the Shell variables are populated)

        * Note: microservice admin paths, i.e. `admin/*`, are blocked from the public internet

    1. the private network (while connected to VPN) by:

        * navigating to the URL `http://<cluster>.<vpc>`, e.g. `http://main.master`, while connected to the target VPN

        * executing the command `curl http://<cluster>.<vpc>`, e.g. `http://main.master`, from the VPN box

        * Note: microservice admin paths, i.e. `admin/*`, are allowed within the private network


# VPN setup

By default, the OpenVPN setup comes with one admin user (`openvpn`) and one regular user (`dev`). Their associated usernames can be customized using the `admin_username` and `dev_username` attributes. Furthermore, the `admin_password` and `dev_password` attributes need to be set, preferably through external environment variables, so that login to the OpenVPN portal works; and from there, other user records can be managed. The portal can be accessed at the environment-specific target subdomain (e.g. `https://vpn.alpha.cloudgrove.io` if the `alpha` environment is targeted) after both the provisioning of the EC2 instance and the complete installation of OpenVPN are done. Trying to access the OpenVPN portal prematurely can break the VPN server. If that happens however, simply terminate the VPN EC2 instance and rerun `terraform apply` to reprovision the VPN setup.


# YAML configs

There are 6 categories of YAML config files that `aws-soaman` can process:

| Config       | Module   | Provisioning |
| ------------ | -------- | ------------ |
| Network      | `soa`    | VPCs and their network resources (e.g. subnets, nat gateways, EIPs, etc) |
| Cluster      | `soa`    | ECS clusters and their dedicated resources (e.g. ALB, EFS volume, etc) |
| Microservice | `soa`    | Microservice configs and related resources (e.g. ECS task defs, IAM policies, databases, etc) |
| User         | `iam`    | IAM users and their policies |
| Bucket       | `s3`     | S3 buckets and their policies |
| App          | `appset` | App-related resources (e.g. DNS records, CloudFront distributions, etc) |

Note that across all these categories, each resource group gets its own dedicated YAML config file. In other words, each VPC has its own dedicated file, and so does an ECS cluster, and a microservice... and a bucket... and an app... and an IAM user.


## Network config

The full list of configuration parameters for the creation of a VPC and its networks is as follows:
```
name: ... # String identifying the VPC
cidr_prefix: ... # First 2 octets of a CIDR; example: 10.0
availability_zones: # List of availability zones
  - a
  - b
  - ...
subnet_groups:
  private:
    <subnet-group-1>: # String identifying the subnet group
      - _._/_ # CIDR suffix; i.e. second 2 octets, plus the subnet mask
      - ...
    <subnet-group-2>:
      - _._/_
      - ...
    ...
  public:
    <subnet-group-1>:
      - _._/_
      - ...
    <subnet-group-2>:
      - _._/_
      - ...
    ...
```

See an example [here](https://github.com/cloudgrove/terraform-aws-soaman/blob/develop/src/examples/complete/config/networks/master.yml), which provisions a VPC called `master`, across availability zones `a`, `b`, and `c`, with 3 private subnets (`10.0.16.0/20`, `10.0.32.0/20`, and `10.0.48.0/20`), and 3 public subnets (`10.0.0.0/24`, `10.0.1.0/24`, `10.0.2.0/24`).


## Cluster config

The full list of configuration parameters for creating an ECS cluster and its links is as follows:

```
name: ... # String identifying the cluster
vpc: ... # Name of the target VPC
subdomain: ... # Prefix of the subdomain for accessing the entrypoint service in the cluster
entrypoint: ... # Name of the entrypoint service
container_insights: ... # For AWS insight metrics; defaults to `disabled`
```

See an example [here](https://github.com/cloudgrove/terraform-aws-soaman/blob/develop/src/examples/complete/config/clusters/main.yml), which provisions an ECS cluster called `main`, on the `master` VPC, with container insights. The entrypoint service for this cluster is `gateway-service`, and can be accessed from the public internet at `https://api.alpha.cloudgrove.io`. If one is connected to a VPN on the `master` VPC, microservices running on this ECS cluster can be accessed via the route `http://main.master:<port>`; for example, `http://main.master:80` accesses `gateway-service` (which runs on port `80`).

Note that if the `entrypoint` is not specified, the link between the public internet and the cluster is omitted, and the cluster resources become 100% private (which may be ideal for tasks that handle in-house data). Such a link comprises the private ALB, the public NLB, the desired subdomain-related CloudFront distribution, and the DNS record for such a subdomain.


## Microservice config

A microservice YAML file contains a macro-config, as follows:
```
name: ... # String identifying the microservice
port: ... # Number identifying the port
vpc: ... # Name of the target VPC
subnet_group: ... # Name of the target subnet group
cluster: ... # Name of the target cluster
config:
  default:
    desired_count: ...
    ...
  <env1>:
    desired_count: ...
    ...
  <env2>:
    desired_count: ...
    ...
  ...
```

... And 3 environment-specific micro-configs under the YAML key `config`, which are:
  * `task_definition`, to configure the Docker container and its memory/compute power
  * `variables`, to inject the microservice environment variables
  * `resources`, to specify and configure microservice resources (such as SQS queues, RDS databases, EFS/S3 access)

The currently supported microservice resources are:
  * EFS locations (a simple list of paths)
  * S3 (a simple list of paths under `read_write` or `read_only`; see the example below)
  * RDS instances (whose YAML is specified below)
  * SQS queues (whose YAML is specified below)

Note that a microservice can be associated with multiple resources of the same kind (such as 2 RDS instances, 3 SQS queues, etc).

For a microservice RDS instance, the full list of supported configuration parameters is as follows:
```
rds:
  my-db:
    engine: ...
    engine_version: ...
    instance_class: ... # defaults to `t4g.micro`
    allocated_storage: ... # defaults to 10
    db_name: ... # defaults to `main`
    username: ... # defaults to `root`
    password: ... # must be KMS-encrypted, and optionally prefixed with `kms_`
    multi_az: ... # defaults to `true`
    parameter_group_name: ... # defaults to `null`
    storage_encrypted: ... # defaults to `true`
    max_allocated_storage: ... # defaults to 1000
    backup_retention_period: ... # defaults to 30
    performance_insights_enabled: ... # defaults to `true`
    skip_final_snapshot: ... # defaults to `true`
    apply_immediately: ... # defaults to `true`
```

For a microservice queue, the full list of supported configuration parameters is as follows:
```
sqs:
  main-queue:
    fifo_queue: ... # defaults to `false`
    delay_seconds: ... # defaults to 0
    max_message_size: ... # defaults to 0
    message_retention_seconds: ... # defaults to 262144
    receive_wait_time_seconds: ... # defaults to 1209600
    max_receive_count: ... # defaults to 5
```

Note that for microservice environment variables and S3 paths (in the YAML config file), it is possible to avoid hardcoding the environment name (e.g. `alpha`, `prod`, etc) by typing `${env}`. Here is an example combining multiple common cases:
```
variables:
  AWS_S3_BUCKET_FOR_DOCUMENTS: cloudgrove.${env}.archives
  AWS_S3_BUCKET_FOR_PUBLIC_CONTENT: &pc_bucket cloudgrove.${env}.public-assets
  POSTGRES_HOST: content-service.${env}.cloudgrove.io
resources:
  s3:
    read_write:
      - cloudgrove.${env}.archives/gateway-service
      - cloudgrove.${env}.archives/shared
    read_only:
      - *pc_bucket
```

By not hardcoding the environment name, the `default` config is inherited by the other environments that are specified in the microservice config file.

See a comprehensive example [here](https://github.com/cloudgrove/terraform-aws-soaman/blob/develop/src/examples/complete/config/microservices/gateway-service.yml), which provisions a microservice called `gateway-service` running on port `80` on the `main` ECS cluster, within the `main` subnet group of the `master` VPC. It will run with a replica count of `2` in the `beta` environment, `0` in `prod`, and `1` in any other environment (such as `alpha`).


## User config

The structure of the YAML config for the creation of an IAM user and its associated access policies is similar to the JSON-based one used by AWS IAM, and is as follows:
```
name: ...
statements:
  - sid: ...
    effect: ...
    actions: ...
    resources: ...
  - ...
```

See an example [here](https://github.com/cloudgrove/terraform-aws-soaman/blob/develop/src/examples/complete/config/users/circleci.yml), which provisions an IAM user called `circleci` that can deploy Docker images to ECR, update ECS services, clear CloudFront caches, and manage files in any S3 bucket that is suffixed with `.public-assets`.


## Bucket config

`aws-soaman` lets one create and configure any number of S3 buckets. However, to be lean, and avoid scenarios where each microservice ends up with multiple dedicated S3 buckets, one is encouraged to specify buckets by their use case (i.e. "configs", "public assets", etc) as it is the use case that dictates the access policy. Miroservices can then have limited or full access to sublocations of the created S3 buckets.

After specifying the target environment and the desired S3 prefix (which can refer to an organization, project, relation, etc), the full S3 bucket name is then generated using the following pattern:
```
<prefix>.<environment>.<use-case>
```

Here are some examples:
```
cloudgrove.prod.configs
cloudgrove.sandbox-2.archives
cloudgrove-client-1.beta.public-assets
```

The full list of configuration parameters for a bucket creation is as follows:
```
name: ... # example: public-assets
object_ownership: ... # defaults to `BucketOwnerPreferred`
access:
  acl: ... # defaults to `private`
  block_public_acls: ... # defaults to `true`
  block_public_policy: ... # defaults to `true`
  ignore_public_acls: ... # defaults to `true`
  restrict_public_buckets: ... # defaults to `true`
cors:
  allowed_methods:
    - ...
  allowed_origins:
    - ...
  allowed_headers:
    - ...
  expose_headers:
    - ...
  max_age_seconds: ...
statements: ... # defaults to `null`
  - sid: ...
    principal: ...
    effect: ...
    actions: ...
    resource: ...
  - ...
```

See an example [here](https://github.com/cloudgrove/terraform-aws-soaman/blob/develop/src/examples/complete/config/buckets/public-assets.yml), which provisions a read-only pubilc S3 bucket called `cloudgrove.alpha.public-assets`.


## App config

The full list of configuration parameters for a hosted web app is as follows:
```
name: ... # String identifying the app; example: `landing-site`
subdomain: ... # defaults to the empty string
path: ... # S3 location, excluding the bucket name; example: `/apps/landing-site/current`
enabled: ... # Desired status of the CloudFront distribution; defaults to `true`
```

See an example [here](https://github.com/cloudgrove/terraform-aws-soaman/blob/develop/src/examples/complete/config/apps/main.yml), which provisions a web app hosted at https://app.alpha.cloudgrove.io.

Note that all apps within the same app set reside in the same bucket, which is specified in the `module` invocation. If a new app is to be hosted in a different S3 bucket, then a new `module` block (invoking `appset`) is required.


# Bonus

To allow a user to access Docker containers running in ECS via SSH (i.e. `aws ecs execute-command ... --command sh --interactive`), they should be assigned the following IAM policy:

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
