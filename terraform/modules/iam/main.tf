resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-nodes"
  display_name = "GKE nodes (${var.name_prefix})"
}

# Google's current minimum role for a custom node service account:
# https://docs.cloud.google.com/kubernetes-engine/security/configure-node-service-accounts
resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_service_account" "sample_app" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-sample"
  display_name = "Sample app Workload Identity (${var.name_prefix})"
}

# podinfo does not call Google APIs, so this identity has no project roles.
# Grant a role here when a workload actually needs one.
resource "google_service_account_iam_member" "sample_app_workload_identity" {
  service_account_id = google_service_account.sample_app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.sample_app_namespace}/${var.sample_app_ksa}]"
}
