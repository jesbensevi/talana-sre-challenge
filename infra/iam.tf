# -----------------------------------------------------------------------------
# External Secrets - Service Account y permisos
# -----------------------------------------------------------------------------

resource "google_service_account" "external_secrets" {
  account_id   = "external-secrets-sa"
  display_name = "External Secrets Service Account"
}

# Binding de Workload Identity (KSA -> GSA)
resource "google_service_account_iam_binding" "workload_identity_binding" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets-sa]"
  ]
}

# Permiso para leer secretos de Secret Manager
resource "google_project_iam_member" "external_secrets_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.external_secrets.email}"
}