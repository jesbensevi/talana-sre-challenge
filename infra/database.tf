
resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "google_sql_database_instance" "main" {
  name             = "talana-db-${random_id.db_name_suffix.hex}"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_15"

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_size         = 10

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }

    backup_configuration {
      enabled = false
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]

  deletion_protection = false
}

resource "google_sql_database" "main" {
  name     = "talana_db"
  project  = var.project_id
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "app" {
  name     = "app_user"
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result
}
