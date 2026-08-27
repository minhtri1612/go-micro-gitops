# go-micro-gitops

Source of truth for **Argo CD** app desired state (multi-repo layout).

## Contains

- `env/` — image tags per environment (Jenkins on **VPS** bumps these)
- `app/`, `template/`, `config/` — Helm values + chart for microservices
- `argocd/` — Projects, manifest-apps, bootstrap Applications
- `db-init/`, `external-secrets/`

## Not here

- Jenkins-in-cluster — **removed** (`22-jenkins-mgmt.yaml` deleted). CI = VPS + `go-micro-pipeline-lib`
- Kind/Terraform/Cilium values — **`go-micro-infra`**

## Bootstrap

Apply from this repo (after Kind + Argo up):

```bash
kubectl apply -f argocd/bootstrap/00-argocd-cm-health.yaml
# … then 01, 02, … (no 22-jenkins)
```

Platform Applications pull Helm **values** from `go-micro-infra`; microservice apps from this repo.
