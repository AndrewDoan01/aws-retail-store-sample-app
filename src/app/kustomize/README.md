# Kustomize deployment for Retail Store Sample App

This folder contains the Kustomize manifests and overlays used by the CI/CD pipelines.

Overview
- Bases: `base/<service>` — one Kustomize base per service (catalog, cart, orders, checkout, ui). Each base contains service, deployment, configmap/secret (if needed), HPA and ServiceAccount.
- Overlays: `overlays/kind` (for e2e/kind tests, uses NodePort) and `overlays/release` (for release artifacts, uses LoadBalancer).

Why we migrated
- CI previously ran `helmfile apply` (rendering charts at release time). To simplify automated artifact generation and make image substitution deterministic we now produce static manifests via Kustomize in the release path.
- Helmfile and charts are kept for local dev (Tilt) and e2e dev workflows.

How images are handled
- Overlays contain an `images:` stanza where `name` + `newTag` can be set to change image tags/digests.
- The release packaging script (`scripts/kubernetes-dist.sh`) updates `overlays/release/kustomization.yaml` to set `newTag` before running `kubectl kustomize`.
- If you want to pin to digests, put the digest in `newTag` (e.g. `sha256:...`) or change the overlay to use `newName` with `@sha256:...`.

CI changes
- `.github/workflows/e2e-test.yml` now deploys with:

```bash
kubectl apply -k src/app/kustomize/overlays/kind
```

- Release artifact generation uses `scripts/kubernetes-dist.sh` which runs `kubectl kustomize` on `overlays/release` and writes `dist/kubernetes/kubernetes.yaml`.

Local testing
- To render an overlay locally (needs `kubectl` with Kustomize support):

```bash
kubectl kustomize src/app/kustomize/overlays/kind > /tmp/kind.yaml
kubectl kustomize src/app/kustomize/overlays/release > /tmp/release.yaml
```

- To apply locally to a cluster (kind/minikube):

```bash
kubectl apply -k src/app/kustomize/overlays/kind
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/owner=retail-store-sample --timeout=180s
```

Notes and caveats
- Helmfile is intentionally preserved for Tilt/local dev. Do not remove `src/app/helmfile.yaml` if you use Tilt.
- ConfigMaps and Secrets: the bases include example ConfigMaps and Secrets to preserve env var names used by services. In production you should replace secrets with platform-managed secrets (Vault/Secrets Manager/Kubernetes Secrets with proper values).
- The `scripts/kubernetes-dist.sh` implementation uses `sed` to set `newTag` in the release overlay to avoid requiring `yq` in CI runners. CI runners still need `kubectl` available (see repo `.mise.toml`).

Rollbacks
- To revert to Helmfile in CI, restore the previous workflow that runs `helmfile apply -f src/app/helmfile.yaml` (history available in git). Prefer creating a short PR that reverts the workflow file.

Where to look next
- `src/app/helmfile.yaml` — original Helmfile used by Tilt/local dev.
- `scripts/kubernetes-dist.sh` — release manifest generator.
- `src/app/kustomize/overlays/*` — the overlays for release and kind.

If you want this README in Vietnamese or with additional diagrams/commands, say so and I will add them.
