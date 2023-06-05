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

provider "google" {
  project = "golang-blueprint"
  region  = "us-central1"
  zone    = "us-central1-c"
}

variable "project" {
  type    = string
  default = "golang-blueprint"
}

variable "region" {
  type = string
  default = "europe-central2"
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 7.0"

  project_id   = var.project
  network_name = "${var.project}-vpc"
  routing_mode = "GLOBAL"

  ip_cidr_range = "10.0.0.0/16"

  subnets = [
    {
      subnet_name   = "public-subnet-1"
      subnet_ip     = "10.0.1.0/24"
      subnet_region = "${var.region}-a"
      subnet_type   = "public"
    },
    {
      subnet_name   = "public-subnet-2"
      subnet_ip     = "10.0.2.0/24"
      subnet_region = "${var.region}-b"
      subnet_type   = "public"
    },
    {
      subnet_name   = "public-subnet-3"
      subnet_ip     = "10.0.3.0/24"
      subnet_region = "${var.region}-c"
      subnet_type   = "public"
    },
    {
      subnet_name   = "private-subnet-1"
      subnet_ip     = "10.0.11.0/24"
      subnet_region = "${var.region}-a"
      subnet_type   = "private"
    },
    {
      subnet_name   = "private-subnet-2"
      subnet_ip     = "10.0.12.0/24"
      subnet_region = "${var.region}-b"
      subnet_type   = "private"
    },
    {
      subnet_name   = "private-subnet-3"
      subnet_ip     = "10.0.13.0/24"
      subnet_region = "${var.region}-c"
      subnet_type   = "private"
    }
  ]

  routes = [
    {
      name             = "allow-egress"
      description      = "Allow all outgoing traffic"
      destination_cidr = "0.0.0.0/0"
      tags             = ["allow-egress"]
      next_hop_gateway = true
    }
  ]
}