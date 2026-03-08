terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    # Bucket name is provided at init time via -backend-config:
    #   terraform init -backend-config="bucket=<project_id>-tf-state"
    prefix = "openclaw"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
