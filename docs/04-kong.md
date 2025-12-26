# Kong Gateway API Controller

Kong es el API Gateway que maneja todo el trafico entrante hacia la aplicacion, utilizando **Gateway API** para el routing de trafico.

## Configuracion Actual

| Parametro | Valor |
|-----------|-------|
| Chart Version | 3.0.1 |
| Kong Version | 3.9 |
| KIC Version | 3.5 |
| Replicas | 1 |
| CPU Request | 50m |
| CPU Limit | 200m |
| Memory Request | 128Mi |
| Memory Limit | 256Mi |
| Modo | DB-less (declarativo) |

## Gateway API

Usamos Gateway API en lugar de Ingress para tener control preciso del trafico (necesario para canary deployments).

### GatewayClass

Define el controlador que manejara los Gateways:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: kong
  annotations:
    konghq.com/gatewayclass-unmanaged: "true"
spec:
  controllerName: konghq.com/kic-gateway-controller
```

### Gateway

Crea el listener HTTP:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: kong-gateway
spec:
  gatewayClassName: kong
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Same
```

### HTTPRoute

Define las rutas, plugins y distribucion de trafico:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: talana-backend
spec:
  parentRefs:
    - name: kong-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      filters:                              # Plugins conectados
        - type: ExtensionRef
          extensionRef:
            group: configuration.konghq.com
            kind: KongPlugin
            name: rate-limit-backend
        - type: ExtensionRef
          extensionRef:
            group: configuration.konghq.com
            kind: KongPlugin
            name: cors-backend
        - type: ExtensionRef
          extensionRef:
            group: configuration.konghq.com
            kind: KongPlugin
            name: request-size-limit
      backendRefs:                          # Traffic splitting
        - name: talana-backend-stable
          port: 80
          weight: 100    # Trafico a version estable
        - name: talana-backend-canary
          port: 80
          weight: 0      # Trafico a version canary
```

## Plugins Disponibles

### 1. Rate Limiting

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: rate-limit-backend
plugin: rate-limiting
config:
  minute: 100000
  hour: 10000000
  policy: local
  fault_tolerant: true
  hide_client_headers: false
```

### 2. CORS

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: cors-backend
plugin: cors
config:
  origins:
    - "*"
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
  credentials: false
  max_age: 3600
```

### 3. Request Size Limiting

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: request-size-limit
plugin: request-size-limiting
config:
  allowed_payload_size: 10
  size_unit: megabytes
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

### Ver recursos Gateway API

```bash
# GatewayClass
kubectl get gatewayclass

# Gateway
kubectl get gateway -A

# HTTPRoutes
kubectl get httproute -A

# Ver pesos actuales del HTTPRoute
kubectl get httproute talana-backend -n talana-dev -o jsonpath='{.spec.rules[0].backendRefs}' | jq .
```

### Ver logs

```bash
# Logs del proxy
kubectl -n kong logs -l app.kubernetes.io/name=kong -c proxy

# Logs del ingress controller
kubectl -n kong logs -l app.kubernetes.io/name=kong -c ingress-controller

# Follow logs
kubectl -n kong logs -f -l app.kubernetes.io/name=kong -c ingress-controller
```

### Probar endpoints

```bash
KONG_IP=$(kubectl -n kong get svc kong-kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Root
curl http://$KONG_IP/

# Health
curl http://$KONG_IP/health

# Ready (incluye DB check)
curl http://$KONG_IP/ready

# Ver distribucion de trafico (durante canary)
for i in {1..20}; do
  curl -s http://$KONG_IP/health | jq -r '.version'
done | sort | uniq -c
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

### Error 400 en logs de KIC

Si ves errores como:
```
could not unmarshal config error: json: cannot unmarshal object into Go struct field ConfigError.flattened_errors
```

Esto es incompatibilidad de versiones. Asegurate de usar Kong chart >= 3.0.1

### HTTPRoute no funciona

```bash
# Verificar que Gateway este programado
kubectl get gateway -n talana-dev

# Verificar status del HTTPRoute
kubectl describe httproute talana-backend -n talana-dev

# Verificar que los servicios existan
kubectl get svc -n talana-dev
```

### 502 Bad Gateway

```bash
# Verificar pods del backend
kubectl -n talana-dev get pods

# Verificar endpoints
kubectl -n talana-dev get endpoints talana-backend-stable
kubectl -n talana-dev get endpoints talana-backend-canary
```

## Archivos Relacionados

| Archivo | Descripcion |
|---------|-------------|
| `k8s/argocd/kong.yaml` | ArgoCD Application para Kong |
| `k8s/argocd/gateway-api-crds.yaml` | CRDs de Gateway API |
| `k8s/apps/talana-backend/base/gateway.yaml` | GatewayClass y Gateway |
| `k8s/apps/talana-backend/base/httproute.yaml` | HTTPRoute para routing |
| `k8s/apps/talana-backend/base/kong-plugins.yaml` | Plugin configurations |

---

Ver [06-canary-deployments.md](06-canary-deployments.md) para configuracion de deployments canary con Argo Rollouts.
