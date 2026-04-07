# wellness-gitops

[![CD MAIN](https://img.shields.io/github/actions/workflow/status/luisrodvilladaorg/wellness-gitops/cd.yml?branch=main&label=CD%20MAIN)](https://github.com/luisrodvilladaorg/wellness-gitops/actions/workflows/cd.yml)
[![Last Commit](https://img.shields.io/github/last-commit/luisrodvilladaorg/wellness-gitops?display_timestamp=committer&label=Last%20Commit&logo=github)](https://github.com/luisrodvilladaorg/wellness-gitops/commits/main)
[![License](https://img.shields.io/github/license/luisrodvilladaorg/wellness-gitops?label=License)](LICENSE)

Main GitOps repository and Kubernetes desired-state workspace synchronized by ArgoCD.

## Quick Profile (Portfolio)

GitOps repository that drives Wellness Kubernetes deployments from declarative state in Git.

- Kustomize base and overlays for `dev` and `prod`.
- Automated image updates from workflows in `wellness-ops`.
- Continuous cluster synchronization through ArgoCD.
- Network and exposure resources: ingress, TLS, and MetalLB configuration.
- Declarative observability with backend `ServiceMonitor`.
- `dev` to `prod` promotion driven by semantic tags.

Result: auditable and predictable deployments aligned with the GitOps model.

## Recruiter TL;DR

- GitOps repository for Kubernetes desired state (`dev` and `prod`).
- Image tags are updated from `wellness-ops` by GitHub Actions.
- ArgoCD continuously synchronizes cluster state from Git.
- Networking and exposure are managed through ingress + TLS manifests.
- Monitoring integration is defined with backend `ServiceMonitor`.

## What this project does today

- Maintains Kustomize base manifests and overlays for `dev` and `prod`.
- Receives image-tag updates from `wellness-ops` pipelines.
- Serves as ArgoCD sync source for cluster reconciliation.

## Repository Model

- `wellness-ops`: application code, Dockerfiles, build/promotion workflows.
- `wellness-gitops`: declarative deployment (K8s), ingress, TLS, and observability assets.

Current flow summary:

1. Push to `main` in `wellness-ops` -> update `dev` overlays in this repo.
2. Tag `v*.*.*` in `wellness-ops` -> promote images to `prod` overlays in this repo.
3. ArgoCD syncs the cluster to the desired state defined in this repo.

## Project Structure

```text
wellness-gitops/
├── k8s/
│   ├── base/                    # Base workloads: backend, frontend, postgres
│   └── overlays/
│       ├── dev/                 # Environment-specific patches (DEV)
│       └── prod/                # Environment-specific patches (PROD)
├── ingress/                     # HTTP ingress and issuer manifests
├── ingress-dev/                 # DEV ingress host/path routing
├── tls/                         # Certificate, issuer, and TLS ingress resources
├── metallb/                     # Bare-metal LoadBalancer IP pool/advertisement
├── monitoring/                  # ServiceMonitor and observability manifests
├── nginx/                       # Optional nginx deployment/service/config manifests
├── rback/                       # RBAC examples/labs
├── strategies-k8s/              # Progressive delivery strategy labs
├── helm/                        # Helm chart-related assets
├── dump.sql                     # Sample DB dump/reference data
└── README.md
```

### Folder guide

- `k8s/base/`: reusable base manifests for core services.
- `k8s/overlays/`: environment overlays (`dev`, `prod`) where image patches are updated by CI/CD.
- `ingress*` + `tls/`: external traffic entrypoint and HTTPS configuration.
- `metallb/`: load balancer setup for bare-metal clusters.
- `monitoring/`: Prometheus Operator integration (`ServiceMonitor`).
- `strategies-k8s/` and `rback/`: lab and learning assets for rollout/RBAC scenarios.

## Networking and exposure

- HTTP(S) routing via **NGINX Ingress Controller**.
- Path rules:
  - `/api` -> `backend-service`
  - `/` -> `frontend-service`
- TLS managed with manifests in `tls/` (cert-manager + issuers/certificates).

## Observability

- `monitoring/backend-servicemonitor.yml` defines the backend `ServiceMonitor`.
- Expected metrics endpoint is `/metrics` on backend service port `http`.

## Scope Note

ArgoCD `Application` manifests are not versioned in this repository.
This repository serves as the GitOps source of Kubernetes resources (desired state).

## Quick usage

- Inspect overlays:

```bash
tree -L 3 k8s/
```

- Preview overlays with Kustomize:

```bash
kubectl kustomize k8s/overlays/dev/backend
kubectl kustomize k8s/overlays/prod/backend
```

## Resources

- [k8s/base](k8s/base)
- [k8s/overlays/dev](k8s/overlays/dev)
- [k8s/overlays/prod](k8s/overlays/prod)
- [ingress-dev/dev-ingress.yml](ingress-dev/dev-ingress.yml)
- [tls/wellness-ingress.yml](tls/wellness-ingress.yml)
- [monitoring/backend-servicemonitor.yml](monitoring/backend-servicemonitor.yml)

## License

Project distributed under [LICENSE](LICENSE).

## Author

Luis Fernando Rodríguez Villada

luisfernando198912@gmail.com
