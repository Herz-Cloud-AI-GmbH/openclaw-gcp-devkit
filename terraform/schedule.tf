# Optional VM start/stop schedule to reduce costs.
# Enable via: vm_schedule_enabled = true in terraform.tfvars

resource "google_compute_resource_policy" "vm_schedule" {
  count = var.vm_schedule_enabled ? 1 : 0

  name        = "${var.instance_name}-schedule"
  region      = var.region
  description = "Auto start/stop schedule for ${var.instance_name}"

  instance_schedule_policy {
    vm_start_schedule {
      schedule = var.vm_schedule_start
    }
    vm_stop_schedule {
      schedule = var.vm_schedule_stop
    }
    time_zone = var.vm_schedule_timezone
  }
}
