variable "project_id" {
  description = "El ID del proyecto de GCP"
  type        = string
}

variable "region" {
  description = "Región de despliegue"
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "Zona para el cluster"
  type        = string
  default     = "us-east1-b"
}