resource "google_compute_network" "openclaw" {
  name                    = "openclaw-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "openclaw" {
  name          = "openclaw-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.openclaw.id
}

# --- Cloud NAT (outbound internet for a VM with no external IP) ----------

resource "google_compute_router" "openclaw" {
  name    = "openclaw-router"
  region  = var.region
  network = google_compute_network.openclaw.id
}

resource "google_compute_router_nat" "openclaw" {
  name                               = "openclaw-nat"
  router                             = google_compute_router.openclaw.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# --- Firewall rules -------------------------------------------------------

resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "openclaw-allow-iap-ssh"
  network = google_compute_network.openclaw.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["openclaw-ssh"]

  description = "Allow SSH from IAP tunnel range only"
}

resource "google_compute_firewall" "deny_all_ingress" {
  name    = "openclaw-deny-all-ingress"
  network = google_compute_network.openclaw.id

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["openclaw-ssh"]

  priority    = 65534
  description = "Deny all other ingress traffic"
}
