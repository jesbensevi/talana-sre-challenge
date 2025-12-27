resource "google_secret_manager_secret" "db_connection" {
  secret_id = "talana-db-connection"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_connection" {
  secret = google_secret_manager_secret.db_connection.id

  secret_data = jsonencode({
    host     = google_sql_database_instance.main.private_ip_address
    port     = 5432
    database = google_sql_database.main.name
    username = google_sql_user.app.name
    password = random_password.db_password.result
  })
}

# Permiso para la Service Account (External Secrets)
resource "google_secret_manager_secret_iam_member" "db_connection_access" {
  secret_id = google_secret_manager_secret.db_connection.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"
}