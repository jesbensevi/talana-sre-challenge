# ArgoCD - GitOps Continuous Delivery

ArgoCD es una herramienta declarativa de GitOps para Kubernetes que permite mantener sincronizados los manifiestos de Kubernetes con un repositorio Git.

## Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                        GitHub Repo                          │
│                    (k8s/ manifiestos)                       │
└─────────────────────────────┬───────────────────────────────┘
                              │ sync
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         ArgoCD                              │
│                   (namespace: argocd)                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Server    │  │ Repo Server │  │ Application Ctrl    │  │
│  │ (UI + API)  │  │  (Git sync) │  │ (reconciliation)    │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────┬───────────────────────────────┘
                              │ deploy
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      GKE Cluster                            │
│              (talana-gke-cluster)                           │
└─────────────────────────────────────────────────────────────┘
```

## Instalacion

ArgoCD se instala automaticamente via Terraform usando el Helm chart oficial.

**Archivo:** `infra/argocd.tf`

```hcl
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.51.6"

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }
}
```

## Acceso a ArgoCD

### 1. Conectarse al cluster GKE

```bash
gcloud container clusters get-credentials talana-gke-cluster \
    --zone us-east1-b \
    --project talana-sre-challenge-jesben
```

### 2. Obtener la IP externa del servidor

```bash
kubectl -n argocd get svc argocd-server
```

Output esperado:
```
NAME            TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)                      AGE
argocd-server   LoadBalancer   10.30.10.123   34.26.252.189   80:31234/TCP,443:31235/TCP   5m
```

### 3. Obtener la contrasena del admin

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d; echo
```

### 4. Acceder a la UI

1. Abre el navegador en: `http://<EXTERNAL-IP>`
2. Usuario: `admin`
3. Contrasena: (la obtenida en el paso anterior)

## Comandos Utiles

### Ver todos los recursos de ArgoCD

```bash
kubectl -n argocd get all
```

### Ver logs del servidor

```bash
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-server -f
```

### Ver aplicaciones desplegadas

```bash
kubectl -n argocd get applications
```

### Reinstalar ArgoCD (si es necesario)

```bash
# Desde el directorio infra/
terraform taint helm_release.argocd
terraform apply
```

## Crear una Aplicacion en ArgoCD

### Via UI

1. Click en **+ NEW APP**
2. Configurar:
   - **Application Name:** `mi-app`
   - **Project:** `default`
   - **Sync Policy:** `Automatic`
   - **Repository URL:** `https://github.com/tu-usuario/tu-repo`
   - **Path:** `k8s/`
   - **Cluster URL:** `https://kubernetes.default.svc`
   - **Namespace:** `default`
3. Click en **CREATE**

### Via CLI (argocd)

```bash
# Instalar CLI
brew install argocd

# Login
argocd login <EXTERNAL-IP> --username admin --password <PASSWORD> --insecure

# Crear aplicacion
argocd app create mi-app \
    --repo https://github.com/tu-usuario/tu-repo \
    --path k8s \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace default \
    --sync-policy automated
```

### Via Manifest (recomendado para GitOps)

```yaml
# k8s/argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mi-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/tu-usuario/tu-repo
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Seguridad

### Cambiar contrasena del admin

```bash
argocd account update-password \
    --current-password <CURRENT> \
    --new-password <NEW>
```

### Deshabilitar usuario admin (produccion)

En `argocd.tf`, agregar:

```hcl
set {
  name  = "configs.params.server\\.disable\\.auth"
  value = "false"
}

set {
  name  = "configs.cm.admin\\.enabled"
  value = "false"
}
```

## Troubleshooting

### Error: "Unable to connect to the server"

Verificar que el cluster este accesible:
```bash
kubectl cluster-info
```

### Error: "permission denied"

Verificar que el Service Account tenga `roles/container.admin`:
```bash
gcloud projects get-iam-policy talana-sre-challenge-jesben \
    --flatten="bindings[].members" \
    --filter="bindings.members:github-actions-sa@"
```

### ArgoCD no sincroniza

1. Verificar conectividad al repo:
   ```bash
   argocd repo list
   ```

2. Ver eventos de la aplicacion:
   ```bash
   argocd app get mi-app
   ```

## Referencias

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Argo Helm Charts](https://github.com/argoproj/argo-helm)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
