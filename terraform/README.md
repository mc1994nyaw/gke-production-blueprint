# Terraform

Example root module for a private regional GKE cluster. `terraform validate` does not need credentials. `plan` and `apply` do, and they are not part of CI.

First time here? Use [docs/runbook.md](../docs/runbook.md), then [docs/runbook-deploy.md](../docs/runbook-deploy.md). Teardown, including `deletion_protection`, is in [docs/runbook-operations.md](../docs/runbook-operations.md).

## What it creates

- A custom-mode VPC, one subnet with private Google access, pod and service secondary ranges, VPC flow logs, a Cloud Router, and Cloud NAT. Nodes do not get public IPs. GCP has no separate "private subnet" type; privacy here means private nodes plus NAT egress.
- A regional GKE cluster with private nodes, a private control plane endpoint, Workload Identity, Dataplane V2, Shielded Nodes, and the REGULAR release channel.
- Three node pools with Cluster Autoscaler: `system` (no taint), `application` (tainted), and `logging` (tainted, minimum 0 because this repo does not ship a log collector).
- A node service account with `roles/container.defaultNodeServiceAccount` only.
- A sample-app Google service account with no project roles. The Kubernetes service account may impersonate it. podinfo does not call Google APIs, so there is nothing to grant yet.

Machine types, disk sizes, CIDRs, and autoscaling bounds in `terraform.tfvars.example` are placeholders.

## Remote state

State is a partial GCS backend. The bucket is not created by this module, because the bucket has to exist before `terraform init` can use it.

```bash
gcloud storage buckets create gs://STATE_BUCKET \
  --project PROJECT_ID \
  --location REGION \
  --uniform-bucket-level-access

gcloud storage buckets update gs://STATE_BUCKET --versioning
```

Use a name that is not guessable. Do not commit the bucket name if the bucket is private to you. Then:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit project_id and master_authorized_cidrs

terraform init \
  -backend-config="bucket=STATE_BUCKET" \
  -backend-config="prefix=gke-production-blueprint"

terraform plan
terraform apply
```

CI runs `terraform init -backend=false`, then `terraform validate`. It does not log in to Google and does not run `plan`.

## After apply

`enable_private_endpoint` defaults to true, and this module does not create a bastion, VPN, or IAP tunnel. `gcloud container clusters get-credentials` only works from a network that can reach the private endpoint, and only from a CIDR you put in `master_authorized_cidrs`. The example CIDR `203.0.113.10/32` is documentation space (RFC 5737). Replace it before apply.

```bash
terraform output sample_app_gsa_email
terraform output get_credentials_command
```

If `project_id` or `name_prefix` changes, update the annotation in `manifests/sample-app/serviceaccount.yaml` to the output email. The committed manifest matches the example values `gke-bp` and `example-project-id`.

Pulling images from a private Artifact Registry repository needs `roles/artifactregistry.reader` on the node service account. The sample app uses a public image, so that role is not granted.

## Destroy

`deletion_protection` defaults to true. Set it to false and apply before `terraform destroy`.
