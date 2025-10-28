# Claude Hub Infrastructure

GitOps repository for Claude Hub Kubernetes infrastructure.

## Repository Structure

```
claude-hub-infra/
├── clusters/           # Cluster-specific configurations
│   ├── dev/           # Development cluster
│   ├── staging/       # Staging cluster
│   └── prod/          # Production cluster
├── k8s/               # Kubernetes manifests
│   ├── base/          # Base configurations (Kustomize)
│   └── overlays/      # Environment-specific overlays
├── policies/          # Conftest/OPA security policies
├── terraform/         # Infrastructure as Code
└── .github/           # CI/CD workflows

## Quick Start

### Prerequisites

- kubectl >= 1.28
- kustomize >= 5.0
- conftest >= 0.45 (for policy checks)
- ArgoCD (for GitOps deployment)

### Local Validation

```bash
# Validate policies
conftest test k8s/base -p policies/

# Build manifests
kustomize build k8s/overlays/dev

# Apply to dev cluster
kubectl apply -k k8s/overlays/dev
```

### GitOps Deployment

This repository is synced to clusters via ArgoCD:

- **Dev**: Auto-sync enabled, self-heal enabled
- **Staging**: Auto-sync enabled, manual promotion
- **Prod**: Manual sync only, requires approval

## Security Policies

All manifests must pass these checks before merge:

1. **No `:latest` tags** - All images must use specific version tags or SHA digests
2. **Run as non-root** - All pods must set `securityContext.runAsNonRoot: true`
3. **Resource limits** - All containers must define CPU/memory limits and requests
4. **No privileged containers** - `privileged: true` is blocked
5. **Network policies** - IMDS access (169.254.169.254) is explicitly blocked

## CI/CD Pipeline

Pull requests trigger:
1. Conftest policy validation
2. Kustomize build test
3. Kubernetes schema validation
4. Security scanning (if applicable)

Merge to `main` triggers:
- Auto-deployment to dev cluster
- Notification to #infra Slack channel

## kubectl + RBAC Configuration

Backend pods require these permissions:
- `pods` - get, list, watch
- `pods/log` - get
- `pods/exec` - create (for shell access)

See `k8s/base/rbac/` for RBAC manifests.

## Network Security

All backend pods are restricted by NetworkPolicy:
- Can access Kubernetes API server
- Can access internal services (Prometheus, etc.)
- **Cannot** access cloud metadata endpoint (169.254.169.254)
- Egress limited to required CIDRs only

## Secrets Management

Secrets are **never committed to git**. We use External Secrets Operator:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend  # or aws-secrets-manager
```

## Development Workflow

1. Create feature branch
2. Modify manifests in `k8s/base/` or `k8s/overlays/`
3. Run `conftest test k8s/base -p policies/` locally
4. Open PR
5. Wait for CI checks to pass
6. Request review
7. Merge triggers auto-deploy to dev

## Promotion to Production

1. Test in dev → validate in staging
2. Create PR to update `k8s/overlays/prod/`
3. Tag release: `git tag v1.2.3`
4. Manual ArgoCD sync to prod
5. Monitor rollout

## Troubleshooting

### Policy Check Failures

```bash
# Run locally to see failures
conftest test k8s/base -p policies/ --output table

# Common fixes:
# - Add runAsNonRoot: true
# - Replace :latest with :v1.2.3
# - Add resources.limits and resources.requests
```

### RBAC Issues

```bash
# Check ServiceAccount permissions
kubectl auth can-i list pods --as=system:serviceaccount:claude-hub:backend-sa

# View effective RBAC
kubectl describe clusterrole backend-k8s-read
```

### ArgoCD Sync Failures

```bash
# View sync status
argocd app get claude-hub-dev

# Force sync
argocd app sync claude-hub-dev --force

# View logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

## Documentation

- [Path B Implementation](docs/PATH-B-IMPLEMENTATION.md)
- [RBAC Minimums](docs/RBAC-MINIMUMS.md)
- [Security Baseline](docs/SECURITY-BASELINE.md)

## Related Repositories

- [claude-hub](https://github.com/SDotTatum/claude-hub) - Main application code
- [claude-hub-infra](https://github.com/SDotTatum/claude-hub-infra) - This repo

## License

MIT
