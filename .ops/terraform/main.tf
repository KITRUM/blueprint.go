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

# GKE
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

module "gke" {
  source     = "terraform-google-modules/kubernetes-engine/google//modules/safer-cluster"
  project_id = var.project

  region   = var.region
  regional = true

  name              = "${var.project}-gke"
  description       = "${var.project}-gke"
  network           = module.vpc.network_name
  subnetwork        = module.vpc.network_name
  ip_range_pods     = "${var.project}-gke-pods"
  ip_range_services = "${var.project}-gke-services"

  create_service_account     = true
  http_load_balancing        = true
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = true
  istio                      = true
  cloudrun                   = true
  dns_cache                  = false

  node_pools = [
    {
      name                      = "${var.project}-default-pool"
      machine_type              = "e2-micro"
      min_count                 = 1
      max_count                 = 3
      initial_node_count        = 1
      local_ssd_count           = 0
      spot                      = false
      local_ssd_ephemeral_count = 0
      disk_size_gb              = 100
      disk_type                 = "pd-standard"
      image_type                = "COS_CONTAINERD"
      enable_gcfs               = false
      enable_gvnic              = false
      auto_repair               = true
      auto_upgrade              = true
      preemptible               = false
    },
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }
}

# Cloud SQL

module "sql-db-access" {
  source      = "GoogleCloudPlatform/sql-db/google//modules/private_service_access"
  version     = "15.0.0"
  project_id  = var.project
  vpc_network = module.vpc.network_name
}

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
      name            = "eurserverlessconn"
      region          = var.region
      subnet_name     = module.vpc.subnets["${var.region}/cloud-run-subnet"]["name"]
      host_project_id = var.project
      machine_type    = "f1-micro"
      min_instances   = 2
      max_instances   = 3
    }
  ]
}

module "service_account" {
  source     = "terraform-google-modules/service-accounts/google"
  version    = "~> 4.1.1"
  project_id = var.project
  prefix     = "sa-cloud-run"
  names      = ["vpc-connector"]
}

# GCR

resource "google_artifact_registry_repository" "basic" {
  format        = "DOCKER"
  repository_id = "${var.project}-basic"
  location      = var.region
}

# Cloud Run DEV

module "cloud_run" {
  source  = "GoogleCloudPlatform/cloud-run/google"
  version = "~> 0.2.0"

  service_name = "basic-dev"
  project_id   = var.project
  location     = var.region
  image        = "europe-central2-docker.pkg.dev/golang-blueprint/golang-blueprint-basic/api:latest"

  service_account_email = module.service_account.email

  ports = {
    "name" : "http1",
    "port" : 8080
  }

  argument = ["serve"]

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

resource "google_cloud_run_service_iam_binding" "noauth-dev" {
  location = module.cloud_run.location
  service  = module.cloud_run.service_name
  role     = "roles/run.invoker"
  members  = [
    "allUsers"
  ]
}

# Cloud Run STAGE

module "cloud_run_stage" {
  source  = "GoogleCloudPlatform/cloud-run/google"
  version = "~> 0.2.0"

  service_name = "basic-stage"
  project_id   = var.project
  location     = var.region
  image        = "europe-central2-docker.pkg.dev/golang-blueprint/golang-blueprint-basic/api:latest"

  service_account_email = module.service_account.email

  ports = {
    "name" : "http1",
    "port" : 8080
  }

  argument = ["serve"]

  env_vars = [
    {
      name  = "ENV"
      value = "stage"
    },
    {
      name  = "DB_CONN_STR"
      value = "postgres://${var.pg_user}:${var.pg_password}@${module.sql-db.private_ip_address}:5432/${var.project}-pg-stage"
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

resource "google_cloud_run_service_iam_binding" "noauth-stage" {
  location = module.cloud_run_stage.location
  service  = module.cloud_run_stage.service_name
  role     = "roles/run.invoker"
  members  = [
    "allUsers"
  ]
}

# Cloud Run PROD

module "cloud_run_prod" {
  source  = "GoogleCloudPlatform/cloud-run/google"
  version = "~> 0.2.0"

  service_name = "basic-prod"
  project_id   = var.project
  location     = var.region
  image        = "europe-central2-docker.pkg.dev/golang-blueprint/golang-blueprint-basic/api:latest"

  service_account_email = module.service_account.email

  ports = {
    "name" : "http1",
    "port" : 8080
  }

  argument = ["serve"]

  env_vars = [
    {
      name  = "ENV"
      value = "prod"
    },
    {
      name  = "DB_CONN_STR"
      value = "postgres://${var.pg_user}:${var.pg_password}@${module.sql-db.private_ip_address}:5432/${var.project}-pg-prod"
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

resource "google_cloud_run_service_iam_binding" "noauth-prod" {
  location = module.cloud_run_prod.location
  service  = module.cloud_run_prod.service_name
  role     = "roles/run.invoker"
  members  = [
    "allUsers"
  ]
}


