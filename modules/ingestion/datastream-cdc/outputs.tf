output "stream_id" {
  value       = google_datastream_stream.this.id
  description = "Full resource ID of the Datastream CDC stream."
}

output "stream_name" {
  value       = google_datastream_stream.this.stream_id
  description = "Short Datastream CDC stream identifier."
}

output "source_profile_id" {
  value       = google_datastream_connection_profile.source.id
  description = "Full resource ID of the source connection profile."
}

output "destination_profile_id" {
  value       = google_datastream_connection_profile.destination.id
  description = "Full resource ID of the BigQuery destination profile."
}

output "private_connection_id" {
  value       = local.effective_private_connection
  description = "Private connectivity resource ID when configured, or empty string."
}
