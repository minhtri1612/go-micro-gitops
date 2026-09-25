# Plan khóa CI/CD cho team ~10 dev

Kiến trúc giữ nguyên: **1 service / 1 repo / 1 Jenkins job**, shared library DevOps, **Jenkins không apply cluster**, Argo CD đọc repo này rồi sync.

File này là plan 7 điểm (CODEX). Làm theo thứ tự dưới. Công việc trải 3 repo:

| Repo | Vai trò |
|---|---|
| `go-micro-gitops` (repo này) | File env, Helm valueFiles, CODEOWNERS, PR promotion |
| `go-micro-pipeline-lib` | `ciGoMicroService`, allowlist, test bắt buộc, bump GitOps |
| `go-micro-infra` (`jenkins/`) | CasC: auth, credentials, pin library |

Service repos (`go-micro-product`, …) chỉ còn Jenkinsfile một dòng sau điểm 2.

---

## Thứ tự

1. Tách file tag + hết race GitOps  
2. Khóa Jenkinsfile (allowlist service → image/env)  
3. Tách credential + PR CI vs release  
4. Phân quyền Jenkins (không còn mọi user = admin)  
5. Pin shared library, tắt override  
6. Bắt buộc test trước publish  
7. Promotion digest: dev → staging/prod qua PR  

1 phải xong trước 7 (Helm đang trỏ `env/dev.yaml` một file). 2 nên làm cùng 1 hoặc ngay sau. 3–5 có thể song song sau 2. 6 gắn vào entrypoint sau khi lock library.

---

## 1. Race: nhiều job cùng sửa `env/dev.yaml`

**Hiện tại:** Mọi service bump chung [`env/dev.yaml`](../env/dev.yaml). `disableConcurrentBuilds()` chỉ khóa **cùng job**, không khóa product vs order. Clone nông + `git push` không rebase → non-fast-forward.

**Mục tiêu:** Mỗi service một file tag. Hai job không đụng cùng file.

**Làm**

- GitOps: `env/dev.yaml` → `env/dev/<service>.yaml` (product, inventory, order, payment, noti, client). Prod/staging cùng pattern. DB tags (`15-alpine`) để file riêng hoặc `env/<env>/_databases.yaml` — Jenkins **không** bump file đó.
- Helm: [`argocd/manifest-apps/templates/applications.yaml`](../argocd/manifest-apps/templates/applications.yaml) đang `../env/{{ env }}.yaml`. Đổi thành `../env/{{ env }}/{{ $appName }}.yaml` (noti → file `noti.yaml`).
- Library: bump chỉ file của service; `git push` + fetch/rebase/retry 3 lần (phòng CODEOWNERS/PR sau này).
- Xóa `envFile` tùy ý từ Jenkinsfile (điểm 2).

**Xong khi:** product và order CI chạy song song, cả hai push GitOps thành công; Argo sync đúng tag từng app.

---

## 2. Dev không biến Jenkinsfile thành quyền deploy

**Hiện tại:** `ciGoMicroService([ service, imageRepo, gitopsRepo, envFile, gitBranch ])` — mặc định `env/dev.yaml` nhưng không khóa. Dev sửa Jenkinsfile có thể bump `env/prod.yaml` hoặc repo khác.

**Mục tiêu:** Jenkinsfile chỉ `ciGoMicroService('product')`. Image repo, GitOps repo, file env, branch nằm **allowlist DevOps** trong library.

**Làm**

- Map trong pipeline-lib, ví dụ `product` → image `minhtri1612/product-service`, GitOps `env/dev/product.yaml`, branch `main`.
- Bỏ (hoặc ignore) `gitopsRepo` / `envFile` / `gitBranch` / `imageRepo` từ Jenkinsfile.
- Job DSL/CasC: job service chỉ load library đã pin; không cho `checkout scm` chạy pipeline tùy ý ngoài entrypoint này.
- Cập nhật 6 Jenkinsfile service cho khớp chữ ký mới.

**Xong khi:** Sửa Jenkinsfile service không thể bump prod hoặc clone GitOps repo khác.

---

## 3. Credentials global + pipeline do dev kiểm soát

**Hiện tại:** `dockerhub-credentials` + `github-go-micro-pat` (CasC). Một PAT vừa đọc source vừa push GitOps. Stage build/bump `withCredentials` trong library nhưng job gắn repo service.

**Mục tiêu**

- **PR:** test/build, **không** Docker Hub write, **không** GitOps PAT.
- **Merge `main`:** job release DevOps-owned: checkout source → build/push image (token chỉ repo đó) → bump **đúng file** GitOps.
- Bot tách: read source; push image scoped; write chỉ `go-micro-gitops`. Không một PAT toàn năng.

**Làm:** folder/Multibranch: PR vs `main`; credential binding chỉ trên job release; PAT GitOps least-privilege (`contents: write` đúng repo).

**Xong khi:** Job PR không thấy credential deploy; leak Jenkinsfile không push được GitOps.

---

## 4. Phân quyền team

**Hiện tại:** `loggedInUsersCanDoAnything` — 10 user = 10 admin.

**Mục tiêu:** Dev xem/build **job service mình**. DevOps: credentials, library, job config, promotion prod.

**Làm:** GitHub OAuth/OIDC (hoặc matrix tạm). Folder `services/product` → team product. Folder `devops/` chỉ admin. Tắt `loggedInUsersCanDoAnything`.

**Xong khi:** User product không sửa job order, không xem credential store.

---

## 5. Shared library pin, không override

**Hiện tại:** `defaultVersion: main`, `allowVersionOverride: true`.

**Mục tiêu:** Pin tag `v1.2.0`, `allowVersionOverride: false`. Library có CI riêng (unit Groovy / job test). Bump version = PR CasC do DevOps.

**Xong khi:** Jenkinsfile `@Library('go-micro-ci@vX')` bị từ chối hoặc bị ignore; mọi job dùng cùng tag.

---

## 6. Test bắt buộc trước publish

**Hiện tại:** Identify → Build & Push → Bump. `libTests.groovy` không gọi từ `ciGoMicroService`.

**Mục tiêu:** Fail = không push image, không bump GitOps.

**Làm (tối thiểu):** unit + lint trong repo service (Make/go test). Entrypoint library gọi trước `docker push`. Sau: integration/contract, rồi scan/SBOM.

**Xong khi:** Test fail → không tag mới trên GitOps.

---

## 7. Promotion: cùng digest, không rebuild prod

**Hiện tại:** CI ghi thẳng tag vào env dev. Không PR staging/prod, không CODEOWNERS.

**Mục tiêu:** Dev CI chỉ `env/dev/<service>.yaml`. Prod = **cùng image digest** đã chạy dev, qua PR.

**Luồng**

1. Merge service `main` → image `name-<sha>` → bump **dev** (điểm 1–2).  
2. Dev ổn → PR GitOps: copy tag/digest → `env/staging/…` (nếu dùng staging) hoặc thẳng `env/prod/…`.  
3. CODEOWNERS: `env/prod/**` bắt DevOps approve.  
4. Argo sync prod sau merge PR. Jenkins **không** ghi `env/prod` từ job service.

**Làm:** CODEOWNERS + branch protection GitOps; optional `promote.groovy` chỉ mở PR, không push `main` prod. Helm valueFiles đã per-service từ điểm 1.

**Xong khi:** Không job service nào push được `env/prod/**` trên `main` nếu thiếu review.

---

## Không làm trong plan này

- EKS / IRSA (ESO lab Kind + IAM key vẫn tách).  
- Đổi Argo/Kind topology.  
- Mỗi dev một Jenkins.

---

## Definition of done (cả 7)

- 10 dev push 6 service cùng lúc: GitOps không fail non-fast-forward.  
- Jenkinsfile service không bump prod, không đổi GitOps repo.  
- PR không mang token deploy.  
- Dev không admin Jenkins.  
- Library pin tag.  
- Test fail chặn publish.  
- Prod chỉ qua PR + CODEOWNERS, cùng digest với dev.
