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

# GCR

resource "google_artifact_registry_repository" "basic" {
  format        = "DOCKER"
  repository_id = "${var.project}-basic"
  location      = var.region
}

# Cloud Run

resource "google_cloud_run_v2_service" "dev" {
  name     = "basic-dev"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    scaling {
      min_instance_count = 1
      max_instance_count = 3
    }

    containers {
      image = "${google_artifact_registry_repository.basic.id}/api"

      args = [
        "serve",
        "-env=dev",
        "-http-addr=:8080",
        "-db-conn-str='host=${module.sql-db.public_ip_address} user=${var.pg_user} password=${var.pg_password} port=5432 database=${var.project}-pg-dev'",
        "-db-migrate",
      ]

      liveness_probe {
        failure_threshold = 3
        timeout_seconds   = 5
        period_seconds    = 10

        http_get {
          path = "/health"
        }
      }

      ports {
        container_port = 8080
      }
    }
  }
}