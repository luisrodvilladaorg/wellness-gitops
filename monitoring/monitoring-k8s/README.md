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