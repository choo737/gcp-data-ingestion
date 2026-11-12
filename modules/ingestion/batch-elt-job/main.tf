locals {
  sa_account_id = trimsuffix(substr(lower("${replace(var.prefix, "_", "-")}-batch-loader"), 0, 30), "-")
  job_name      = trimsuffix(substr(lower(replace("${var.prefix}-${var.job_suffix}", "_", "-")), 0, 63), "-")
}

resource "google_service_account" "batch_loader" {
  project      = var.compute_project_id
  account_id   = local.sa_account_id
  display_name = "${var.prefix} Batch Loader"
  description  = "Dedicated least-privilege service account for Cloud Run GCS-to-Bronze loads."
}

resource "google_storage_bucket_iam_member" "landing_objects" {
  bucket = var.landing_bucket_name
  role   = "roles/storage.objectUser"
  member = google_service_account.batch_loader.member
}

resource "google_bigquery_dataset_iam_member" "bronze_editor" {
  project    = var.bronze_project_id
  dataset_id = var.bronze_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_service_account.batch_loader.member
}

resource "google_project_iam_member" "compute_job_user" {
  project = var.compute_project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.batch_loader.member
}

resource "google_kms_crypto_key_iam_member" "batch_loader_cmek" {
  count = var.kms_key_id != "" ? 1 : 0

  crypto_key_id = var.kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = google_service_account.batch_loader.member
}

resource "google_cloud_run_v2_job" "this" {
  project             = var.compute_project_id
  location            = var.region
  name                = local.job_name
  deletion_protection = !var.delete_contents_on_destroy
  labels              = var.labels

  template {
    template {
      service_account = google_service_account.batch_loader.email
      max_retries     = var.max_retries
      timeout         = var.timeout
      encryption_key  = var.kms_key_id != "" ? var.kms_key_id : null

      containers {
        image = var.container_image

        env {
          name  = "BRONZE_PROJECT"
          value = var.bronze_project_id
        }
        env {
          name  = "BRONZE_DATASET"
          value = var.bronze_dataset_id
        }
        env {
          name  = "EXECUTION_PROJECT"
          value = var.compute_project_id
        }
        env {
          name  = "LANDING_BUCKET"
          value = var.landing_bucket_name
        }
        env {
          name  = "SOURCE_PREFIX"
          value = var.source_prefix
        }
        env {
          name  = "TARGET_TABLE"
          value = var.target_table
        }
        env {
          name  = "SOURCE_FORMAT"
          value = var.source_format
        }
        env {
          name  = "KMS_KEY_ID"
          value = var.kms_key_id
        }
        env {
          name  = "QUARANTINE_PREFIX"
          value = var.quarantine_prefix
        }
        env {
          name  = "FAIL_ON_QUARANTINE"
          value = var.fail_on_quarantine ? "true" : "false"
        }
      }
    }
  }

  depends_on = [
    google_storage_bucket_iam_member.landing_objects,
    google_bigquery_dataset_iam_member.bronze_editor,
    google_project_iam_member.compute_job_user,
    google_kms_crypto_key_iam_member.batch_loader_cmek,
  ]
}
