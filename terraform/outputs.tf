output "network_name" {
  description = "VPC name."
  value       = module.network.network_name
}

output "subnet_name" {
  description = "Node subnet name."
  value       = module.network.subnet_name
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = module.gke.cluster_name
}

output "cluster_location" {
  description = "Region of the regional cluster."
  value       = module.gke.cluster_location
}

output "node_service_account_email" {
  description = "Least-privilege service account used by nodes."
  value       = module.iam.node_service_account_email
}

output "sample_app_gsa_email" {
  description = "Workload Identity service account email. Copy it into the sample-app ServiceAccount annotation if name_prefix or project_id changes."
  value       = module.iam.sample_app_service_account_email
}

output "get_credentials_command" {
  description = "Command that fetches kubeconfig after apply. Requires a network path to the private endpoint when enable_private_endpoint is true."
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${module.gke.cluster_location} --project ${var.project_id}"
}
