# aws-bootstrap-harness

The Terraform I reach for to stand up a web application on AWS quickly — and
safely. A one-time account bootstrap, then three modules that every site
reuses:

| | What it gives you |
|---|---|
| [`bootstrap/`](bootstrap) | Run once per AWS account: the GitHub Actions OIDC provider and a shared, versioned, TLS-only state bucket with S3-native locking. |
| [`modules/github-oidc-roles`](modules/github-oidc-roles) | Per repository: a read-only **plan** role for pull requests and an **apply** role for the deploy branch only. No long-lived AWS keys, anywhere. |
| [`modules/static-site`](modules/static-site) | Private S3 + CloudFront with Origin Access Control, an ACM certificate, Route 53 records, strict security headers (HSTS, CSP, frame-deny, nosniff), optional geo-restriction, `www` → apex and `/dir/` → `index.html` handling. |
| [`modules/cost-breaker`](modules/cost-breaker) | A hard stop on the bill: request/byte-rate alarms and a budget that, when breached, **disable the CloudFront distribution** and email you why. |
| [`examples/static-site`](examples/static-site) | All of the above wired together, with plan-on-PR and deploy-on-merge workflows. |

## The shape of a project

```
              pull request ──► plan workflow ──(OIDC, read-only role)──► terraform plan → PR comment
 GitHub repo
              merge to main ──► deploy workflow ──(OIDC, apply role)──► terraform apply
                                                                       ► aws s3 sync site/
                                                                       ► CloudFront invalidation

 viewer ──TLS──► CloudFront ──SigV4 (OAC)──► private S3 bucket
                     │
                     └─ metrics ──► alarms ─┐
                        budget 100% ────────┴─► SNS ─► breaker Lambda ─► distribution disabled
```

## First-time setup

1. **Bootstrap the account** (once, admin credentials, local state):

   ```sh
   cd bootstrap
   cp terraform.tfvars.example terraform.tfvars   # pick a globally unique bucket name
   terraform init && terraform apply
   ```

2. **Start a project from the example.** Copy `examples/static-site` into a new
   repository (keep the module `source` paths, or point them at a tagged
   release of this repo). Put the site in `site/`.

3. **First apply, locally.** The CI roles are created by this apply, so it
   can't run in CI yet:

   ```sh
   cp terraform.tfvars.example terraform.tfvars   # domain, zone, repo, bootstrap outputs
   terraform init -backend-config=bucket=<state bucket> -backend-config=region=<region>
   terraform apply
   ```

   Click the SNS confirmation email.

4. **Hand over to CI.** Set the repository variables listed at the top of
   [`plan.yml`](examples/static-site/.github/workflows/plan.yml), including
   `PLAN_ROLE_ARN` and `APPLY_ROLE_ARN` from the apply's outputs. From then on:
   a pull request posts its plan; a merge applies, syncs and invalidates.

## Restoring service after a breaker trip

Look at what caused it first (the alert email says which alarm fired). Then:

```sh
aws lambda invoke --region us-east-1 --function-name <name>-breaker \
  --cli-binary-format raw-in-base64-out --payload '{"action":"enable"}' /dev/stdout
```

## Requirements

Terraform ≥ 1.10 (S3-native state locking), AWS provider 5.x, an existing
Route 53 public hosted zone for the domain.

## Licence

MIT
