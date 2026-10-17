variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "region" {
  description = "Region for the regional cluster and its node pools."
  type        = string
}

variable "name_prefix" {
  description = "Short prefix used in the cluster name."
  type        = string
}

variable "network_name" {
  description = "VPC name."
  type        = string
}

variable "subnet_name" {
  description = "Subnetwork name for nodes."
  type        = string
}

variable "pods_range_name" {
  description = "Secondary range name for pods."
  type        = string
}

variable "services_range_name" {
  description = "Secondary range name for services."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "/28 CIDR for the control plane."
  type        = string
}

variable "enable_private_endpoint" {
  description = "Disable the public control plane endpoint."
  type        = bool
}

variable "master_global_access" {
  description = "Allow cross-region access to the private control plane endpoint."
  type        = bool
}

variable "master_authorized_cidrs" {
  description = "CIDRs that may reach the control plane endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "release_channel" {
  description = "GKE release channel."
  type        = string
}

variable "deletion_protection" {
  description = "Protect the cluster from Terraform destroy."
  type        = bool
}

variable "maintenance_start" {
  description = "RFC3339 start of the recurring maintenance window."
  type        = string
}

variable "maintenance_end" {
  description = "RFC3339 end of the recurring maintenance window."
  type        = string
}

variable "maintenance_recurrence" {
  description = "RFC5545 recurrence for maintenance."
  type        = string
}

variable "node_service_account_email" {
  description = "Service account email attached to every node."
  type        = string
}

variable "labels" {
  description = "Cluster resource labels."
  type        = map(string)
}

variable "node_pools" {
  description = "Node pools to create. Autoscaling bounds are totals across zones."
  type = map(object({
    machine_type = string
    disk_size_gb = number
    disk_type    = string
    min_nodes    = number
    max_nodes    = number
    labels       = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}
