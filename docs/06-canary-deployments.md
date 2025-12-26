# Canary Deployments con Argo Rollouts

Este documento describe la implementacion de despliegues Canary usando Argo Rollouts integrado con Kong.

## Arquitectura

```
                    ┌─────────────────────────────────────┐
                    │           Kong Ingress              │
                    │         (Traffic Split)             │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
           ┌────────▼────────┐          ┌────────▼────────┐
           │  Stable Service │          │  Canary Service │
           │     (90%)       │          │     (10%)       │
           └────────┬────────┘          └────────┬────────┘
                    │                             │
           ┌────────▼────────┐          ┌────────▼────────┐
           │   Pods v1.0.2   │          │   Pods v1.0.3   │
           │   (Produccion)  │          │   (Nueva ver.)  │
           └─────────────────┘          └─────────────────┘
```

## Componentes

### 1. Argo Rollouts Controller

Instalado via ArgoCD Application:

```yaml
# k8s/argocd/argo-rollouts.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-rollouts
  namespace: argocd
spec:
  source:
    repoURL: https://argoproj.github.io/argo-helm
    chart: argo-rollouts
    targetRevision: 2.35.1
```

### 2. Rollout (reemplaza Deployment)

```yaml
# k8s/apps/talana-backend/base/rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: talana-backend
spec:
  strategy:
    canary:
      canaryService: talana-backend-canary
      stableService: talana-backend-stable
      steps:
        - setWeight: 10
        - pause: {duration: 1m}
        - setWeight: 25
        - pause: {duration: 2m}
        - setWeight: 50
        - pause: {duration: 2m}
        - setWeight: 75
        - pause: {duration: 2m}
      trafficRouting:
        kong:
          ingress: talana-backend
```

### 3. Services

Se requieren 3 services:

| Service | Proposito |
|---------|-----------|
| `talana-backend-stable` | Recibe trafico de produccion |
| `talana-backend-canary` | Recibe trafico de prueba |
| `talana-backend` | Service root para Argo Rollouts |

## Flujo de Canary Deployment

```
┌──────────────────────────────────────────────────────────────────────┐
│                         NUEVO DEPLOYMENT                              │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Paso 1: 10% trafico al canary                                        │
│ - Se crean nuevos pods con la nueva version                          │
│ - Kong enruta 10% del trafico a canary service                       │
│ - Pausa: 1 minuto para observar metricas                             │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Paso 2: 25% trafico al canary                                        │
│ - Si todo OK, incrementa a 25%                                       │
│ - Pausa: 2 minutos                                                   │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Paso 3: 50% trafico al canary                                        │
│ - Mitad del trafico va a la nueva version                            │
│ - Pausa: 2 minutos                                                   │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Paso 4: 75% trafico al canary                                        │
│ - Mayoria del trafico en nueva version                               │
│ - Pausa: 2 minutos                                                   │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Paso 5: 100% - Promocion completa                                    │
│ - Todo el trafico va a la nueva version                              │
│ - Pods antiguos se eliminan                                          │
│ - Rollout completado                                                 │
└──────────────────────────────────────────────────────────────────────┘
```

## Comandos Utiles

### Instalar kubectl plugin

```bash
# macOS
brew install argoproj/tap/kubectl-argo-rollouts

# Linux
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```

### Ver estado del rollout

```bash
# Estado actual
kubectl argo rollouts get rollout talana-backend -n talana-dev

# Watch en tiempo real
kubectl argo rollouts get rollout talana-backend -n talana-dev -w
```

### Promover manualmente

```bash
# Avanzar al siguiente paso
kubectl argo rollouts promote talana-backend -n talana-dev

# Promover completamente (skip all pauses)
kubectl argo rollouts promote talana-backend -n talana-dev --full
```

### Abortar/Rollback

```bash
# Abortar canary y volver a stable
kubectl argo rollouts abort talana-backend -n talana-dev

# Deshacer a revision anterior
kubectl argo rollouts undo talana-backend -n talana-dev
```

### Ver historial

```bash
kubectl argo rollouts history talana-backend -n talana-dev
```

## Dashboard de Argo Rollouts

### Acceder al Dashboard

```bash
# Port-forward al dashboard
kubectl port-forward svc/argo-rollouts-dashboard 3100:3100 -n argo-rollouts

# Abrir en navegador
open http://localhost:3100
```

### Funcionalidades del Dashboard

- Visualizacion del estado de rollouts
- Promocion/abort manual
- Historial de revisiones
- Metricas en tiempo real

## Integracion con Kong

Argo Rollouts modifica automaticamente las anotaciones del Ingress de Kong para realizar traffic splitting:

```yaml
# Durante canary (ejemplo: 25% canary)
metadata:
  annotations:
    konghq.com/override: |
      {
        "service": {
          "upstream": {
            "targets": [
              {"target": "talana-backend-stable.talana-dev.svc:80", "weight": 75},
              {"target": "talana-backend-canary.talana-dev.svc:80", "weight": 25}
            ]
          }
        }
      }
```

## Mejoras Futuras

### 1. Analysis Templates (Rollback automatico)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  metrics:
    - name: success-rate
      interval: 30s
      successCondition: result >= 0.95
      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            sum(rate(http_requests_total{status=~"2.*"}[1m])) /
            sum(rate(http_requests_total[1m]))
```

### 2. Notificaciones

Integrar con Slack/Teams para notificar sobre:
- Inicio de canary
- Promociones
- Rollbacks

### 3. Metricas Custom

Definir metricas de negocio para rollback automatico:
- Latencia p99
- Tasa de errores
- Conversion rate

## Troubleshooting

### Rollout stuck en "Paused"

```bash
# Ver eventos
kubectl describe rollout talana-backend -n talana-dev

# Promover manualmente si es intencional
kubectl argo rollouts promote talana-backend -n talana-dev
```

### Traffic no se divide correctamente

```bash
# Verificar servicios
kubectl get svc -n talana-dev

# Verificar endpoints
kubectl get endpoints -n talana-dev

# Ver configuracion de Kong
kubectl describe ingress talana-backend -n talana-dev
```

### Pods canary no inician

```bash
# Ver pods
kubectl get pods -n talana-dev -l app=talana-backend

# Ver logs del rollout controller
kubectl logs -n argo-rollouts -l app.kubernetes.io/name=argo-rollouts
```

## Referencias

- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [Kong Traffic Routing](https://argoproj.github.io/argo-rollouts/features/traffic-management/kong/)
- [Analysis & Progressive Delivery](https://argoproj.github.io/argo-rollouts/features/analysis/)
