# Talana SRE Challenge

Infraestructura completa en Google Cloud Platform para desplegar una aplicacion Django en Kubernetes usando GitOps con ArgoCD.

## Arquitectura

```mermaid
graph TD
    %% Estilos
    classDef gcp fill:#e8f0fe,stroke:#4285f4,stroke-width:2px;
    classDef node fill:#e6f2ff,stroke:#326ce5,stroke-width:2px,stroke-dasharray: 5 5;
    classDef pod fill:#326ce5,stroke:#fff,stroke-width:1px,color:white;
    classDef db fill:#fff,stroke:#db4437,stroke-width:2px;
    classDef ext fill:#fbbc04,stroke:#333,stroke-width:2px;

    User((Usuario Internet)):::ext
    GH_Actions("GitHub Actions (CI/CD)"):::ext

    subgraph GCP ["Google Cloud Platform"]
        style GCP fill:#f9f9f9,stroke:#999

        LB["Google Cloud L4 Load Balancer"]:::gcp
        WIF["Workload Identity Federation"]:::gcp

        subgraph VPC ["VPC: talana-vpc"]
            NAT["Cloud NAT (Salida Internet)"]:::gcp

            subgraph GKE ["GKE Cluster (Privado)"]
                style GKE fill:#fff,stroke:#326ce5

                subgraph Node1 ["Nodo Worker"]
                    class Node1 node
                    Kong1("Kong Proxy"):::pod
                    AppBlue1("Django (Pod 1)"):::pod
                    AppBlue2("Django (Pod 2)"):::pod
                end
            end

            subgraph Database ["Capa de Datos"]
                SQL[("Cloud SQL (PostgreSQL)<br/>Solo IP Privada")]:::db
            end
        end
    end

    User -->|HTTPS| LB
    LB -->|TCP| Kong1

    Kong1 -->|Internal Routing| AppBlue1
    Kong1 -->|Internal Routing| AppBlue2

    AppBlue1 -->|Private Access :5432| SQL
    AppBlue2 -->|Private Access :5432| SQL

    GH_Actions -.->|1. Auth OIDC| WIF
    GH_Actions -.->|2. Deploy K8s| GKE
    Node1 -.->|Pull Image/Updates| NAT
```

## Stack Tecnologico

| Componente | Tecnologia |
|------------|------------|
| Cloud | Google Cloud Platform |
| IaC | Terraform 1.6+ |
| Container Orchestration | GKE (Google Kubernetes Engine) |
| GitOps | ArgoCD |
| Progressive Delivery | Argo Rollouts (Canary Deployments) |
| CI/CD | GitHub Actions + Workload Identity Federation |
| API Gateway | Kong + Gateway API |
| Secrets | External Secrets Operator + GCP Secret Manager |
| Base de Datos | Cloud SQL PostgreSQL 15 |
| Aplicacion | Django 5.0 + Gunicorn |
| Container Registry | Artifact Registry |

## Estructura del Proyecto

```
talana-sre-challenge/
├── .github/workflows/
│   ├── terraform.yml          # CI/CD para infraestructura
│   ├── build-push.yml         # CI/CD para aplicacion
│   └── argocd-bootstrap.yml   # Setup inicial de ArgoCD
├── app/                       # Aplicacion Django
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── manage.py
│   ├── talana/               # Proyecto Django (config)
│   └── api/                  # App de endpoints
├── infra/                    # Terraform (IaC)
│   ├── provider.tf
│   ├── vpc.tf
│   ├── gke.tf
│   ├── database.tf
│   ├── argocd.tf
│   ├── artifact-registry.tf
│   └── secrets.tf
├── k8s/                      # Manifiestos Kubernetes (Kustomize)
│   ├── apps/
│   │   └── talana-backend/
│   │       ├── base/         # deployment, service, ingress, kong-plugins
│   │       └── overlays/dev/
│   ├── infra/
│   │   ├── external-secrets/
│   │   └── cluster-secret-store/
│   └── argocd/               # ArgoCD Applications (kong, infra, backend)
├── scripts/
│   └── bootstrap.sh          # Script de setup inicial
└── docs/
    ├── 01-bootstrap.md
    ├── 02-argocd.md
    ├── 03-production-improvements.md
    ├── 04-kong.md
    └── 05-gitops-architecture.md
```

## Quick Start

### Prerequisitos

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.6
- Cuenta de GCP con billing habilitado
- Repositorio en GitHub

### Paso 1: Bootstrap del Proyecto

El script de bootstrap configura todo el proyecto de GCP desde cero:

```bash
# Clonar el repositorio
git clone https://github.com/jesbensevi/talana-sre-ch.git
cd talana-sre-ch

# Ejecutar bootstrap
./scripts/bootstrap.sh <PROJECT_ID> <GITHUB_REPO>

# Ejemplo:
./scripts/bootstrap.sh talana-sre-challenge-jesben jesbensevi/talana-sre-ch
```

**El script automatiza:**
- Creacion/seleccion del proyecto GCP
- Habilitacion de APIs necesarias
- Creacion del bucket para Terraform state
- Service Account para GitHub Actions
- Workload Identity Federation (autenticacion sin keys)

### Paso 2: Configurar GitHub Secrets

Despues de ejecutar el bootstrap, agrega estos secrets en GitHub:

| Secret | Descripcion |
|--------|-------------|
| `GCP_PROJECT_ID` | ID del proyecto GCP |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Path del WIF provider |
| `GCP_SERVICE_ACCOUNT` | Email del Service Account |

Configurar en: `Settings > Secrets and variables > Actions`

### Paso 3: Deploy de Infraestructura

```bash
# Push a main para aplicar Terraform
git push origin main
```

GitHub Actions ejecutara automaticamente:
- `terraform plan` en PRs
- `terraform apply` en push a main

### Paso 4: Bootstrap de ArgoCD (Una sola vez)

Una vez que la infraestructura este desplegada, ejecutar el workflow de ArgoCD:

1. Ir a **Actions** en GitHub
2. Seleccionar **"ArgoCD Bootstrap"**
3. Click en **"Run workflow"**
4. Seleccionar action: **"apply"**

Este paso registra las aplicaciones en ArgoCD para que comience el despliegue GitOps.

## Flujo CI/CD

```mermaid
flowchart TB
    subgraph Trigger ["Cambios en Codigo"]
        INFRA["infra/**"]
        APP["app/**"]
        K8S["k8s/**"]
        K8SARGO["k8s/argocd/**"]
    end

    subgraph Actions ["GitHub Actions"]
        TF["terraform.yml<br/>Plan → Apply"]
        BUILD["build-push.yml<br/>Build → Push"]
        BOOT["argocd-bootstrap.yml<br/>kubectl apply"]
    end

    subgraph ArgoCD ["ArgoCD"]
        SYNC["Auto-sync"]
    end

    subgraph Results ["Resultados"]
        GCP["GCP Infra<br/>Updated"]
        AR["Artifact Registry<br/>Image Pushed"]
        GKE["GKE Cluster<br/>Deployed"]
    end

    INFRA --> TF --> GCP
    APP --> BUILD --> AR
    K8S --> SYNC --> GKE
    K8SARGO --> BOOT --> SYNC

    style Trigger fill:#24292e,color:#fff
    style Actions fill:#2088FF,color:#fff
    style ArgoCD fill:#EF7B4D,color:#fff
```

## Endpoints de la Aplicacion

| Endpoint | Descripcion |
|----------|-------------|
| `/` | Info del API |
| `/api/*` | Endpoints de la aplicacion |
| `/health` | Liveness probe |
| `/ready` | Readiness probe + conexion BD |

## Kong Ingress Controller

Kong actua como API Gateway con configuracion optimizada para el challenge (1 replica, recursos limitados).

### Plugins Configurados

| Plugin | Configuracion |
|--------|---------------|
| **Rate Limiting** | 100 req/min, 1000 req/hora por IP |
| **CORS** | Permite todos los origenes (configurable) |
| **Request Size** | Maximo 10 MB por request |

### Acceso

```bash
# Obtener IP externa de Kong
kubectl -n kong get svc kong-kong-proxy

# Ver logs de Kong
kubectl -n kong logs -l app.kubernetes.io/name=kong
```

> Ver [docs/03-production-improvements.md](docs/03-production-improvements.md) para configuracion de HA y produccion.

## Acceso a ArgoCD

```bash
# Obtener IP externa
kubectl -n argocd get svc argocd-server

# Obtener password de admin
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d; echo
```

- **URL**: `http://<EXTERNAL-IP>`
- **Usuario**: `admin`
- **Password**: (obtenido con el comando anterior)

## URLs de Acceso

| Servicio | URL | Descripcion |
|----------|-----|-------------|
| ArgoCD UI | http://34.26.252.189 | Panel GitOps |
| Kong API Gateway | http://35.237.234.196 | Trafico de aplicacion |
| Argo Rollouts Dashboard | http://34.73.161.251:3100 | Visualizacion canary deployments |

## Documentacion Adicional

- [00 - Setup Guide (Desplegar desde cero)](docs/00-setup-guide.md)
- [01 - Bootstrap Guide](docs/01-bootstrap.md)
- [02 - ArgoCD Guide](docs/02-argocd.md)
- [03 - Production Improvements](docs/03-production-improvements.md)
- [04 - Kong API Gateway](docs/04-kong.md)
- [05 - GitOps Architecture](docs/05-gitops-architecture.md)
- [06 - Canary Deployments](docs/06-canary-deployments.md)
- [07 - Billing y Costos](docs/07-billing.md)

## Roles IAM del Service Account

| Rol | Proposito |
|-----|-----------|
| `roles/editor` | Recursos generales de GCP |
| `roles/iam.serviceAccountTokenCreator` | Generar tokens |
| `roles/iam.serviceAccountAdmin` | Gestionar Service Accounts |
| `roles/servicenetworking.networksAdmin` | VPC peering |
| `roles/secretmanager.admin` | Secret Manager |
| `roles/container.admin` | GKE + RBAC |
| `roles/artifactregistry.admin` | Artifact Registry |

## Recursos Creados

### Networking
- VPC con subnet privada (10.10.0.0/24)
- Cloud NAT para salida a internet
- Private Service Connection para Cloud SQL
- **3 Load Balancers L4** (configuracion actual para el challenge):
  - Kong API Gateway (trafico de aplicacion)
  - ArgoCD UI (panel de administracion)
  - Argo Rollouts Dashboard (visualizacion de canary deployments)

> Ver [docs/03-production-improvements.md](docs/03-production-improvements.md) para consolidar en un solo LB.

### Compute
- GKE Cluster privado (2 nodos e2-standard-2)
- Workload Identity habilitado

### Data
- Cloud SQL PostgreSQL 15 (IP privada)
- Secret Manager para credenciales

### CI/CD
- Artifact Registry para imagenes Docker
- Workload Identity Federation para GitHub Actions

---

**Talana SRE Challenge** - Infrastructure as Code + GitOps
