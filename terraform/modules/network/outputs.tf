output "network_name" {
  description = "VPC name."
  value       = google_compute_network.this.name
}

output "network_id" {
  description = "VPC id."
  value       = google_compute_network.this.id
}

output "subnet_name" {
  description = "Node subnet name."
  value       = google_compute_subnetwork.nodes.name
}

output "subnet_id" {
  description = "Node subnet id."
  value       = google_compute_subnetwork.nodes.id
}

output "pods_range_name" {
  description = "Secondary range name for pods."
  value       = local.pods_range_name
}

output "services_range_name" {
  description = "Secondary range name for services."
  value       = local.services_range_name
}

output "nat_name" {
  description = "Cloud NAT name."
  value       = google_compute_router_nat.this.name
}
