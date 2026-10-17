variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "name_prefix" {
  description = "Short prefix used in service account ids."
  type        = string
}

variable "sample_app_namespace" {
  description = "Kubernetes namespace allowed to impersonate the sample app service account."
  type        = string
}

variable "sample_app_ksa" {
  description = "Kubernetes service account allowed to impersonate the sample app service account."
  type        = string
}
