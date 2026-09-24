# go-micro-gitops

Source of truth for **Argo CD** app desired state (multi-repo layout).

## Contains

- `env/` — image tags per environment (Jenkins on **VPS** bumps these)
- `app/`, `template/`, `config/` — Helm values + chart for microservices
- `argocd/` — Projects, manifest-apps, bootstrap Applications
- `db-init/`, `external-secrets/`

## Not here

- Jenkins — **không** ở repo này. CI = Docker Compose trong `go-micro-infra/jenkins` + library `go-micro-pipeline-lib`
- Kind/Terraform — **`go-micro-infra`**

## Bootstrap

Apply from this repo after Kind + Argo are up. CNI = kindnet. Traefik = NodePort. No Cilium, no MetalLB.

```bash
kubectl apply -f argocd/bootstrap/00-argocd-cm-health.yaml
kubectl apply -f argocd/bootstrap/01-projects.yaml
# monitoring 05/06/08, then rollouts 12/14, traefik 19/21, stacks 02/04
```

Platform Applications pull Helm **values** from `go-micro-infra`; microservice apps from this repo.
