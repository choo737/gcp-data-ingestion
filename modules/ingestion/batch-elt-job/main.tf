locals {
  sa_account_id                = trimsuffix(substr(lower("${replace(var.prefix, "_", "-")}-batch-loader"), 0, 30), "-")
  job_name                     = trimsuffix(substr(lower(replace("${var.prefix}-${var.job_suffix}", "_", "-")), 0, 63), "-")
  effective_kms_key_id         = var.kms_key_id != null ? trimspace(var.kms_key_id) : ""
  effective_vpc_id             = var.vpc_id != null ? trimspace(var.vpc_id) : ""
  effective_subnet_id          = var.subnet_id != null ? trimspace(var.subnet_id) : ""
  use_direct_vpc               = local.effective_vpc_id != "" || local.effective_subnet_id != ""
  effective_pii_restricted_tag = var.pii_restricted_policy_tag_id != null ? trimspace(var.pii_restricted_policy_tag_id) : ""
  effective_pii_masked_tag     = var.pii_masked_policy_tag_id != null ? trimspace(var.pii_masked_policy_tag_id) : ""

  default_target_schema_json = jsonencode([
    { name = "order_id", type = "STRING", mode = "NULLABLE", description = "Unique POS order identifier." },
    { name = "order_date", type = "DATE", mode = "NULLABLE", description = "Order calendar date." },
    { name = "store_id", type = "STRING", mode = "NULLABLE", description = "Retail store identifier." },
    { name = "customer_id", type = "STRING", mode = "NULLABLE", description = "Customer identifier." },
    merge(
      { name = "customer_ic_number", type = "STRING", mode = "NULLABLE", description = "Customer identity number." },
      local.effective_pii_restricted_tag != "" ? { policyTags = { names = [local.effective_pii_restricted_tag] } } : {}
    ),
    merge(
      { name = "customer_email", type = "STRING", mode = "NULLABLE", description = "Customer email address." },
      local.effective_pii_masked_tag != "" ? { policyTags = { names = [local.effective_pii_masked_tag] } } : {}
    ),
    { name = "country_code", type = "STRING", mode = "NULLABLE", description = "ISO country code." },
    { name = "currency_code", type = "STRING", mode = "NULLABLE", description = "ISO currency code." },
    { name = "gross_amount", type = "NUMERIC", mode = "NULLABLE", description = "Gross order amount." },
    { name = "discount_amount", type = "NUMERIC", mode = "NULLABLE", description = "Discount amount applied." },
    { name = "tax_amount", type = "NUMERIC", mode = "NULLABLE", description = "Tax amount applied." },
    { name = "net_amount", type = "NUMERIC", mode = "NULLABLE", description = "Net order amount." },
    { name = "order_status", type = "STRING", mode = "NULLABLE", description = "Order lifecycle status." },
    { name = "updated_at", type = "TIMESTAMP", mode = "NULLABLE", description = "Source record timestamp." },
    { name = "_metadata_deleted", type = "BOOL", mode = "NULLABLE", description = "Logical delete marker." },
    { name = "_ingested_at", type = "TIMESTAMP", mode = "NULLABLE", description = "Batch ingestion timestamp." },
    { name = "_cdc_sequence_num", type = "INT64", mode = "NULLABLE", description = "Batch sequence number." },
    { name = "_op_type", type = "STRING", mode = "NULLABLE", description = "Batch operation type." },
  ])

  effective_target_schema_json = (
    var.target_table_schema_json != ""
    ? var.target_table_schema_json
    : local.default_target_schema_json
  )
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
  count = local.effective_kms_key_id != "" ? 1 : 0

  crypto_key_id = local.effective_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = google_service_account.batch_loader.member
}

resource "google_bigquery_table" "target" {
  count = var.create_target_table ? 1 : 0

  project             = var.bronze_project_id
  dataset_id          = var.bronze_dataset_id
  table_id            = var.target_table
  description         = "Partitioned Bronze batch landing table with PII policy tags."
  deletion_protection = !var.delete_contents_on_destroy
  clustering          = length(var.target_clustering) > 0 ? var.target_clustering : null
  schema              = local.effective_target_schema_json
  labels              = var.labels

  time_partitioning {
    type  = "DAY"
    field = "order_date"
  }

  dynamic "encryption_configuration" {
    for_each = local.effective_kms_key_id != "" ? [local.effective_kms_key_id] : []
    content {
      kms_key_name = encryption_configuration.value
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.batch_loader_cmek]
}

resource "google_cloud_run_v2_job" "this" {
  project             = var.compute_project_id
  location            = var.region
  name                = local.job_name
  deletion_protection = !var.delete_contents_on_destroy
  labels              = var.labels

  template {
    parallelism = 1
    task_count  = 1

    template {
      service_account = google_service_account.batch_loader.email
      max_retries     = var.max_retries
      timeout         = var.timeout
      encryption_key  = local.effective_kms_key_id != "" ? local.effective_kms_key_id : null

      dynamic "vpc_access" {
        for_each = local.use_direct_vpc ? [1] : []
        content {
          egress = var.vpc_egress
          network_interfaces {
            network    = local.effective_vpc_id != "" ? local.effective_vpc_id : null
            subnetwork = local.effective_subnet_id != "" ? local.effective_subnet_id : null
          }
        }
      }

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
          value = local.effective_kms_key_id
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
    google_bigquery_table.target,
  ]
}
