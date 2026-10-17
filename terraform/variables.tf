variable "project_id" {
  description = "GCP project id that will own the network, cluster, and service accounts. The example value is a placeholder."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a letter, and use only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "Region for the subnet, Cloud NAT, and the regional GKE cluster. us-central1 in the example is a placeholder, not a placement decision."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "region must look like a GCP region, for example us-central1."
  }
}

variable "name_prefix" {
  description = "Short prefix for resource names. Kept under 20 characters so service account ids stay within the 30 character limit."
  type        = string
  default     = "gke-bp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2-20 lowercase characters and start with a letter."
  }
}

variable "subnet_cidr" {
  description = "Primary CIDR for node IPs. Nodes have no public IPs. Example range, not a measured allocation."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary CIDR for pod IPs. Example range."
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR for ClusterIP services. Example range."
  type        = string
  default     = "10.30.0.0/20"
}

variable "master_ipv4_cidr_block" {
  description = "RFC1918 /28 for the control plane private endpoint. Example range."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a /28."
  }
}

variable "enable_private_endpoint" {
  description = "When true, the control plane has no public endpoint. kubectl then needs a path inside the VPC. This example does not create that path."
  type        = bool
  default     = true
}

variable "master_global_access" {
  description = "Allow reaching the private control plane endpoint from other regions. Left false in the example."
  type        = bool
  default     = false
}

variable "master_authorized_cidrs" {
  description = "CIDRs allowed to reach the control plane endpoint. The example uses TEST-NET-3 (RFC 5737) and must be replaced before any real apply."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "203.0.113.10/32"
      display_name = "example-replace-me"
    }
  ]
}

variable "release_channel" {
  description = "GKE release channel. REGULAR is the example. STABLE is a one-line change."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "EXTENDED"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, STABLE, or EXTENDED."
  }
}

variable "deletion_protection" {
  description = "When true, Terraform will not destroy the cluster until this is set to false."
  type        = bool
  default     = true
}

variable "maintenance_start" {
  description = "RFC3339 anchor for the weekly maintenance window. The date is only an anchor; recurrence picks the weekday. Example window."
  type        = string
  default     = "2026-01-04T09:00:00Z"
}

variable "maintenance_end" {
  description = "RFC3339 end of the maintenance window. Example window."
  type        = string
  default     = "2026-01-04T13:00:00Z"
}

variable "maintenance_recurrence" {
  description = "RFC5545 recurrence for the maintenance window. Example: Sunday 09:00-13:00 UTC."
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SU"
}

variable "node_pools" {
  description = "Node pools and Cluster Autoscaler bounds. Machine types and counts are example sizes, not a capacity plan."
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
  default = {
    system = {
      machine_type = "e2-standard-2"
      disk_size_gb = 50
      disk_type    = "pd-balanced"
      min_nodes    = 1
      max_nodes    = 3
      labels       = { role = "system" }
    }
    application = {
      machine_type = "e2-standard-2"
      disk_size_gb = 50
      disk_type    = "pd-balanced"
      min_nodes    = 1
      max_nodes    = 5
      labels       = { role = "application" }
      taints = [
        {
          key    = "workload"
          value  = "app"
          effect = "NO_SCHEDULE"
        }
      ]
    }
    logging = {
      machine_type = "e2-standard-2"
      disk_size_gb = 50
      disk_type    = "pd-balanced"
      # No collector is shipped, so the example does not keep nodes running.
      min_nodes = 0
      max_nodes = 3
      labels    = { role = "logging" }
      taints = [
        {
          key    = "workload"
          value  = "logging"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  validation {
    condition = alltrue([
      for pool in var.node_pools : pool.min_nodes >= 0 && pool.min_nodes <= pool.max_nodes
    ])
    error_message = "Each node pool needs min_nodes >= 0 and min_nodes <= max_nodes."
  }
}

variable "sample_app_namespace" {
  description = "Namespace of the sample workload. Must match manifests/sample-app."
  type        = string
  default     = "sample-app"
}

variable "sample_app_ksa" {
  description = "Kubernetes service account of the sample workload. Must match manifests/sample-app."
  type        = string
  default     = "sample-app"
}

variable "labels" {
  description = "Labels applied to the GKE cluster."
  type        = map(string)
  default = {
    managed_by = "terraform"
    repository = "gke-production-blueprint"
  }
}
