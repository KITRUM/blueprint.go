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
  default = ""
}

variable "pg_password" {
  type    = string
  default = ""
}

module "sql-db-access" {
  source     = "GoogleCloudPlatform/sql-db/google//modules/private_service_access"
  version    = "15.0.0"
  project_id = var.project
  vpc_network = module.vpc.network_name
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

  ip_configuration = {
    ipv4_enabled       = true
    require_ssl        = true
    private_network    = null
    allocated_ip_range = null
  }

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

resource "google_artifact_registry_repository" "basic" {
  format        = "DOCKER"
  repository_id = "${var.project}-basic"
  location      = var.region
}