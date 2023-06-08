terraform {
  required_providers {
    # Google Cloud Platform provider documentation:
    # https://registry.terraform.io/providers/hashicorp/google/latest/docs
    google = {
      source  = "hashicorp/google"
      version = "4.67.0"
    }
  }

  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "heartwilltell"

    workspaces {
      name = "blueprintgo"
    }
  }

  required_version = "~>1.4.2"
}

# Providers definition.

provider "google" {
  project = "golang-blueprint"
  region  = "europe-central2"
  zone    = "europe-central2-a"

  credentials = var.json_key_file_content
}

provider "google-beta" {
  project = "golang-blueprint"
  region  = "europe-central2"
  zone    = "europe-central2-a"

  credentials = var.json_key_file_content
}

# Variables

variable "json_key_file_content" {
  type = string
}

variable "project" {
  type    = string
  default = "golang-blueprint"
}

variable "region" {
  type    = string
  default = "europe-central2"
}

variable "pg_user" {
  type    = string
  default = "user"
}

variable "pg_password" {
  type    = string
  default = "password"
}

variable "db_tier" {
  type    = string
  default = "db-f1-micro"
}

module "sql-db-access" {
  source      = "GoogleCloudPlatform/sql-db/google//modules/private_service_access"
  version     = "15.0.0"
  project_id  = var.project
  vpc_network = module.vpc.network_name
}

# Cloud SQL

locals {
  ip_config = {
    ipv4_enabled                                  = true
    require_ssl                                   = false
    private_network                               = module.vpc.network_id
    enable_private_path_for_google_cloud_services = true
    allocated_ip_range                            = null
    authorized_networks                           = [
      {
        name  = "wfh"
        value = "85.57.71.73/32"
      }
    ]
  }
}

module "sql-db" {
  source     = "GoogleCloudPlatform/sql-db/google//modules/postgresql"
  version    = "15.0.0"
  project_id = var.project
  region     = var.region
  zone       = "${var.region}-a"

  name             = "${var.project}-pg"
  database_version = "POSTGRES_15"

  availability_type               = "REGIONAL"
  maintenance_window_day          = 7
  maintenance_window_hour         = 12
  maintenance_window_update_track = "stable"

  tier = var.db_tier

  db_name      = "${var.project}-pg-prod"
  db_charset   = "UTF8"
  db_collation = "en_US.UTF8"

  additional_databases = [
    {
      name      = "${var.project}-pg-dev"
      charset   = "UTF8"
      collation = "en_US.UTF8"
    },
    {
      name      = "${var.project}-pg-stage"
      charset   = "UTF8"
      collation = "en_US.UTF8"
    },
  ]

  ip_configuration = local.ip_config

  read_replica_name_suffix = "-replica"
  read_replicas            = [
    {
      name              = "0"
      zone              = "${var.region}-b"
      availability_type = "REGIONAL"
      tier              = var.db_tier

      ip_configuration = local.ip_config

      database_flags        = []
      disk_autoresize       = null
      disk_autoresize_limit = null
      disk_size             = null
      disk_type             = "PD_HDD"
      encryption_key_name   = null
      user_labels           = {
        terraform = "true"
      }
    }
  ]

  backup_configuration = {
    enabled                        = true
    start_time                     = "20:55"
    location                       = null
    point_in_time_recovery_enabled = false
    transaction_log_retention_days = null
    retained_backups               = 365
    retention_unit                 = "COUNT"
  }

  user_name     = var.pg_user
  user_password = var.pg_password
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider = google-beta

  network                 = module.vpc.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_compute_global_address" "private_ip_address" {
  provider = google-beta

  name          = "db-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = module.vpc.network_id
}

# VPC

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 7.0"

  project_id   = var.project
  network_name = "${var.project}-vpc"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "public-${var.region}-1"
      subnet_ip     = "10.0.1.0/24"
      subnet_region = var.region
      subnet_type   = "public"
    },
    {
      subnet_name   = "public-${var.region}-2"
      subnet_ip     = "10.0.2.0/24"
      subnet_region = var.region
      subnet_type   = "public"
    },
    {
      subnet_name   = "public-${var.region}-3"
      subnet_ip     = "10.0.3.0/24"
      subnet_region = var.region
      subnet_type   = "public"
    },
    {
      subnet_name   = "private-${var.region}-1"
      subnet_ip     = "10.0.11.0/24"
      subnet_region = var.region
      subnet_type   = "private"
    },
    {
      subnet_name   = "private-${var.region}-2"
      subnet_ip     = "10.0.12.0/24"
      subnet_region = var.region
      subnet_type   = "private"
    },
    {
      subnet_name   = "private-${var.region}-3"
      subnet_ip     = "10.0.13.0/24"
      subnet_region = var.region
      subnet_type   = "private"
    },
    {
      subnet_name           = "cloud-run-subnet"
      subnet_ip             = "10.10.0.0/28"
      subnet_region         = var.region
      subnet_private_access = "true"
      subnet_flow_logs      = "false"
      description           = "Cloud Run VPC Connector Subnet"
    }
  ]

  routes = [
    {
      name              = "allow-egress"
      description       = "Allow all outgoing traffic"
      destination_range = "0.0.0.0/0"
      tags              = "allow-all-egress"
      next_hop_internet = "true"
    }
  ]
}

module "serverless_connector" {
  source  = "terraform-google-modules/network/google//modules/vpc-serverless-connector-beta"
  version = "~> 4.0"

  project_id = var.project

  vpc_connectors = [
    {
      name            = "${var.region}-serverless"
      region          = var.region
      subnet_name     = module.vpc.subnets["${var.region}/cloud-run-subnet"]["name"]
      host_project_id = var.project
      machine_type    = "e2-micro"
      min_instances   = 2
      max_instances   = 3
    }
  ]
}

# GCR

resource "google_artifact_registry_repository" "basic" {
  format        = "DOCKER"
  repository_id = "${var.project}-basic"
  location      = var.region
}

# Cloud Run

module "service_account" {
  source     = "terraform-google-modules/service-accounts/google"
  version    = "~> 4.1.1"
  project_id = var.project
  prefix     = "sa-cloud-run"
  names      = ["vpc-connector"]
}

module "cloud_run" {
  source  = "GoogleCloudPlatform/cloud-run/google"
  version = "~> 0.2.0"

  service_name = "basic-dev"
  project_id   = var.project
  location     = var.region
  image        = "europe-central2-docker.pkg.dev/golang-blueprint/golang-blueprint-basic/api:latest"

  service_account_email = module.service_account.email

  ports = [
    {
      "name" : "http",
      "port" : 8080
    }
  ]

  env_vars = [
    {
      name  = "ENV"
      value = "dev"
    },
    {
      name  = "DB_CONN_STR"
      value = "postgres://${var.pg_user}:${var.pg_password}@${module.sql-db.private_ip_address}:5432/${var.project}-pg-dev"
    },
    {
      name  = "DB_MIGRATE"
      value = "true"
    }
  ]

  template_annotations = {
    "autoscaling.knative.dev/maxScale"        = 3
    "autoscaling.knative.dev/minScale"        = 1
    "run.googleapis.com/cloudsql-instances"   = module.sql-db.instance_connection_name
    "run.googleapis.com/vpc-access-connector" = element(tolist(module.serverless_connector.connector_ids), 1)
    "run.googleapis.com/vpc-access-egress"    = "all-traffic"
  }
}

#resource "google_cloud_run_v2_service" "dev" {
#  name     = "basic-dev"
#  location = var.region
#  ingress  = "INGRESS_TRAFFIC_ALL"
#
#  launch_stage = ""
#
#  template {
#    scaling {
#      min_instance_count = 1
#      max_instance_count = 3
#    }
#
#    containers {
#      image = "europe-central2-docker.pkg.dev/golang-blueprint/golang-blueprint-basic/api:latest"
#
#      args = ["serve"]
#
#      env {
#        name  = "ENV"
#        value = "dev"
#      }
#
#      env {
#        name  = "DB_CONN_STR"
#        value = "postgres://${var.pg_user}:${var.pg_password}@${module.sql-db.public_ip_address}:5432/${var.project}-pg-dev"
#      }
#
#      env {
#        name  = "DB_MIGRATE"
#        value = "true"
#      }
#
#      liveness_probe {
#        failure_threshold = 3
#        timeout_seconds   = 5
#        period_seconds    = 10
#
#        http_get {
#          path = "/health"
#        }
#      }
#
#      ports {
#        container_port = 8080
#      }
#    }
#  }
#}