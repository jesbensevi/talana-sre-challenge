# -----------------------------------------------------------------------------
# Artifact Registry - Container Registry para imagenes Docker
# -----------------------------------------------------------------------------

resource "google_artifact_registry_repository" "talana" {
  location      = var.region
  repository_id = "talana-repo"
  description   = "Docker repository for Talana applications"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-minimum-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
}

# Permitir que GKE pueda hacer pull de imagenes
resource "google_artifact_registry_repository_iam_member" "gke_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.talana.location
  repository = google_artifact_registry_repository.talana.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_container_cluster.primary.node_config[0].service_account}"

  depends_on = [google_container_cluster.primary]
}

# Permitir que GitHub Actions pueda hacer push de imagenes
resource "google_artifact_registry_repository_iam_member" "github_actions_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.talana.location
  repository = google_artifact_registry_repository.talana.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:github-actions-sa@${var.project_id}.iam.gserviceaccount.com"
}
