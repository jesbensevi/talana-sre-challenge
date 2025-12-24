# Bootstrap Inicial - Talana SRE Challenge

Este documento describe los pasos para configurar el entorno inicial del proyecto desde cero.

## Prerrequisitos

### 1. Instalar Google Cloud SDK

**macOS (Homebrew):**
```bash
brew install --cask google-cloud-sdk
```

**Linux (Debian/Ubuntu):**
```bash
# Agregar el repositorio de Google Cloud
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

sudo apt-get update && sudo apt-get install google-cloud-sdk
```

**Windows:**
Descargar el instalador desde: https://cloud.google.com/sdk/docs/install

### 2. Verificar instalación

```bash
gcloud version
```

## Autenticación en GCP

### 1. Login interactivo

```bash
gcloud auth login
```

Esto abrirá el navegador para autenticarte con tu cuenta de Google.

### 2. Verificar autenticación

```bash
gcloud auth list
```

Deberías ver tu cuenta marcada como activa.

## Ejecutar Bootstrap

### 1. Dar permisos de ejecución al script

```bash
chmod +x scripts/bootstrap.sh
```

### 2. Ejecutar el bootstrap

```bash
./scripts/bootstrap.sh <PROJECT_ID> <GITHUB_REPO>
```

**Ejemplo para este proyecto:**
```bash
./scripts/bootstrap.sh talana-sre-challenge-jesben jesbensevi/talana-sre-challenge
```

## Qué hace el Bootstrap

El script `bootstrap.sh` automatiza la configuración inicial:

| Paso | Descripción |
|------|-------------|
| 1 | Verifica que `gcloud` esté instalado |
| 2 | Verifica autenticación en GCP |
| 3 | Crea el proyecto GCP si no existe |
| 4 | Vincula la cuenta de facturación |
| 5 | Habilita las APIs necesarias |
| 6 | Crea el bucket para Terraform state |
| 7 | Crea la Service Account para GitHub Actions |
| 8 | Configura Workload Identity Federation |
| 9 | Muestra los valores para GitHub Secrets |

### APIs habilitadas

- `iam.googleapis.com`
- `iamcredentials.googleapis.com`
- `cloudresourcemanager.googleapis.com`
- `sts.googleapis.com`
- `container.googleapis.com` (GKE)
- `sqladmin.googleapis.com` (Cloud SQL)
- `compute.googleapis.com`
- `servicenetworking.googleapis.com`
- `artifactregistry.googleapis.com`

### Recursos creados

- **Bucket GCS**: `${PROJECT_ID}-tfstate` (para Terraform state)
- **Service Account**: `github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com`
- **Workload Identity Pool**: `github-pool`
- **Workload Identity Provider**: `github-provider`

## Configurar GitHub Secrets

Después de ejecutar el bootstrap, agregar estos secrets en GitHub:

**Repositorio → Settings → Secrets and variables → Actions**

| Secret Name | Valor |
|-------------|-------|
| `GCP_PROJECT_ID` | `talana-sre-challenge-jesben` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | (output del script) |
| `GCP_SERVICE_ACCOUNT` | `github-actions-sa@talana-sre-challenge-jesben.iam.gserviceaccount.com` |

## Siguientes Pasos

1. Configurar los secrets en GitHub
2. Actualizar `infra/backend.tf` con el nombre del bucket
3. Crear `infra/terraform.tfvars` con las variables
4. Ejecutar Terraform para la infraestructura principal

```bash
cd infra
terraform init
terraform plan
```

## (Opcional) Conectarse al Cluster GKE

Si deseas conectarte al cluster GKE desde tu terminal local, necesitas instalar el plugin de autenticación:

### 1. Instalar el plugin

```bash
gcloud components install gke-gcloud-auth-plugin
```

### 2. Configurar la variable de entorno

Agregar a tu `~/.zshrc` o `~/.bashrc`:

```bash
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
```

Luego recargar:

```bash
source ~/.zshrc  # o source ~/.bashrc
```

### 3. Obtener credenciales del cluster

```bash
gcloud container clusters get-credentials talana-gke-cluster \
    --zone us-east1-b \
    --project talana-sre-challenge-jesben
```

### 4. Verificar conexión

```bash
kubectl get nodes
```

Deberías ver los nodos del cluster:

```
NAME                                              STATUS   ROLES    AGE   VERSION
gke-talana-gke-cluster-talana-node-pool-xxxxx     Ready    <none>   Xm    v1.xx.x
gke-talana-gke-cluster-talana-node-pool-xxxxx     Ready    <none>   Xm    v1.xx.x
```
