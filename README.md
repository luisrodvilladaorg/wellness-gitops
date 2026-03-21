# wellness-gitops

GitOps repository containing the **Kubernetes desired state** for Wellness.

## Quick Profile (Portfolio)

GitOps repository that drives Wellness Kubernetes deployments through declarative state in Git.

- Kustomize base and overlays for `dev` and `prod`.
- Automated image updates from workflows in `wellnes-ops`.
- Continuous cluster synchronization through ArgoCD.
- Network and exposure resources: ingress, TLS, and MetalLB configuration.
- Declarative observability with backend `ServiceMonitor`.
- `dev` to `prod` promotion controlled by semantic tags.

Result: auditable, predictable deployments aligned with the GitOps model.

## What this repo is

This repository contains Kustomize base manifests and overlays for `dev` and `prod`.

- `wellnes-ops` builds/publishes images and updates tags in this repo.
- **ArgoCD** watches this repo and syncs the cluster to what is defined in Git.

## Relationship with `wellnes-ops`

- `wellnes-ops`: application code, Dockerfiles, build/promotion workflows.
- `wellness-gitops`: declarative deployment (K8s), ingress, TLS, and observability assets.

Current flow summary:

1. Push to `main` in `wellnes-ops` -> update `dev` overlays in this repo.
2. Tag `v*.*.*` in `wellnes-ops` -> promote images to `prod` overlays in this repo.
3. ArgoCD syncs the cluster to the desired state defined in this repo.

## Main structure

- `k8s/base/`
  - `backend/`, `frontend/`, `postgres/`
- `k8s/overlays/dev/`
  - `backend/patch-image.yml`
  - `frontend/patch-image.yml`
  - `postgres/`
- `k8s/overlays/prod/`
  - `backend/patch-image.yml`
  - `frontend/patch-image.yml`
  - `postgres/`
- `ingress-dev/`, `ingress/`, `tls/`, `metallb/`, `monitoring/`

## Networking and exposure

- HTTP(S) routing via **NGINX Ingress Controller**.
- Path rules:
  - `/api` -> `backend-service`
  - `/` -> `frontend-service`
- TLS managed with manifests in `tls/` (cert-manager + issuers/certificates).

## Observability

- `monitoring/backend-servicemonitor.yml` defines the backend `ServiceMonitor`.
- Expected metrics endpoint is `/metrics` on backend service port `http`.

## Important note

ArgoCD `Application` manifests are not versioned in this repository.
This repository serves as the GitOps source of Kubernetes resources (desired state).

## Quick usage

To inspect overlays:

```bash
tree -L 3 k8s/
```

To preview an overlay with Kustomize:

```bash
kubectl kustomize k8s/overlays/dev/backend
kubectl kustomize k8s/overlays/prod/backend
```
