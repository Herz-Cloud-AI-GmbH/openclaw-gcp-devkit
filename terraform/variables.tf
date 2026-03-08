variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for the compute instance"
  type        = string
  default     = "europe-west1-b"
}

variable "instance_name" {
  description = "Name of the Compute Engine instance"
  type        = string
  default     = "openclaw-gateway"
}

variable "machine_type" {
  description = "GCP machine type"
  type        = string
  default     = "e2-medium"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 20
}

# --- Optional VM start/stop schedule (cost saving) ---

variable "vm_schedule_enabled" {
  description = "Enable automatic VM start/stop schedule"
  type        = bool
  default     = false
}

variable "vm_schedule_timezone" {
  description = "IANA timezone for the schedule (e.g. Europe/Berlin, US/Central)"
  type        = string
  default     = "UTC"
}

variable "vm_schedule_start" {
  description = "Cron expression for VM start (e.g. '0 8 * * 1-5' = 08:00 weekdays)"
  type        = string
  default     = "0 8 * * 1-5"
}

variable "vm_schedule_stop" {
  description = "Cron expression for VM stop (e.g. '0 22 * * *' = 22:00 every day)"
  type        = string
  default     = "0 22 * * *"
}
