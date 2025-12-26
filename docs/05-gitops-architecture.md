# Arquitectura GitOps

Este documento describe el flujo GitOps completo del proyecto.

## Diagrama General

```mermaid
flowchart TB
    subgraph GitHub ["GitHub Repository"]
        direction TB
        APP["app/
        (Django Code)"]
        INFRA["infra/
        (Terraform)"]
        K8S["k8s/
        (Manifests)"]
    end

    subgraph Actions ["GitHub Actions"]
        direction TB
        BUILD["build-push.yml
        Build & Push Image"]
        TF["terraform.yml
        Plan & Apply"]
        BOOT["argocd-bootstrap.yml
        Initial Setup"]
    end

    subgraph GCP ["Google Cloud Platform"]
        direction TB
        AR["Artifact Registry
        Docker Images"]

        subgraph GKE ["GKE Cluster"]
            direction TB
            ARGO["ArgoCD
            GitOps Controller"]

            subgraph Apps ["Aplicaciones"]
                ESO["External Secrets
                Operator"]
                KONG["Kong
                Ingress"]
                CSS["ClusterSecretStore"]
                BACKEND["talana-backend
                (Deployment)"]
            end
        end

        SQL["Cloud SQL"]
        SM["Secret Manager"]
    end

    %% Triggers
    APP -->|"push"| BUILD
    INFRA -->|"push"| TF
    K8S -->|"push"| ARGO

    %% GitHub Actions flows
    BUILD -->|"docker push"| AR
    TF -->|"terraform apply"| GKE
    TF -->|"terraform apply"| SQL
    TF -->|"terraform apply"| SM
    BOOT -->|"kubectl apply"| ARGO

    %% ArgoCD syncs
    ARGO -->|"sync helm"| ESO
    ARGO -->|"sync helm"| KONG
    ARGO -->|"sync kustomize"| CSS
    ARGO -->|"sync kustomize"| BACKEND

    %% Dependencies
    AR -.->|"pull image"| BACKEND
    ESO -.->|"fetch secrets"| SM
    CSS -.->|"auth"| SM
    BACKEND -.->|"connect"| SQL
    KONG -->|"route traffic"| BACKEND

    %% Styling
    classDef github fill:#24292e,color:#fff
    classDef actions fill:#2088FF,color:#fff
    classDef gcp fill:#4285F4,color:#fff
    classDef k8s fill:#326CE5,color:#fff

    class APP,INFRA,K8S github
    class BUILD,TF,BOOT actions
    class AR,SQL,SM gcp
    class ARGO,ESO,KONG,CSS,BACKEND k8s
```

## Flujo por Tipo de Cambio

### 1. Cambios en Aplicacion (app/)

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant GA as GitHub Actions
    participant AR as Artifact Registry
    participant Argo as ArgoCD
    participant K8s as Kubernetes

    Dev->>GH: git push (app/)
    GH->>GA: Trigger build-push.yml
    GA->>GA: Build Docker image
    GA->>AR: Push image:sha
    GA->>GH: Update image tag in kustomization
    GH->>Argo: Webhook/Poll detect change
    Argo->>K8s: Sync Deployment
    K8s->>K8s: Rolling update
    Note over K8s: Pods updated
```

### 2. Cambios en Infraestructura (infra/)

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant GA as GitHub Actions
    participant GCP as GCP Resources

    Dev->>GH: git push (infra/)
    GH->>GA: Trigger terraform.yml
    GA->>GA: terraform init
    GA->>GA: terraform plan
    GA->>GCP: terraform apply
    Note over GCP: VPC, GKE, SQL, etc.
```

### 3. Cambios en Manifiestos K8s (k8s/)

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant Argo as ArgoCD
    participant K8s as Kubernetes

    Dev->>GH: git push (k8s/)
    GH->>Argo: Webhook/Poll detect change
    Argo->>Argo: Compare Git vs Cluster
    Argo->>K8s: Auto-sync changes
    Note over K8s: Resources updated
```

## ArgoCD Applications

```mermaid
flowchart LR
    subgraph ArgoCD ["ArgoCD (namespace: argocd)"]
        direction TB
        A2["external-secrets"]
        A3["kong"]
        A4["cluster-secret-store"]
        A5["talana-backend-dev"]
    end

    subgraph Sources ["Fuentes"]
        direction TB
        H2["Helm: external-secrets.io"]
        H3["Helm: charts.konghq.com"]
        G1["Git: k8s/infra/cluster-secret-store"]
        G2["Git: k8s/apps/talana-backend/overlays/dev"]
    end

    subgraph Namespaces ["Namespaces Destino"]
        direction TB
        N2["external-secrets"]
        N3["kong"]
        N4["external-secrets"]
        N5["talana-dev"]
    end

    H2 --> A2 --> N2
    H3 --> A3 --> N3
    G1 --> A4 --> N4
    G2 --> A5 --> N5
```

## Estructura de Directorios

```
talana-sre-challenge/
├── .github/workflows/
│   ├── terraform.yml        ──→ Cambios en infra/
│   ├── build-push.yml       ──→ Cambios en app/
│   └── argocd-bootstrap.yml ──→ Manual (una vez)
│
├── app/                     ──→ GitHub Actions (build-push)
│   ├── Dockerfile
│   └── ...
│
├── infra/                   ──→ GitHub Actions (terraform)
│   ├── *.tf
│   └── ...
│
└── k8s/                     ──→ ArgoCD (auto-sync)
    ├── argocd/              ──→ Bootstrap inicial
    │   ├── kong.yaml
    │   ├── infra.yaml
    │   ├── cluster-secret-store.yaml
    │   └── dev-env.yaml
    │
    ├── apps/
    │   └── talana-backend/
    │       ├── base/        ──→ Recursos comunes
    │       └── overlays/
    │           └── dev/     ──→ Configuracion dev
    │
    └── infra/
        ├── external-secrets/
        └── cluster-secret-store/
```

## Deployment Flow

```mermaid
flowchart LR
    subgraph Deployment ["Kubernetes Deployment"]
        direction TB
        R1["Pod 1"]
        R2["Pod 2"]
    end

    subgraph Service ["Service"]
        S1["talana-backend
        ClusterIP"]
    end

    subgraph Kong ["Kong Ingress"]
        LB["Load Balancer
        35.237.234.196"]
    end

    LB -->|"HTTP"| S1
    S1 -->|"Round Robin"| R1
    S1 -->|"Round Robin"| R2

    style R1 fill:#326CE5,color:#fff
    style R2 fill:#326CE5,color:#fff
```

## Webhook para Sync Instantaneo

ArgoCD esta configurado con un **webhook de GitHub** para sync instantaneo en lugar del polling por defecto (3 minutos).

```
GitHub Push → Webhook → ArgoCD → Sync (segundos)
```

**Configuracion:** GitHub repo → Settings → Webhooks

| Campo | Valor |
|-------|-------|
| Payload URL | `http://<ARGOCD_IP>/api/webhook` |
| Content type | `application/json` |
| Events | Just the push event |

El webhook notifica a todas las aplicaciones de ArgoCD. Solo se sincronizan las apps cuyos paths fueron modificados.

## Resumen de Automatizaciones

| Trigger | Pipeline | Accion |
|---------|----------|--------|
| Push a `app/**` | build-push.yml | Build image → Push → Update tag |
| Push a `infra/**` | terraform.yml | Plan → Apply |
| Push a `k8s/**` | ArgoCD | Auto-sync a cluster |
| Manual | argocd-bootstrap.yml | Aplicar apps ArgoCD |

## Enlaces Utiles

- **ArgoCD UI**: http://34.26.252.189
- **Kong API**: http://35.237.234.196
- **Artifact Registry**: us-east1-docker.pkg.dev/talana-sre-challenge-jesben/talana-repo
