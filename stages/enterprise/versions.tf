terraform {
  required_version = ">= 1.8.0"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0.0, < 9.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 8.0.0, < 9.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11.0, < 1.0.0"
    }
  }
}
