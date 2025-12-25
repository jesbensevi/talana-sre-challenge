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

