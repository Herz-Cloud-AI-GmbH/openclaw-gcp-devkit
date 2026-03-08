output "instance_name" {
  description = "Name of the Compute Engine instance"
  value       = google_compute_instance.openclaw.name
}

output "instance_zone" {
  description = "Zone of the Compute Engine instance"
  value       = google_compute_instance.openclaw.zone
}
