# Observability Lab — wellness-ops
**Fecha:** 22 de abril de 2026  
**Cluster:** k3s — IP `192.168.1.11`  
**Repo GitOps:** `github.com/luisrodvilladaorg/wellness-gitops`  
**Namespace monitoring:** kube-prometheus-stack + Loki

---

## Contexto

Stack de observabilidad completo sobre un cluster k3s single-node con:
- `kube-prometheus-stack` (Prometheus + Grafana + Alertmanager + kube-state-metrics + node-exporter)
- Loki (SingleBinary mode)
- ArgoCD como motor GitOps

El objetivo fue versionar dashboards, activar Alertmanager y crear reglas Prometheus — todo gestionado por GitOps.

---

## Estructura final del repo GitOps

```
wellness-gitops/
├── k8s/
│   └── argocd/
│       ├── app-kube-prom.yaml          # ArgoCD Application para kube-prometheus-stack
│       ├── appproject.yml              # AppProject con permisos actualizados
│       ├── app-backend-dev.yml
│       ├── app-backend-prod.yml
│       └── ...
└── monitoring/
    └── monitoring-k8s/
        ├── kube-prom-values.yaml       # Helm values de kube-prom (Alertmanager enabled)
        ├── prometheus-rules.yaml       # PrometheusRule — alertas wellness-ops
        ├── alertmanager-config.yaml    # AlertmanagerConfig CRD
        ├── backend-servicemonitor.yml  # ServiceMonitor para backend (pendiente prom-client)
        └── dashboards/
            ├── grafana-overview.json
            ├── kubernetes-api-server.json
            ├── kubernetes-compute-resources.json
            ├── kubernetes-namespace-pods.json
            └── kubernetes-pod.json
```

---

## Parte 1 — Dashboards versionados

### Qué se hizo
Se exportaron 5 dashboards del kube-prometheus-stack desde Grafana y se versionaron en el repo GitOps.

### Proceso de exportación
1. Abrir Grafana → `http://192.168.1.11:3000` (vía port-forward)
2. Dashboards → Browse → seleccionar dashboard
3. Share → Export → **Export for sharing externally** → Download JSON
4. Copiar desde carpeta compartida de VirtualBox al repo:

```bash
sudo cp /media/compartidaVM/nombre-dashboard.json \
  /opt/wellness-gitops/monitoring/monitoring-k8s/dashboards/
```

### Dashboards exportados

| Archivo | Dashboard original | Descripción |
|---|---|---|
| `grafana-overview.json` | Grafana Overview | Estado interno de Grafana |
| `kubernetes-api-server.json` | Kubernetes / API server | Health del control plane |
| `kubernetes-compute-resources.json` | Kubernetes / Compute Resources / Cluster | CPU, memoria, red, disco por namespace |
| `kubernetes-namespace-pods.json` | Kubernetes / Compute Resources / Namespace (Pods) | Recursos por namespace drill-down |
| `kubernetes-pod.json` | Kubernetes / Compute Resources / Pod | Métricas a nivel de pod individual |

### Nota sobre permisos (VirtualBox shared folder)
La carpeta compartida `/media/compartidaVM` pertenece al grupo `vboxsf`. Para acceder sin sudo:
```bash
sudo usermod -aG vboxsf $USER
# Cerrar sesión y volver a entrar para que tome efecto
```

### Dashboard pendiente
`wellness-ops-app.json` — dashboard custom de la app. Requiere `prom-client` instalado en el backend Node.js para exponer `/metrics`. Cuando esté listo, el ServiceMonitor (`backend-servicemonitor.yml`) ya está en el repo esperando.

---

## Parte 2 — kube-prom incorporado a GitOps

### Situación inicial
`kube-prometheus-stack` estaba instalado con Helm directamente (fuera de GitOps). Alertmanager estaba desactivado:

```bash
helm get values kube-prom -n monitoring
# alertmanager:
#   enabled: false
```

### Solución — ArgoCD Application con multi-source

Se creó `/opt/wellness-gitops/k8s/argocd/app-kube-prom.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prom
  namespace: argocd
spec:
  project: wellness
  sources:
    - repoURL: https://prometheus-community.github.io/helm-charts
      chart: kube-prometheus-stack
      targetRevision: 82.16.2
      helm:
        valueFiles:
          - $values/monitoring/monitoring-k8s/kube-prom-values.yaml
    - repoURL: https://github.com/luisrodvilladaorg/wellness-gitops
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
```

**Por qué `ServerSideApply=true`:** Los CRDs de kube-prometheus-stack son tan grandes que superan el límite de anotaciones de Kubernetes (262144 bytes). Sin esta opción ArgoCD falla con:
```
CustomResourceDefinition is invalid: metadata.annotations: Too long
```

**Por qué `sources` (plural) y no `source`:** Necesitamos dos fuentes — el chart de Helm (prometheus-community) y el values file del repo GitOps. ArgoCD soporta multi-source con la sintaxis `sources`.

### AppProject actualizado

El AppProject original solo permitía `default` y `dev`. Se amplió para soportar kube-prom:

```yaml
sourceRepos:
  - https://github.com/luisrodvilladaorg/wellness-gitops
  - https://prometheus-community.github.io/helm-charts   # añadido

destinations:
  - namespace: default
  - namespace: dev
  - namespace: monitoring    # añadido
  - namespace: argocd        # añadido
  - namespace: kube-system   # añadido (node-exporter vive aquí)

clusterResourceWhitelist:
  - Namespace
  - ClusterRole / ClusterRoleBinding
  - CustomResourceDefinition
  - ValidatingWebhookConfiguration   # añadido
  - MutatingWebhookConfiguration     # añadido
```

**Por qué `kube-system`:** kube-prometheus-stack despliega el node-exporter DaemonSet en `kube-system`. Sin este namespace en destinations, ArgoCD rechaza el sync.

**Por qué los Webhooks:** El Prometheus Operator registra webhooks de validación para sus CRDs. Sin permitirlos en el AppProject, el sync falla con `resource is not permitted in project wellness`.

### kube-prom-values.yaml

```yaml
alertmanager:
  enabled: true    # era false

grafana:
  adminPassword: admin123
  enabled: true

prometheus:
  prometheusSpec:
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 100m
        memory: 256Mi
    retention: 24h
```

---

## Parte 3 — Reglas Prometheus (PrometheusRule)

### Cómo funciona el selector
Prometheus solo recoge reglas con el label correcto:

```bash
kubectl get prometheus -n monitoring -o yaml | grep -A5 ruleSelector
# ruleSelector:
#   matchLabels:
#     release: kube-prom
```

Todo `PrometheusRule` debe tener `labels: release: kube-prom`.

### Reglas creadas — `prometheus-rules.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: wellness-alerts
  namespace: monitoring
  labels:
    release: kube-prom
spec:
  groups:
    - name: wellness-ops
      rules:
        - alert: HighErrorRate
          expr: |
            sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m])) > 0
            and
            (
              sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))
              /
              sum(rate(nginx_ingress_controller_requests[5m]))
            ) > 0.05
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Alta tasa de errores 5xx"
            description: "Más del 5% de requests están devolviendo 5xx en los últimos 5 minutos"

        - alert: PodRestartingTooMuch
          expr: |
            increase(kube_pod_container_status_restarts_total{namespace=~"default|dev"}[15m]) > 5
          for: 0m
          labels:
            severity: warning
          annotations:
            summary: "Pod reiniciando demasiado"
            description: "El pod {{ $labels.pod }} en namespace {{ $labels.namespace }} ha reiniciado más de 5 veces en 15 minutos"

        - alert: PostgresDown
          expr: |
            kube_pod_status_phase{namespace=~"default|dev", pod=~"postgres.*"} != 1
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "PostgreSQL no está corriendo"
            description: "El pod {{ $labels.pod }} en {{ $labels.namespace }} no está en estado Running"
```

### Fix — falso positivo en HighErrorRate
La versión inicial de `HighErrorRate` disparaba en FIRING aunque no hubiera tráfico real. Causa: división `0/0` en PromQL da resultado inesperado cuando no hay requests.

**Fix:** añadir condición `> 0` antes de la división para garantizar que solo evalúa cuando hay tráfico 5xx real.

### Verificar que Prometheus cargó las reglas
```bash
kubectl get prometheusrule -n monitoring
# wellness-alerts   24s  ← debe aparecer
```

En la UI de Prometheus `http://192.168.1.11:9090/alerts` → buscar grupo `wellness-ops`.

---

## Parte 4 — Alertmanager con Gmail SMTP

### Por qué no meter la contraseña en el repo
La App Password de Gmail no va en ningún manifiesto del repo. Si se hace push de una contraseña a GitHub, queda en el historial para siempre aunque se borre después.

### Paso 1 — Generar App Password de Gmail
1. Ir a `https://myaccount.google.com/apppasswords`
2. Crear una nueva App Password (requiere 2FA activo)
3. Copiar los 16 caracteres **sin espacios**

### Paso 2 — Crear Secret en Kubernetes
```bash
kubectl create secret generic alertmanager-gmail \
  --from-literal=password='APP_PASSWORD_SIN_ESPACIOS' \
  -n monitoring
```

Este Secret **no va al repo**.

### Paso 3 — Config global de Alertmanager
El `AlertmanagerConfig` CRD solo gestiona sub-rutas. La config global (receiver principal) debe ir en el Secret que Alertmanager lee directamente:

```bash
# Crear el archivo de config temporal
cat <<EOF > /tmp/alertmanager.yaml
global:
  smtp_smarthost: smtp.gmail.com:587
  smtp_from: TU_EMAIL@gmail.com
  smtp_auth_username: TU_EMAIL@gmail.com
  smtp_auth_password: TU_APP_PASSWORD
  smtp_require_tls: true

route:
  receiver: gmail
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h

receivers:
  - name: gmail
    email_configs:
      - to: TU_EMAIL@gmail.com
EOF

# Reemplazar el Secret que Alertmanager usa
kubectl delete secret alertmanager-kube-prom-kube-prometheus-alertmanager -n monitoring
kubectl create secret generic alertmanager-kube-prom-kube-prometheus-alertmanager \
  --from-file=alertmanager.yaml=/tmp/alertmanager.yaml \
  -n monitoring
```

### Resultado
Emails llegando con alertas del cluster. La primera alerta recibida fue `KubeSchedulerDown` — es normal en k3s porque el scheduler no expone métricas como en un cluster kubeadm estándar. No es un problema real.

---

## Comandos de verificación rápida

```bash
# Estado general del stack
kubectl get pods -n monitoring

# Reglas cargadas
kubectl get prometheusrule -n monitoring

# Alertmanager corriendo
kubectl get pods -n monitoring | grep alertmanager

# ArgoCD Applications
kubectl get application -n argocd

# Port-forwards
kubectl port-forward -n monitoring svc/kube-prom-grafana 3000:80 --address=0.0.0.0
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 --address=0.0.0.0
kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093 --address=0.0.0.0
```

---

## Pendientes

- [ ] `wellness-ops-app.json` — dashboard custom cuando se añada `prom-client` al backend
- [ ] SLO mini — `docs/SLO.md` (API availability 99.5% + alertas)
- [ ] Secret `alertmanager-gmail` — documentar proceso de rotación
- [ ] Incorporar Loki a GitOps (actualmente instalado con Helm directo igual que kube-prom era antes)

## SLO-2b — Latencia de la API

**SLI:** Porcentaje de requests HTTP que responden en menos de 500ms.

**Query Prometheus:**
```promql
sum(rate(wellness_http_request_duration_seconds_bucket{le="0.5"}[5m]))
/
sum(rate(wellness_http_request_duration_seconds_count[5m]))
```

**Objetivo:** `>= 95%` de requests bajo 500ms en ventana de 30 días  
**Error Budget:** `5%` — hasta 1 de cada 20 requests puede superar 500ms  
**Referencia P95 actual:** ~700ms en ruta `/` (health check del cluster)  
**Alerta sugerida:** Cuando P95 supere 1s durante 5 minutos

# Observability Lab — Parte 2
**Fecha:** 22 de abril de 2026  
**Continuación de:** OBSERVABILITY-LAB.md

---

## Parte 5 — prom-client + ServiceMonitor

### Situación inicial
El backend ya tenía `prom-client` implementado con métricas custom, pero Prometheus no las estaba raspando por dos razones:
1. El endpoint `/metrics` no estaba expuesto via Ingress (correcto — no debe estarlo)
2. El ServiceMonitor tenía el label incorrecto

### Verificar que /metrics funciona internamente
```bash
kubectl exec -n default deploy/backend -- wget -qO- http://localhost:3000/metrics | head -20
# Devuelve métricas wellness_backend_* — CPU, memoria, HTTP requests, duración
```

**Por qué no via Ingress:** Exponer `/metrics` públicamente es un riesgo de seguridad — revela información interna del sistema. Prometheus accede directamente al pod via ServiceMonitor, sin pasar por el Ingress.

### Fix del ServiceMonitor
El label `release` debe coincidir con el selector de Prometheus:

```bash
kubectl get prometheus -n monitoring -o yaml | grep -A5 ruleSelector
# serviceMonitorSelector:
#   matchLabels:
#     release: kube-prom
```

**Antes (incorrecto):**
```yaml
labels:
  release: monitoring
```

**Después (correcto):**
```yaml
labels:
  release: kube-prom
```

### ServiceMonitor final
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: backend-monitoring
  namespace: monitoring
  labels:
    release: kube-prom
spec:
  selector:
    matchLabels:
      app: backend
  namespaceSelector:
    matchNames:
      - default
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

**Por qué `port: http` y no `port: 3000`:** El ServiceMonitor referencia el nombre del puerto definido en el Service, no el número. El Service tiene `name: http` en el puerto 3000.

### Verificar que Prometheus raspa el backend
En la UI de Prometheus → Status → Targets → buscar `backend-monitoring` → estado `UP`.

Query para verificar métricas:
```promql
wellness_http_requests_total
```

Resultado esperado — series por pod, route y status:
```
wellness_http_requests_total{pod="backend-xxx", route="/", status="200"} 4754
wellness_http_requests_total{pod="backend-yyy", route="/", status="200"} 4754
```

---

## Parte 6 — Dashboard custom wellness-ops / Backend

### Panels creados

| Panel | Query | Visualización |
|---|---|---|
| HTTP Request Rate | `sum(rate(wellness_http_requests_total[5m])) by (route, status)` | Time series |
| HTTP Error Rate 5xx | `sum(rate(wellness_http_requests_total{status=~"5.."}[5m])) by (route)` | Time series |
| Request Duration P95 | `histogram_quantile(0.95, sum(rate(wellness_http_request_duration_seconds_bucket[5m])) by (le, route))` | Time series (unit: seconds) |
| Total Requests by Status | `sum(wellness_http_requests_total) by (status)` | Stat |

### Observaciones del dashboard
- P95 latencia en ruta `/` → ~700ms (health check del cluster, request ligero)
- Error Rate 5xx → No data (correcto, no hay errores reales)
- Total requests → 10014 status 200, 1 status 404 (el curl de prueba a `/api/metrics`)

### Exportar y versionar
El dashboard se exporta desde Grafana → Share → Export → Export for sharing externally → Download JSON.

En Grafana 12 hay que salir del modo edición primero (**Exit edit**) antes de poder acceder a la opción de exportar.

Archivo guardado en:
```
wellness-gitops/monitoring/monitoring-k8s/dashboards/wellness-ops-backend.json
```

---

## Parte 7 — SLO de latencia (SLO-2b)

Añadido a `docs/SLO.md` en el repo `wellness-ops`.

### SLO-2b — Latencia de la API

**SLI:** Porcentaje de requests HTTP que responden en menos de 500ms.

**Query Prometheus:**
```promql
sum(rate(wellness_http_request_duration_seconds_bucket{le="0.5"}[5m]))
/
sum(rate(wellness_http_request_duration_seconds_count[5m]))
```

**Objetivo:** `>= 95%` de requests bajo 500ms en ventana de 30 días  
**Error Budget:** `5%` — hasta 1 de cada 20 requests puede superar 500ms  
**Referencia P95 actual:** ~700ms en ruta `/`  
**Alerta sugerida:** Cuando P95 supere 1s durante 5 minutos

### Por qué usar el bucket `le="0.5"` y no P95 directamente
El SLI de latencia se define sobre un umbral fijo (500ms) porque es más fácil de interpretar como contrato de servicio. El P95 es una métrica de monitoreo — te dice dónde está el percentil 95, pero no si estás cumpliendo el objetivo.

---

## Métricas disponibles en el backend

| Métrica | Tipo | Descripción |
|---|---|---|
| `wellness_backend_process_cpu_seconds_total` | Counter | CPU consumida por el proceso |
| `wellness_backend_process_resident_memory_bytes` | Gauge | Memoria RSS del proceso |
| `wellness_http_requests_total` | Counter | Total requests por method, route, status |
| `wellness_http_request_duration_seconds` | Histogram | Duración de requests con buckets: 0.1, 0.3, 0.5, 1, 2, 5s |

---

## Roadmap completado

| Punto | Estado |
|---|---|
| Dashboards versionados (5 JSON + 1 custom) | ✅ |
| kube-prom incorporado a GitOps (ArgoCD) | ✅ |
| Alertmanager activado + Gmail SMTP | ✅ |
| PrometheusRule — 3 alertas | ✅ |
| prom-client + ServiceMonitor corregido | ✅ |
| Dashboard custom wellness-ops/Backend | ✅ |
| SLO.md completo (disponibilidad + latencia + postgres) | ✅ |

## Pendientes futuros
- [ ] Alerta de latencia — `HighP95Latency` cuando P95 > 1s durante 5 minutos
- [ ] Dashboard Grafana con burn rate del error budget
- [ ] Incorporar Loki a GitOps (actualmente Helm directo)
- [ ] Replicar stack completo en namespace `default` para portfolio público