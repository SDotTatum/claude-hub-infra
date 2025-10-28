# Secrets Management with External Secrets Operator

This guide explains how Claude Hub manages secrets using the External Secrets Operator (ESO) pattern.

## Overview

**Never commit secrets to Git.** Instead, we use External Secrets Operator to sync secrets from external secret managers into Kubernetes Secrets.

```
┌─────────────────────┐
│ AWS Secrets Manager │
│  HashiCorp Vault    │  External Secret Manager
│  GCP Secret Manager │  (Source of Truth)
└──────────┬──────────┘
           │
           │ External Secrets
           │ Operator polls
           │ every 1 hour
           ▼
┌─────────────────────┐
│ Kubernetes Secrets  │  Auto-created, never committed
│ (claude-hub ns)     │  Used by pods
└─────────────────────┘
```

## Why External Secrets Operator?

**Problems with traditional approaches**:
- ❌ Hardcoded in manifests → Security risk
- ❌ Sealed Secrets → Hard to rotate
- ❌ Manual kubectl create secret → Not declarative

**Benefits of ESO**:
- ✅ **Single source of truth**: Secret manager is authoritative
- ✅ **Automatic rotation**: Secrets refresh periodically
- ✅ **Audit trail**: Secret manager logs all access
- ✅ **Access control**: IAM policies control who can read secrets
- ✅ **GitOps-friendly**: ExternalSecret manifests are declarative

## Installation

### 1. Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

### 2. Verify Installation

```bash
kubectl get pods -n external-secrets-system
kubectl get crd | grep external-secrets
```

You should see:
- `externalsecrets.external-secrets.io`
- `secretstores.external-secrets.io`
- `clustersecretstores.external-secrets.io`

## Configuration

### Step 1: Create ServiceAccount (Optional - for cloud IAM)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-sa
  namespace: claude-hub
  annotations:
    # AWS
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/ExternalSecretsRole

    # GCP
    iam.gke.io/gcp-service-account: external-secrets@project.iam.gserviceaccount.com
```

### Step 2: Create SecretStore

Choose one based on your secret manager:

#### AWS Secrets Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: claude-hub
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

#### HashiCorp Vault

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: claude-hub
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "claude-hub-role"
          serviceAccountRef:
            name: external-secrets-sa
```

#### Google Secret Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: gcpsm-secret-store
  namespace: claude-hub
spec:
  provider:
    gcpsm:
      projectID: "your-gcp-project-id"
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: your-cluster-name
          serviceAccountRef:
            name: external-secrets-sa
```

### Step 3: Create ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: claude-hub-secrets
  namespace: claude-hub
spec:
  refreshInterval: 1h  # How often to sync

  secretStoreRef:
    name: vault-backend  # Reference to SecretStore
    kind: SecretStore

  target:
    name: claude-hub-secrets  # Name of K8s Secret to create
    creationPolicy: Owner

  data:
  - secretKey: POSTGRES_PASSWORD
    remoteRef:
      key: claude-hub/postgres
      property: password
```

### Step 4: Use Secret in Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: claude-hub-backend
spec:
  template:
    spec:
      containers:
      - name: backend
        envFrom:
        - secretRef:
            name: claude-hub-secrets  # Auto-created by ESO
```

## Secret Organization

Organize secrets logically in your secret manager:

```
claude-hub/
├── postgres
│   ├── password
│   ├── username
│   └── host
├── supabase
│   ├── url
│   └── service_key
├── openai
│   └── api_key
├── anthropic
│   └── api_key
└── monitoring
    ├── grafana_admin_password
    └── prometheus_token
```

## Secret Rotation

### Automatic Rotation

ESO automatically syncs secrets based on `refreshInterval`:

```yaml
spec:
  refreshInterval: 1h  # Check every hour
```

When you update a secret in the secret manager:
1. ESO detects the change (within 1 hour)
2. Updates the Kubernetes Secret
3. Pods are NOT automatically restarted

### Trigger Pod Restart on Secret Change

Use [Reloader](https://github.com/stakater/Reloader):

```bash
helm install reloader stakater/reloader
```

Add annotation to Deployment:

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```

Now pods restart when secrets change.

## Troubleshooting

### ExternalSecret Not Syncing

```bash
# Check ExternalSecret status
kubectl describe externalsecret claude-hub-secrets -n claude-hub

# Check ESO operator logs
kubectl logs -n external-secrets-system \
  -l app.kubernetes.io/name=external-secrets
```

Common issues:
- **SecretStore misconfigured**: Check auth credentials
- **IAM permissions**: Ensure ServiceAccount has access
- **Secret path wrong**: Verify `remoteRef.key` exists in secret manager

### Secret Not Found in Secret Manager

```bash
# AWS
aws secretsmanager describe-secret --secret-id claude-hub/postgres

# GCP
gcloud secrets describe claude-hub-postgres

# Vault
vault kv get secret/claude-hub/postgres
```

### Pods Not Using Latest Secret

Force pod restart:

```bash
kubectl rollout restart deployment claude-hub-backend -n claude-hub
```

Or use Reloader (see above).

## Security Best Practices

### 1. Least Privilege IAM

**AWS IAM Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "arn:aws:secretsmanager:us-east-1:123456789:secret:claude-hub/*"
  }]
}
```

**Vault Policy**:
```hcl
path "secret/data/claude-hub/*" {
  capabilities = ["read", "list"]
}
```

### 2. Namespace Isolation

Use `SecretStore` (namespace-scoped) instead of `ClusterSecretStore`:

```yaml
kind: SecretStore  # ✅ Scoped to namespace
# NOT ClusterSecretStore  # ❌ Cluster-wide
```

### 3. Audit Logging

Enable audit logging in your secret manager:
- **AWS**: CloudTrail for Secrets Manager
- **Vault**: Audit devices
- **GCP**: Cloud Audit Logs

### 4. Secret Encryption at Rest

Kubernetes encrypts Secrets at rest by default (if enabled). Verify:

```bash
kubectl get secrets -n claude-hub -o yaml | grep encryption
```

### 5. Network Policies

Limit which pods can access secrets:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-only
spec:
  podSelector:
    matchLabels:
      app: claude-hub-backend
  policyTypes:
  - Ingress
```

## Migration Guide

### From Manual kubectl create secret

**Before**:
```bash
kubectl create secret generic claude-hub-secrets \
  --from-literal=POSTGRES_PASSWORD=mypassword
```

**After**:
1. Store secret in secret manager
2. Create ExternalSecret manifest
3. Apply: `kubectl apply -f external-secret.yaml`

### From Sealed Secrets

**Before**:
```bash
kubeseal < secret.yaml > sealed-secret.yaml
kubectl apply -f sealed-secret.yaml
```

**After**:
1. Decrypt Sealed Secret
2. Store values in secret manager
3. Delete Sealed Secret
4. Create ExternalSecret

## Local Development

For local development without a secret manager:

```yaml
# dev-secrets.yaml (DO NOT COMMIT)
apiVersion: v1
kind: Secret
metadata:
  name: claude-hub-secrets
  namespace: claude-hub
stringData:
  POSTGRES_PASSWORD: "dev-password"
  OPENAI_API_KEY: "sk-dev-..."
```

```bash
# Apply locally
kubectl apply -f dev-secrets.yaml

# Add to .gitignore
echo "dev-secrets.yaml" >> .gitignore
```

**For production**, always use ExternalSecret.

## Verification Checklist

- [ ] External Secrets Operator installed
- [ ] SecretStore configured with correct auth
- [ ] ExternalSecret manifests applied
- [ ] Secrets exist in secret manager
- [ ] IAM/RBAC permissions granted
- [ ] Kubernetes Secrets auto-created
- [ ] Pods can read secrets
- [ ] Reloader configured (optional)
- [ ] Audit logging enabled

## Related Documentation

- [External Secrets Operator Docs](https://external-secrets.io/)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
- [HashiCorp Vault](https://www.vaultproject.io/docs)
- [GCP Secret Manager](https://cloud.google.com/secret-manager/docs)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

## Next Steps

After setting up secrets management:

1. **Populate secret manager** with production secrets
2. **Test in dev cluster** with `kubectl describe externalsecret`
3. **Verify sync** with `kubectl get secrets`
4. **Deploy to prod** with ArgoCD
5. **Monitor sync status** in ArgoCD UI
