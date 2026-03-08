resource "google_compute_instance" "openclaw" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.openclaw.id
    subnetwork = google_compute_subnetwork.openclaw.id
  }

  metadata_startup_script = file("${path.module}/../scripts/startup.sh")

  service_account {
    email = google_service_account.openclaw.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
    ]
  }

  resource_policies = var.vm_schedule_enabled ? [google_compute_resource_policy.vm_schedule[0].id] : []

  tags = ["openclaw-ssh"]

  labels = {
    app     = "openclaw"
    managed = "terraform"
  }

  allow_stopping_for_update = true
}
