# Canary Deployments con Argo Rollouts

Este proyecto utiliza Argo Rollouts para implementar despliegues canary progresivos.

## Arquitectura

```
                    ┌─────────────────┐
                    │   Kong Ingress  │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
    ┌─────────────────┐           ┌─────────────────┐
    │ Service: stable │           │ Service: canary │
    │  (talana-backend)│           │(talana-backend- │
    │                 │           │     canary)     │
    └────────┬────────┘           └────────┬────────┘
             │                             │
             ▼                             ▼
    ┌─────────────────┐           ┌─────────────────┐
    │   Pods Stable   │           │   Pods Canary   │
    │   (version N)   │           │  (version N+1)  │
    └─────────────────┘           └─────────────────┘
```

## Estrategia Canary Configurada

El rollout sigue estos pasos:

| Paso | Accion | Trafico Canary |
|------|--------|----------------|
| 1 | setWeight: 20 | 20% |
| 2 | pause: {} | **Espera promocion manual** |
| 3 | setWeight: 50 | 50% |
| 4 | pause: 30s | Espera 30 segundos |
| 5 | setWeight: 80 | 80% |
| 6 | pause: 30s | Espera 30 segundos |
| 7 | (automatico) | 100% - Rollout completo |

## Comandos Utiles

### Instalar plugin kubectl-argo-rollouts (opcional)

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

# Sin el plugin
kubectl get rollout talana-backend -n talana-dev -o yaml
```

### Promover canary (continuar al siguiente paso)

```bash
# Promover al siguiente paso
kubectl argo rollouts promote talana-backend -n talana-dev

# Sin el plugin
kubectl patch rollout talana-backend -n talana-dev --type merge -p '{"status":{"pauseConditions":null}}'
```

### Abortar rollout (rollback)

```bash
# Abortar y volver a version estable
kubectl argo rollouts abort talana-backend -n talana-dev

# Sin el plugin
kubectl patch rollout talana-backend -n talana-dev --type merge -p '{"spec":{"abortedAt":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}}}'
```

### Reiniciar rollout

```bash
kubectl argo rollouts restart talana-backend -n talana-dev
```

## Flujo de Despliegue

### 1. Trigger: Push a main con cambios en app/

```bash
git add app/
git commit -m "feat: nueva funcionalidad"
git push origin main
```

### 2. GitHub Actions construye nueva imagen

El workflow `build-push.yml` automaticamente:
- Construye la imagen Docker
- Pushea a Artifact Registry con tag del commit SHA
- Actualiza el tag en el rollout (via kustomize)

### 3. ArgoCD detecta cambios y sincroniza

ArgoCD detecta el cambio en la imagen y:
- Crea nuevos pods con la version canary
- Configura el 20% del trafico hacia canary
- Pausa esperando promocion manual

### 4. Validar canary

```bash
# Ver que pod responde (ejecutar varias veces)
for i in {1..20}; do
  curl -s http://35.237.234.196/health | jq -r '.pod'
done

# Testear directamente el canary (sin balanceo)
kubectl port-forward svc/talana-backend-canary 8081:80 -n talana-dev
curl http://localhost:8081/health
```

### 5. Promover o abortar

```bash
# Si todo esta bien, promover
kubectl argo rollouts promote talana-backend -n talana-dev

# Si hay problemas, abortar
kubectl argo rollouts abort talana-backend -n talana-dev
```

## Dashboard de Argo Rollouts

El dashboard esta disponible para visualizar rollouts:

```bash
# Port forward al dashboard
kubectl port-forward svc/argo-rollouts-dashboard 3100:3100 -n argo-rollouts

# Abrir en navegador
open http://localhost:3100/rollouts
```

## Ejemplo Visual del Proceso

```
┌────────────────────────────────────────────────────────────────────┐
│                         CANARY ROLLOUT                              │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Paso 1: 20% canary                                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│   │
│  │ 20%                                                    80% │   │
│  │ canary                                              stable │   │
│  └─────────────────────────────────────────────────────────────┘   │
│  [PAUSED] Esperando promocion manual...                            │
│                                                                     │
│  Paso 3: 50% canary (despues de promote)                           │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │████████████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│   │
│  │ 50%                                                    50% │   │
│  │ canary                                              stable │   │
│  └─────────────────────────────────────────────────────────────┘   │
│  Esperando 30s...                                                  │
│                                                                     │
│  Paso 5: 80% canary                                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │████████████████████████████████████████████████░░░░░░░░░░░░│   │
│  │ 80%                                                    20% │   │
│  │ canary                                              stable │   │
│  └─────────────────────────────────────────────────────────────┘   │
│  Esperando 30s...                                                  │
│                                                                     │
│  Completo: 100% nueva version                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │████████████████████████████████████████████████████████████│   │
│  │ 100% nueva version (ahora es stable)                       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│  [HEALTHY] Rollout completado exitosamente                         │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

## Archivos Relacionados

| Archivo | Descripcion |
|---------|-------------|
| `k8s/argocd/argo-rollouts.yaml` | ArgoCD Application para Argo Rollouts |
| `k8s/apps/talana-backend/base/rollout.yaml` | Configuracion del Rollout |
| `k8s/apps/talana-backend/base/service.yaml` | Service estable |
| `k8s/apps/talana-backend/base/service-canary.yaml` | Service canary |

## Troubleshooting

### Rollout stuck en Paused

```bash
# Ver estado detallado
kubectl describe rollout talana-backend -n talana-dev

# Promover manualmente
kubectl argo rollouts promote talana-backend -n talana-dev
```

### Rollout en estado Degraded

```bash
# Ver eventos
kubectl get events -n talana-dev --sort-by='.lastTimestamp'

# Ver logs de pods canary
kubectl logs -l app=talana-backend -n talana-dev --tail=50
```

### Volver a version anterior

```bash
# Abortar rollout actual
kubectl argo rollouts abort talana-backend -n talana-dev

# O hacer rollback a revision especifica
kubectl argo rollouts undo talana-backend -n talana-dev --to-revision=2
```

---

Ver [03-production-improvements.md](03-production-improvements.md) para configuraciones avanzadas como analisis automatico con metricas.
