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

module "sql-db" {
  source     = "GoogleCloudPlatform/sql-db/google//modules/postgresql"
  version    = "15.0.0"
  project_id = var.project

  name             = "${var.project}-pg"
  database_version = "PostgreSQL 15"

  enable_backups = true

  // HA config
  high_availability = true
  zone              = "${var.region}-a"
  secondary_zone    = "${var.region}-b"

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