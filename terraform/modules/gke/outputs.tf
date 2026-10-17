output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Cluster location. This module always uses a region."
  value       = google_container_cluster.this.location
}

output "cluster_id" {
  description = "GKE cluster id."
  value       = google_container_cluster.this.id
}
