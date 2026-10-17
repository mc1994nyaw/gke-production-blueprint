locals {
  required_services = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "network" {
  source = "./modules/network"

  project_id    = var.project_id
  region        = var.region
  name_prefix   = var.name_prefix
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr

  depends_on = [google_project_service.required]
}

module "iam" {
  source = "./modules/iam"

  project_id           = var.project_id
  name_prefix          = var.name_prefix
  sample_app_namespace = var.sample_app_namespace
  sample_app_ksa       = var.sample_app_ksa

  depends_on = [google_project_service.required]
}

module "gke" {
  source = "./modules/gke"

  project_id                 = var.project_id
  region                     = var.region
  name_prefix                = var.name_prefix
  network_name               = module.network.network_name
  subnet_name                = module.network.subnet_name
  pods_range_name            = module.network.pods_range_name
  services_range_name        = module.network.services_range_name
  master_ipv4_cidr_block     = var.master_ipv4_cidr_block
  enable_private_endpoint    = var.enable_private_endpoint
  master_global_access       = var.master_global_access
  master_authorized_cidrs    = var.master_authorized_cidrs
  release_channel            = var.release_channel
  deletion_protection        = var.deletion_protection
  maintenance_start          = var.maintenance_start
  maintenance_end            = var.maintenance_end
  maintenance_recurrence     = var.maintenance_recurrence
  node_pools                 = var.node_pools
  node_service_account_email = module.iam.node_service_account_email
  labels                     = var.labels

  depends_on = [google_project_service.required]
}
