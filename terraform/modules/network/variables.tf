variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "region" {
  description = "Region for the subnet, router, and Cloud NAT."
  type        = string
}

variable "name_prefix" {
  description = "Short prefix used in network resource names."
  type        = string
}

variable "subnet_cidr" {
  description = "Primary CIDR for node addresses."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary CIDR for pod addresses."
  type        = string
}

variable "services_cidr" {
  description = "Secondary CIDR for service addresses."
  type        = string
}
