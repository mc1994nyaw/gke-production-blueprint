# Partial backend. Bucket and prefix are supplied at init so this
# configuration does not contain a project id or credentials.
# CI uses `terraform init -backend=false` and never reads state.
# Create the bucket out of band, then:
#   terraform init -backend-config="bucket=STATE_BUCKET" -backend-config="prefix=gke-production-blueprint"
terraform {
  backend "gcs" {}
}
