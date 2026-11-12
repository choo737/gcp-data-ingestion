data "google_project" "datastream" {
  project_id = var.project_id
}

locals {
  sanitized_base = trimsuffix(substr(lower(replace("${var.prefix}-${var.stream_name}", "_", "-")), 0, 48), "-")
  effective_port = var.db_port > 0 ? var.db_port : (var.source_engine == "POSTGRESQL" ? 5432 : 3306)
  db_secret_id   = regex("^(projects/[^/]+/secrets/[^/]+)/versions/", var.db_password_secret_version)[0]

  datastream_service_agent = "serviceAccount:service-${data.google_project.datastream.number}@gcp-sa-datastream.iam.gserviceaccount.com"

  effective_private_connection = (
    var.create_private_connection
    ? google_datastream_private_connection.this[0].id
    : var.private_connection_id
  )
}

resource "terraform_data" "validate_private_connectivity" {
  lifecycle {
    precondition {
      condition     = !var.create_private_connection || var.network_attachment != "" || (var.vpc_id != "" && var.peering_cidr != "")
      error_message = "create_private_connection requires network_attachment or both vpc_id and peering_cidr."
    }
  }
}

resource "google_secret_manager_secret_iam_member" "datastream_db_password" {
  secret_id = local.db_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.datastream_service_agent
}

resource "google_bigquery_dataset_iam_member" "datastream_bronze_editor" {
  project    = var.bronze_project_id
  dataset_id = var.bronze_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.datastream_service_agent
}

resource "google_project_iam_member" "datastream_bronze_job_user" {
  project = var.bronze_project_id
  role    = "roles/bigquery.jobUser"
  member  = local.datastream_service_agent
}

resource "google_datastream_private_connection" "this" {
  count = var.create_private_connection ? 1 : 0

  project                   = var.project_id
  location                  = var.region
  private_connection_id     = "${local.sanitized_base}-priv"
  display_name              = "${var.prefix} ${var.stream_name} private"
  create_without_validation = var.create_without_validation
  labels                    = var.labels

  dynamic "psc_interface_config" {
    for_each = var.network_attachment != "" ? [var.network_attachment] : []
    content {
      network_attachment = psc_interface_config.value
    }
  }

  dynamic "vpc_peering_config" {
    for_each = var.network_attachment == "" && var.vpc_id != "" ? [1] : []
    content {
      vpc    = var.vpc_id
      subnet = var.peering_cidr
    }
  }

  depends_on = [terraform_data.validate_private_connectivity]
}

resource "google_datastream_connection_profile" "source" {
  project                   = var.project_id
  location                  = var.region
  connection_profile_id     = "${local.sanitized_base}-src"
  display_name              = "${var.prefix} ${var.stream_name} source"
  create_without_validation = var.create_without_validation
  labels                    = var.labels

  dynamic "postgresql_profile" {
    for_each = var.source_engine == "POSTGRESQL" ? [1] : []
    content {
      hostname                       = var.db_host
      port                           = local.effective_port
      username                       = var.db_username
      database                       = var.db_database
      secret_manager_stored_password = var.db_password_secret_version
    }
  }

  dynamic "mysql_profile" {
    for_each = var.source_engine == "MYSQL" ? [1] : []
    content {
      hostname                       = var.db_host
      port                           = local.effective_port
      username                       = var.db_username
      secret_manager_stored_password = var.db_password_secret_version
    }
  }

  dynamic "private_connectivity" {
    for_each = local.effective_private_connection != "" ? [local.effective_private_connection] : []
    content {
      private_connection = private_connectivity.value
    }
  }

  depends_on = [google_secret_manager_secret_iam_member.datastream_db_password]
}

resource "google_datastream_connection_profile" "destination" {
  project               = var.project_id
  location              = var.region
  connection_profile_id = "${local.sanitized_base}-bq"
  display_name          = "${var.prefix} ${var.stream_name} bigquery"
  labels                = var.labels

  bigquery_profile {}
}

resource "google_datastream_stream" "this" {
  project                         = var.project_id
  location                        = var.region
  stream_id                       = "${local.sanitized_base}-stream"
  display_name                    = "${var.prefix} ${var.stream_name} cdc"
  desired_state                   = var.start_stream ? "RUNNING" : "NOT_STARTED"
  customer_managed_encryption_key = var.kms_key_name != "" ? var.kms_key_name : null
  create_without_validation       = var.create_without_validation
  labels                          = var.labels

  source_config {
    source_connection_profile = google_datastream_connection_profile.source.id

    dynamic "postgresql_source_config" {
      for_each = var.source_engine == "POSTGRESQL" ? [1] : []
      content {
        publication                   = var.postgresql_publication
        replication_slot              = var.postgresql_replication_slot
        max_concurrent_backfill_tasks = var.max_concurrent_backfill_tasks

        dynamic "include_objects" {
          for_each = length(var.included_objects) > 0 ? [1] : []
          content {
            dynamic "postgresql_schemas" {
              for_each = var.included_objects
              content {
                schema = postgresql_schemas.key
                dynamic "postgresql_tables" {
                  for_each = postgresql_schemas.value
                  content {
                    table = postgresql_tables.value
                  }
                }
              }
            }
          }
        }
      }
    }

    dynamic "mysql_source_config" {
      for_each = var.source_engine == "MYSQL" ? [1] : []
      content {
        gtid {}
        max_concurrent_backfill_tasks = var.max_concurrent_backfill_tasks
        max_concurrent_cdc_tasks      = var.max_concurrent_cdc_tasks

        dynamic "include_objects" {
          for_each = length(var.included_objects) > 0 ? [1] : []
          content {
            dynamic "mysql_databases" {
              for_each = var.included_objects
              content {
                database = mysql_databases.key
                dynamic "mysql_tables" {
                  for_each = mysql_databases.value
                  content {
                    table = mysql_tables.value
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.destination.id

    bigquery_destination_config {
      data_freshness = var.cdc_mode == "MERGE" ? var.data_freshness : null

      single_target_dataset {
        dataset_id = "${var.bronze_project_id}:${var.bronze_dataset_id}"
      }

      dynamic "append_only" {
        for_each = var.cdc_mode == "APPEND_ONLY" ? [1] : []
        content {}
      }

      dynamic "merge" {
        for_each = var.cdc_mode == "MERGE" ? [1] : []
        content {}
      }
    }
  }

  dynamic "backfill_all" {
    for_each = var.backfill_mode == "ALL" ? [1] : []
    content {}
  }

  dynamic "backfill_none" {
    for_each = var.backfill_mode == "NONE" ? [1] : []
    content {}
  }

  depends_on = [
    google_bigquery_dataset_iam_member.datastream_bronze_editor,
    google_project_iam_member.datastream_bronze_job_user,
  ]
}
