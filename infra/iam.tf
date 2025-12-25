# 1. Creamos la identidad (Service Account)
resource "google_service_account" "external_secrets" {
  account_id   = "external-secrets-sa"
  display_name = "External Secrets Service Account"
}


resource "google_service_account_iam_binding" "workload_identity_binding" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
  ]
}