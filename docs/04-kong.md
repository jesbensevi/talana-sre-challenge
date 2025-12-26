# Kong Ingress Controller

Kong es el API Gateway que maneja todo el trafico entrante hacia la aplicacion.

## Arquitectura

```
Internet → GCP Load Balancer → Kong Proxy → Backend Services
                                   ↓
                            Rate Limiting
                            CORS Headers
                            Request Validation
```

## Configuracion Actual

| Parametro | Valor |
|-----------|-------|
| Replicas | 1 |
| CPU Request | 50m |
| CPU Limit | 200m |
| Memory Request | 128Mi |
| Memory Limit | 256Mi |
| Modo | DB-less (declarativo) |

## Plugins Habilitados

### 1. Rate Limiting

Limita el numero de requests por cliente.

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: rate-limit-backend
plugin: rate-limiting
config:
  minute: 100      # 100 requests por minuto
  hour: 1000       # 1000 requests por hora
  policy: local    # Contador local (no distribuido)
  fault_tolerant: true
  hide_client_headers: false
```

**Headers de respuesta:**
```
X-RateLimit-Limit-Minute: 100
X-RateLimit-Remaining-Minute: 98
X-RateLimit-Limit-Hour: 1000
X-RateLimit-Remaining-Hour: 997
```

### 2. CORS

Permite requests cross-origin.

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: cors-backend
plugin: cors
config:
  origins:
    - "*"              # Permite todos los origenes
  methods:
    - GET
    - POST
    - PUT
    - DELETE
    - OPTIONS
  headers:
    - Accept
    - Authorization
    - Content-Type
  exposed_headers:
    - X-RateLimit-Limit-Minute
    - X-RateLimit-Remaining-Minute
  credentials: false
  max_age: 3600        # Cache preflight por 1 hora
```

### 3. Request Size Limiting

Limita el tamano maximo de requests.

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: request-size-limit
plugin: request-size-limiting
config:
  allowed_payload_size: 10    # 10 MB maximo
  size_unit: megabytes
```

## Ingress Configuration

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: talana-backend
  annotations:
    konghq.com/strip-path: "false"
    konghq.com/plugins: rate-limit-backend
spec:
  ingressClassName: kong
  rules:
    - http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: talana-backend
                port:
                  number: 80
          - path: /health
            pathType: Exact
            backend:
              service:
                name: talana-backend
                port:
                  number: 80
          - path: /ready
            pathType: Exact
            backend:
              service:
                name: talana-backend
                port:
                  number: 80
          - path: /
            pathType: Exact
            backend:
              service:
                name: talana-backend
                port:
                  number: 80
```

## Comandos Utiles

### Ver estado de Kong

```bash
# Pods
kubectl -n kong get pods

# Services
kubectl -n kong get svc

# IP externa
kubectl -n kong get svc kong-kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Ver logs

```bash
# Logs del proxy
kubectl -n kong logs -l app.kubernetes.io/name=kong -c proxy

# Logs del ingress controller
kubectl -n kong logs -l app.kubernetes.io/name=kong -c ingress-controller

# Follow logs
kubectl -n kong logs -f -l app.kubernetes.io/name=kong
```

### Ver configuracion activa

```bash
# Listar plugins
kubectl get kongplugins -A

# Listar ingresses
kubectl get ingress -A

# Describir ingress
kubectl describe ingress talana-backend -n talana-dev
```

### Probar endpoints

```bash
KONG_IP=$(kubectl -n kong get svc kong-kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Root
curl http://$KONG_IP/

# Health (muestra pod name)
curl http://$KONG_IP/health

# Ready (incluye DB check)
curl http://$KONG_IP/ready

# Ver headers de rate limiting
curl -I http://$KONG_IP/health
```

### Test de balanceo de carga

```bash
# Ejecutar multiples requests para ver diferentes pods
for i in {1..10}; do
  curl -s http://$KONG_IP/health | jq -r '.pod'
done
```

## Aplicar plugins a un Ingress

Los plugins se aplican mediante annotations:

```yaml
metadata:
  annotations:
    # Un solo plugin
    konghq.com/plugins: rate-limit-backend

    # Multiples plugins (separados por coma)
    konghq.com/plugins: rate-limit-backend,cors-backend,request-size-limit
```

## Troubleshooting

### Kong no responde

```bash
# Verificar pods
kubectl -n kong get pods

# Ver eventos
kubectl -n kong get events --sort-by='.lastTimestamp'

# Reiniciar Kong
kubectl -n kong rollout restart deployment kong-kong
```

### 502 Bad Gateway

El backend no esta disponible:

```bash
# Verificar pods del backend
kubectl -n talana-dev get pods

# Verificar service
kubectl -n talana-dev get svc talana-backend

# Verificar endpoints
kubectl -n talana-dev get endpoints talana-backend
```

### Rate limit muy restrictivo

Ajustar valores en `kong-plugins.yaml`:

```yaml
config:
  minute: 200    # Aumentar limite
  hour: 5000
```

## Archivos Relacionados

| Archivo | Descripcion |
|---------|-------------|
| `k8s/argocd/kong.yaml` | ArgoCD Application para Kong |
| `k8s/apps/talana-backend/base/ingress.yaml` | Ingress rules |
| `k8s/apps/talana-backend/base/kong-plugins.yaml` | Plugin configurations |

---

Ver [03-production-improvements.md](03-production-improvements.md) para configuracion de produccion (HA, TLS, rate limiting distribuido).
