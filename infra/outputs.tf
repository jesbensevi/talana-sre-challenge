
output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP Region"
  value       = var.region
}

output "vpc_name" {
  description = "Nombre de la VPC"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Nombre de la subnet"
  value       = google_compute_subnetwork.subnet.name
}


output "gke_cluster_name" {
  description = "Nombre del cluster GKE"
  value       = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  description = "Endpoint del cluster GKE"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "CA Certificate del cluster"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

# Comando para conectarse al cluster
output "gke_connection_command" {
  description = "Comando para conectarse al cluster con kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${var.zone} --project ${var.project_id}"
}

# -----------------------------------------------------------------------------
# Cloud SQL Outputs
# -----------------------------------------------------------------------------

output "db_instance_name" {
  description = "Nombre de la instancia de Cloud SQL"
  value       = google_sql_database_instance.main.name
}

output "db_private_ip" {
  description = "IP privada de Cloud SQL"
  value       = google_sql_database_instance.main.private_ip_address
}

output "db_connection_name" {
  description = "Connection name para Cloud SQL Proxy"
  value       = google_sql_database_instance.main.connection_name
}

output "db_name" {
  description = "Nombre de la base de datos"
  value       = google_sql_database.main.name
}

output "db_user" {
  description = "Usuario de la base de datos"
  value       = google_sql_user.app.name
}

# -----------------------------------------------------------------------------
# Secret Manager Outputs
# -----------------------------------------------------------------------------

output "secret_db_connection_id" {
  description = "ID del secreto con el connection string"
  value       = google_secret_manager_secret.db_connection.secret_id
}

# -----------------------------------------------------------------------------
# ArgoCD Outputs
# -----------------------------------------------------------------------------

output "argocd_namespace" {
  description = "Namespace donde esta instalado ArgoCD"
  value       = helm_release.argocd.namespace
}

output "argocd_server_url_command" {
  description = "Comando para obtener la URL del servidor ArgoCD"
  value       = "kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

output "argocd_initial_admin_password_command" {
  description = "Comando para obtener la contrasena inicial de admin"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}


# -----------------------------------------------------------------------------
# External Secrets Outputs
# -----------------------------------------------------------------------------
output "external_secrets_gsa_email" {
  description = "Email de la Service Account de External Secrets"
  value       = google_service_account.external_secrets.email
}

# -----------------------------------------------------------------------------
# Artifact Registry Outputs
# -----------------------------------------------------------------------------
output "artifact_registry_url" {
  description = "URL del Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.talana.repository_id}"
}

output "artifact_registry_image" {
  description = "Full image path para talana-backend"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.talana.repository_id}/talana-backend"
}