# S3 module

Provisions buckets from `<config_dir>/buckets/**/*.yml`, named
`<prefix>.<env>.<name>`. The `buckets` output maps configured names to AWS bucket
resources, including `arn`, `bucket`, and `bucket_regional_domain_name`.
Requires the `hashicorp/aws` provider version 6.37.0 or newer, including support
for explicit SSE-C blocking. A root provider constraint pinned to AWS v5 must be
updated before initialization. This provider requirement applies even when the
optional encryption configuration is omitted.

## Configuration

```hcl
module "s3" {
  source          = "cloudgrove/soaman/aws//src/modules/s3"
  # Pin a released module version containing these features before production use.
  config_dir      = "${path.module}/config"
  prefix          = "relaitech.rel8"
  env             = var.env
  protect_buckets = true
}
```

`protect_buckets` defaults to `false`. When enabled, all buckets in this module
invocation use a separate resource with literal `lifecycle.prevent_destroy = true`.
It rejects plans that destroy or replace those buckets while the resource remains
configured. It does not protect against deletion outside Terraform or removal of
the resource configuration. Terraform does not allow a variable or YAML expression
as a lifecycle value, so changing this setting on existing buckets requires the
state moves described below. Do not simply flip it and apply.

A Rel8 media bucket can retain its existing YAML and add explicit encryption and
TLS settings:

```yaml
name: media
object_ownership: BucketOwnerEnforced
versioning: true
require_tls: true
encryption:
  sse_algorithm: AES256
  bucket_key_enabled: false
  blocked_encryption_types:
    - SSE-C
cors:
  allowed_methods: [GET, HEAD, PUT, POST, DELETE]
  allowed_origins: ["*"]
  allowed_headers: ["*"]
  expose_headers:
    - x-amz-server-side-encryption
    - x-amz-request-id
    - x-amz-id-2
    - ETag
  max_age_seconds: 3000
```

The Rel8 artifacts bucket needs the same ownership, TLS, and encryption settings,
with `name: artifacts` and `versioning: false`, and no CORS block.

- Omit `versioning` to leave versioning unmanaged. `true` enables it; `false`
  configures `Suspended`.
- Omit `encryption` to leave encryption configuration unmanaged. When provided,
  `sse_algorithm` is required; `kms_master_key_id` is optional for KMS encryption.
  `bucket_key_enabled` defaults to `false`; `blocked_encryption_types` is optional
  and accepts the provider's `SSE-C` or `NONE` values.
- `require_tls` defaults to `false`. When enabled, a generated statement denies
  all S3 actions over insecure transport on both the bucket and its objects.
- `object_ownership` retains its `BucketOwnerPreferred` default. Set it to
  `BucketOwnerEnforced` to disable ACL resource creation.
- Existing `access`, `cors`, and `statements` configuration remains supported.
  Public access blocks retain their existing defaults. Public-read access inferred
  from `access.acl` and custom statements share one policy with TLS enforcement.
- Custom statements retain `sid`, `principal`, `effect`, `actions`, and `resource`;
  optional `condition` accepts an IAM condition object. Values in custom statements
  are used as provided; they are not interpolated with bucket attributes.

For example, a custom condition can be specified as:

```yaml
statements:
  - sid: AllowTaggedObjectRead
    principal: "*"
    effect: Allow
    actions: [s3:GetObject]
    resource: arn:aws:s3:::example.alpha.assets/*
    condition:
      StringEquals:
        s3:ExistingObjectTag/shared: "true"
```

## Migrating existing soaman consumers

Use the correct initialized backend and workspace for each environment, prevent
concurrent Terraform runs, and save a state backup before moving addresses.
Update provider constraints as needed and run `terraform init -upgrade`. Keep
existing bucket names and module names unchanged.

The public and custom bucket policy resources are now consolidated into
`aws_s3_bucket_policy.all`. For each existing public policy, move its address:

```sh
terraform state mv 'module.s3.aws_s3_bucket_policy.public["public-assets"]' 'module.s3.aws_s3_bucket_policy.all["public-assets"]'
```

For a custom policy, move `module.s3.aws_s3_bucket_policy.custom["<name>"]`
to `module.s3.aws_s3_bucket_policy.all["<name>"]` instead. If both old resources
exist for the same bucket, they already refer to the same remote policy: keep one
state entry, remove the duplicate with `terraform state rm`, then move the retained
entry. The new policy will compose the configured statements on apply. Do not try
to move both old entries to the same destination.

Unprotected bucket addresses remain `aws_s3_bucket.all`. If opting into
`protect_buckets = true`, move each bucket address before planning:

```sh
terraform state mv 'module.s3.aws_s3_bucket.all["archives"]' 'module.s3.aws_s3_bucket.protected["archives"]'
```

To opt out later, set `protect_buckets = false` and move the bucket state in the
reverse direction. Other resource addresses are unaffected by this choice.

If switching an existing bucket to `BucketOwnerEnforced`, the ACL resource leaves
the configuration; ensure any required ACL-based permissions are represented by
policies before doing so.

Run `terraform plan` and inspect the complete diff before applying. An existing
bucket must not be destroyed or replaced as part of this migration.

## Migrating Rel8

This module supports Rel8's S3 configuration; adopting it is a separate change in
`rel8-infrastructure` after a version containing these features is available.

Keep `module "s3"`, `config_dir`, `prefix = "relaitech.${var.project}"`, and `env`
unchanged. Replace the local source with a pinned release of this module and set
`protect_buckets = true`. Add the encryption and TLS fields shown above to both
bucket YAML files, retaining their existing versioning and CORS values. Rel8's
AWS provider constraint `~> 6.37.0` already satisfies this module's requirement.

After initializing against the existing backend, back up the state and move these
addresses for **each** environment where the resources are already managed:

```sh
terraform state mv 'module.s3.aws_s3_bucket.all["media"]' 'module.s3.aws_s3_bucket.protected["media"]'
terraform state mv 'module.s3.aws_s3_bucket.all["artifacts"]' 'module.s3.aws_s3_bucket.protected["artifacts"]'
terraform state mv 'module.s3.aws_s3_bucket_policy.tls_only["media"]' 'module.s3.aws_s3_bucket_policy.all["media"]'
terraform state mv 'module.s3.aws_s3_bucket_policy.tls_only["artifacts"]' 'module.s3.aws_s3_bucket_policy.all["artifacts"]'
```

Ownership, public access blocks, encryption, versioning, and CORS retain Rel8's
resource addresses. The new output is a superset of Rel8's existing output.
Existing Lambda S3 permissions and bucket-name environment variables do not need
to change. Buckets referenced only in function configuration and the Terraform
state backend bucket remain outside this migration unless explicitly provisioned
through this module.

Review a plan for every environment: expect no bucket replacements and no changes
to encryption, versioning, public access blocking, or TLS enforcement. State moves
must be omitted for resources that have not yet been created.
