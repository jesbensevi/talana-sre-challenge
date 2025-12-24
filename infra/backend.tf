
terraform {
  backend "gcs" {
    bucket = "talana-sre-challenge-jesben-tfstate"
    prefix = "terraform/state"
  }
}
