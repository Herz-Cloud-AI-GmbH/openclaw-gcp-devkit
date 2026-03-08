resource "google_service_account" "openclaw" {
  account_id   = "openclaw-vm-sa"
  display_name = "OpenClaw VM Service Account"
  description  = "Least-privilege service account for the OpenClaw Compute Engine instance"
}

resource "google_project_iam_member" "openclaw_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_project_iam_member" "openclaw_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}

# --- IAP tunnel access (SSH without external IP) --------------------------

data "google_client_openid_userinfo" "me" {}

resource "google_project_iam_member" "iap_tunnel_user" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "user:${data.google_client_openid_userinfo.me.email}"
}
