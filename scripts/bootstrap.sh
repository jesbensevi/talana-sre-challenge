#!/bin/bash
#
# Talana SRE Challenge - Bootstrap Script
# This script sets up all GCP prerequisites from scratch:
# - Project creation/selection
# - API enablement
# - Terraform state bucket
# - Workload Identity Federation for GitHub Actions
#
# Usage: ./bootstrap.sh <PROJECT_ID> <GITHUB_REPO>
# Example: ./bootstrap.sh my-gcp-project jesben/talana-sre-challenge
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
    fi
}

# -----------------------------------------------------------------------------
# Validate Arguments
# -----------------------------------------------------------------------------

if [ $# -lt 2 ]; then
    echo "Usage: $0 <PROJECT_ID> <GITHUB_REPO>"
    echo "Example: $0 my-gcp-project jesben/talana-sre-challenge"
    exit 1
fi

PROJECT_ID="$1"
GITHUB_REPO="$2"
REGION="us-east1"
BUCKET_NAME="${PROJECT_ID}-tfstate"
SA_NAME="github-actions-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"

# Extract owner from repo
GITHUB_OWNER=$(echo "$GITHUB_REPO" | cut -d'/' -f1)

echo ""
echo "=============================================="
echo "  Talana SRE Challenge - Bootstrap"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Project ID:    $PROJECT_ID"
echo "  Region:        $REGION"
echo "  GitHub Repo:   $GITHUB_REPO"
echo "  State Bucket:  $BUCKET_NAME"
echo ""

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------

log_info "Checking prerequisites..."

check_command "gcloud"
check_command "gsutil"

log_success "All required tools are installed"

# -----------------------------------------------------------------------------
# GCP Authentication
# -----------------------------------------------------------------------------

log_info "Checking GCP authentication..."

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 | grep -q "@"; then
    log_warn "No active GCP account found. Initiating login..."
    gcloud auth login --no-launch-browser
else
    CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_success "Authenticated as: $CURRENT_ACCOUNT"
fi

# -----------------------------------------------------------------------------
# Project Setup
# -----------------------------------------------------------------------------

log_info "Checking if project '$PROJECT_ID' exists..."

if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
    log_success "Project '$PROJECT_ID' already exists"
else
    log_warn "Project '$PROJECT_ID' does not exist. Creating..."

    # Check if billing account is available
    BILLING_ACCOUNT=$(gcloud billing accounts list --filter=open=true --format="value(ACCOUNT_ID)" | head -n1)

    if [ -z "$BILLING_ACCOUNT" ]; then
        log_error "No billing account found. Please create a billing account first."
    fi

    gcloud projects create "$PROJECT_ID" --name="$PROJECT_ID"
    log_info "Linking billing account..."
    gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
    log_success "Project '$PROJECT_ID' created and billing linked"
fi

# Set the project
log_info "Setting active project to '$PROJECT_ID'..."
gcloud config set project "$PROJECT_ID"
log_success "Active project set"

# -----------------------------------------------------------------------------
# Enable Required APIs
# -----------------------------------------------------------------------------

log_info "Enabling required GCP APIs (this may take a few minutes)..."

APIS=(
    "iam.googleapis.com"
    "iamcredentials.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "sts.googleapis.com"
    "container.googleapis.com"
    "sqladmin.googleapis.com"
    "compute.googleapis.com"
    "servicenetworking.googleapis.com"
    "artifactregistry.googleapis.com"
    "secretmanager.googleapis.com"
)

for api in "${APIS[@]}"; do
    if gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
        log_success "API already enabled: $api"
    else
        log_info "Enabling API: $api"
        gcloud services enable "$api" --project="$PROJECT_ID"
        log_success "API enabled: $api"
    fi
done

# -----------------------------------------------------------------------------
# Create Terraform State Bucket
# -----------------------------------------------------------------------------

log_info "Checking Terraform state bucket..."

if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
    log_success "Bucket 'gs://${BUCKET_NAME}' already exists"
else
    log_info "Creating bucket 'gs://${BUCKET_NAME}'..."
    gsutil mb -p "$PROJECT_ID" -l "$REGION" -b on "gs://${BUCKET_NAME}"

    # Enable versioning for state protection
    gsutil versioning set on "gs://${BUCKET_NAME}"
    log_success "Bucket created with versioning enabled"
fi

# -----------------------------------------------------------------------------
# Create Service Account
# -----------------------------------------------------------------------------

log_info "Setting up Service Account for GitHub Actions..."

if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &> /dev/null; then
    log_success "Service Account '$SA_EMAIL' already exists"
else
    log_info "Creating Service Account..."
    gcloud iam service-accounts create "$SA_NAME" \
        --project="$PROJECT_ID" \
        --display-name="GitHub Actions Service Account" \
        --description="Service Account for GitHub Actions CI/CD"
    log_success "Service Account created"
fi

# Assign roles to Service Account
log_info "Assigning roles to Service Account..."

ROLES=(
    "roles/editor"
    "roles/iam.serviceAccountTokenCreator"
    "roles/servicenetworking.networksAdmin"
    "roles/secretmanager.admin"
    "roles/container.admin"
)

for role in "${ROLES[@]}"; do
    log_info "Assigning role: $role"
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="$role" \
        --condition=None \
        --quiet
done

log_success "Roles assigned to Service Account"

# -----------------------------------------------------------------------------
# Setup Workload Identity Federation
# -----------------------------------------------------------------------------

log_info "Setting up Workload Identity Federation..."

# Get Project Number (required for WIF paths)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
log_info "Project Number: $PROJECT_NUMBER"

# Create Workload Identity Pool
POOL_FULL_NAME="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}"

if gcloud iam workload-identity-pools describe "$POOL_NAME" \
    --project="$PROJECT_ID" \
    --location="global" &> /dev/null; then
    log_success "Workload Identity Pool '$POOL_NAME' already exists"
else
    log_info "Creating Workload Identity Pool..."
    gcloud iam workload-identity-pools create "$POOL_NAME" \
        --project="$PROJECT_ID" \
        --location="global" \
        --display-name="GitHub Actions Pool" \
        --description="Identity pool for GitHub Actions"
    log_success "Workload Identity Pool created"
    log_info "Waiting for pool to propagate..."
    sleep 10
fi

# Create Workload Identity Provider
if gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
    --project="$PROJECT_ID" \
    --location="global" \
    --workload-identity-pool="$POOL_NAME" &> /dev/null; then
    log_success "Workload Identity Provider '$PROVIDER_NAME' already exists"
else
    log_info "Creating Workload Identity Provider..."
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
        --project="$PROJECT_ID" \
        --location="global" \
        --workload-identity-pool="$POOL_NAME" \
        --display-name="GitHub OIDC Provider" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
        --attribute-condition="assertion.repository_owner == '${GITHUB_OWNER}'"
    log_success "Workload Identity Provider created"
    log_info "Waiting for provider to propagate..."
    sleep 10
fi

# Bind Service Account to Workload Identity
log_info "Binding Service Account to Workload Identity..."

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/${POOL_FULL_NAME}/attribute.repository/${GITHUB_REPO}" \
    --quiet

log_success "Workload Identity binding configured"

# -----------------------------------------------------------------------------
# Get Workload Identity Provider Full Path
# -----------------------------------------------------------------------------

WIF_PROVIDER=$(gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
    --project="$PROJECT_ID" \
    --location="global" \
    --workload-identity-pool="$POOL_NAME" \
    --format="value(name)")

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "=============================================="
echo -e "${GREEN}  Bootstrap Complete!${NC}"
echo "=============================================="
echo ""
echo "Resources Created:"
echo "  - Project: $PROJECT_ID"
echo "  - Terraform State Bucket: gs://${BUCKET_NAME}"
echo "  - Service Account: $SA_EMAIL"
echo "  - Workload Identity Pool: $POOL_NAME"
echo "  - Workload Identity Provider: $PROVIDER_NAME"
echo ""
echo "=============================================="
echo "  GitHub Secrets Configuration"
echo "=============================================="
echo ""
echo "Add these secrets to your GitHub repository:"
echo ""
echo -e "${YELLOW}GCP_PROJECT_ID:${NC}"
echo "$PROJECT_ID"
echo ""
echo -e "${YELLOW}GCP_WORKLOAD_IDENTITY_PROVIDER:${NC}"
echo "$WIF_PROVIDER"
echo ""
echo -e "${YELLOW}GCP_SERVICE_ACCOUNT:${NC}"
echo "$SA_EMAIL"
echo ""
echo "=============================================="
echo "  Next Steps"
echo "=============================================="
echo ""
echo "1. Add the above secrets to GitHub:"
echo "   https://github.com/${GITHUB_REPO}/settings/secrets/actions"
echo ""
echo "2. Update infra/backend.tf with your bucket name:"
echo "   bucket = \"${BUCKET_NAME}\""
echo ""
echo "3. Create terraform.tfvars in infra/:"
echo "   project_id = \"${PROJECT_ID}\""
echo "   region     = \"${REGION}\""
echo ""
echo "4. Initialize and apply Terraform:"
echo "   cd infra && terraform init && terraform plan"
echo ""
