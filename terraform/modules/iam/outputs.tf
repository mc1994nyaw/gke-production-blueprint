output "node_service_account_email" {
  description = "Email of the node service account."
  value       = google_service_account.nodes.email
}

output "sample_app_service_account_email" {
  description = "Email of the sample app Workload Identity service account."
  value       = google_service_account.sample_app.email
}
