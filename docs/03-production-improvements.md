# Mejoras para Produccion

Este documento lista las mejoras recomendadas para llevar esta infraestructura a un ambiente productivo.

## Kong Ingress Controller

### Configuracion Actual (Challenge)
- 1 replica
- Recursos limitados (50m CPU, 128Mi RAM)
- Sin PodDisruptionBudget

### Configuracion Recomendada (Produccion)

```yaml
# En k8s/argocd/kong.yaml - helm.valuesObject
replicaCount: 2  # Minimo 2 para HA

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi

podDisruptionBudget:
  enabled: true
  minAvailable: 1

# Anti-affinity para distribuir replicas en diferentes nodos
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: kong
          topologyKey: kubernetes.io/hostname
```

## Consolidacion de Load Balancers

### Configuracion Actual (Challenge)
- 2 Load Balancers L4 separados (~$36/mes):
  - Kong API Gateway (trafico de aplicacion)
  - ArgoCD UI (panel de administracion)

### Configuracion Recomendada (Produccion)

Usar un solo Load Balancer con Kong como unico punto de entrada, ruteando por subdominios:

```yaml
# k8s/apps/argocd-ingress/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    konghq.com/strip-path: "false"
    konghq.com/protocols: "https"
spec:
  ingressClassName: kong
  tls:
    - hosts:
        - argocd.example.com
      secretName: argocd-tls
  rules:
    - host: argocd.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
---
# k8s/apps/talana-backend/base/ingress.yaml (actualizado)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: talana-backend
  annotations:
    konghq.com/plugins: rate-limit-backend
spec:
  ingressClassName: kong
  tls:
    - hosts:
        - api.example.com
      secretName: api-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: talana-backend
                port:
                  number: 80
```

**Pasos para migrar:**

1. Cambiar ArgoCD Service de `LoadBalancer` a `ClusterIP`:
   ```yaml
   # En k8s/argocd/argocd-values.yaml o via Terraform
   server:
     service:
       type: ClusterIP
   ```

2. Crear Ingress para ArgoCD a traves de Kong

3. Configurar DNS:
   - `api.example.com` → IP de Kong
   - `argocd.example.com` → IP de Kong

4. Configurar TLS con cert-manager

**Ahorro:** ~$18/mes (1 LB menos)

## GKE Cluster

### Configuracion Actual
- 1 nodo preemptible (e2-standard-2)
- Single zone (us-east1-b)

### Configuracion Recomendada

```hcl
# Multi-zone para HA
location = "us-east1"  # Regional en lugar de zonal

node_pool {
  initial_node_count = 1

  autoscaling {
    min_node_count = 2
    max_node_count = 10
  }

  node_config {
    preemptible  = false  # Nodos on-demand para produccion
    machine_type = "e2-standard-4"

    # Nodos en multiples zonas automaticamente
  }
}
```

## Base de Datos (Cloud SQL)

### Configuracion Actual
- db-f1-micro (compartido)
- Sin HA
- Sin backups automaticos

### Configuracion Recomendada

```hcl
resource "google_sql_database_instance" "main" {
  database_version = "POSTGRES_15"

  settings {
    tier              = "db-custom-2-4096"  # 2 vCPU, 4GB RAM
    availability_type = "REGIONAL"          # HA con failover automatico

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"

      backup_retention_settings {
        retained_backups = 30
      }
    }

    maintenance_window {
      day  = 7  # Domingo
      hour = 4  # 4 AM
    }
  }
}
```

## Seguridad

### Mejoras Recomendadas

1. **TLS/HTTPS**
   ```yaml
   # Kong con certificados
   proxy:
     tls:
       enabled: true
     annotations:
       # Usar cert-manager para certificados automaticos
       cert-manager.io/cluster-issuer: letsencrypt-prod
   ```

2. **Network Policies**
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: backend-netpol
   spec:
     podSelector:
       matchLabels:
         app: talana-backend
     ingress:
       - from:
           - namespaceSelector:
               matchLabels:
                 name: kong
     egress:
       - to:
           - ipBlock:
               cidr: 10.10.0.0/24  # Solo Cloud SQL
   ```

3. **Pod Security Standards**
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 1000
     readOnlyRootFilesystem: true
     allowPrivilegeEscalation: false
   ```

## Observabilidad

### Monitoreo Recomendado

1. **Prometheus + Grafana**
   ```yaml
   # ArgoCD Application para kube-prometheus-stack
   source:
     repoURL: https://prometheus-community.github.io/helm-charts
     chart: kube-prometheus-stack
   ```

2. **Kong Metrics**
   ```yaml
   # Habilitar metricas en Kong
   env:
     prometheus_metrics: "on"
   ```

3. **Cloud Logging/Monitoring**
   - Habilitar GKE logging nativo
   - Crear alertas en Cloud Monitoring

## Rate Limiting

### Configuracion Actual
- 100 req/min, 1000 req/hora (local policy)

### Configuracion Recomendada (Produccion)

```yaml
# Usar Redis para rate limiting distribuido
plugin: rate-limiting
config:
  minute: 60
  hour: 1000
  policy: redis
  redis_host: redis.redis.svc.cluster.local
  redis_port: 6379
  redis_timeout: 2000
  fault_tolerant: true
```

## CI/CD

### Mejoras Recomendadas

1. **Ambientes separados**
   - dev, staging, production con diferentes clusters
   - Promocion manual a produccion

2. **Canary/Blue-Green Deployments**
   ```yaml
   # Argo Rollouts para despliegues progresivos
   apiVersion: argoproj.io/v1alpha1
   kind: Rollout
   spec:
     strategy:
       canary:
         steps:
           - setWeight: 20
           - pause: {duration: 5m}
           - setWeight: 50
           - pause: {duration: 10m}
   ```

3. **Image Scanning**
   - Integrar Trivy o Snyk en el pipeline
   - Bloquear imagenes con vulnerabilidades criticas

## Costos Estimados (Produccion)

| Recurso | Configuracion | Costo Mensual Estimado |
|---------|---------------|------------------------|
| GKE Cluster | Regional, 3 nodos e2-standard-4 | ~$300 |
| Cloud SQL | db-custom-2-4096, HA | ~$150 |
| Load Balancer | 1 regional | ~$20 |
| Cloud NAT | 1 gateway | ~$35 |
| **Total** | | **~$505/mes** |

---

Estas mejoras deben implementarse gradualmente segun las necesidades del proyecto y el presupuesto disponible.
