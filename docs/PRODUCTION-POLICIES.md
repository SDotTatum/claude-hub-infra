# Production Security Policies

This document describes the additional security policies enforced for production deployments beyond the base security requirements.

## Overview

Production deployments must meet **stricter security standards** than dev/staging environments. These policies are enforced via Conftest in the CI pipeline and will block PRs that don't comply.

### Policy Files

- `policies/security.rego` - Base security policies (all environments)
- `policies/production.rego` - Additional production-only policies

## Production Requirements

### 1. SHA256 Digests Required

**Rule**: Production images MUST use SHA256 digests, not version tags

**Why**: Digest pins ensure immutability - the exact same image is deployed every time. Tags can be overwritten.

**Example**:
```yaml
# ❌ REJECTED in production
image: ghcr.io/sdottatum/backend:v1.2.3

# ✅ ACCEPTED in production
image: ghcr.io/sdottatum/backend@sha256:abc123...
```

**How to get digest**:
```bash
docker inspect ghcr.io/sdottatum/backend:v1.2.3 --format='{{index .RepoDigests 0}}'
```

---

### 2. Container Security Context

**Rule**: All production containers must define comprehensive security context

**Required Fields**:
```yaml
containers:
- name: app
  securityContext:
    runAsNonRoot: true                    # ✅ Required
    allowPrivilegeEscalation: false       # ✅ Required
    readOnlyRootFilesystem: true          # ✅ Required
    capabilities:
      drop: [ALL]                         # ✅ Required
```

**Why**: Defense-in-depth - even if an attacker gains code execution, these restrictions limit damage.

---

### 3. Pod Security Context

**Rule**: Production pods must define pod-level security context

**Required Fields**:
```yaml
spec:
  securityContext:
    runAsNonRoot: true         # ✅ Required
    runAsUser: 1000           # ✅ Must be >= 1000
    fsGroup: 1000             # ⚠️  Recommended if using volumes
    seccompProfile:
      type: RuntimeDefault    # ✅ Required (or Localhost)
```

**Why**:
- `runAsUser >= 1000` - Prevents running as system users (0-999)
- `seccompProfile` - Limits syscalls available to container
- `fsGroup` - Ensures proper volume permissions

---

### 4. Resource Limits and Requests

**Rule**: All production containers must define limits and requests

**Required**:
```yaml
containers:
- name: app
  resources:
    requests:
      cpu: "250m"      # ✅ Required
      memory: "512Mi"  # ✅ Required
    limits:
      cpu: "1000m"     # ✅ Required
      memory: "2Gi"    # ✅ Required
```

**Why**:
- Prevents resource exhaustion attacks
- Enables proper scheduling and QoS
- Cost management and capacity planning

**Guideline**: Set `limits` to 2-4x `requests` based on burst needs

---

### 5. Health Probes

**Rule**: Production containers must define liveness and readiness probes

**Required**:
```yaml
containers:
- name: app
  livenessProbe:          # ✅ Required
    httpGet:
      path: /health
      port: 8080
    initialDelaySeconds: 60
    periodSeconds: 30

  readinessProbe:         # ✅ Required
    httpGet:
      path: /ready
      port: 8080
    initialDelaySeconds: 30
    periodSeconds: 10
```

**Why**:
- Automatic recovery from hung processes
- Zero-downtime rolling updates
- Improved availability

---

### 6. High Availability

**Rule**: Production deployments must have `replicas >= 2`

**Required**:
```yaml
spec:
  replicas: 2  # ✅ Minimum 2 for HA
```

**Exception**: Add label to allow single replica:
```yaml
metadata:
  labels:
    allow-single-replica: "true"  # Only for specific use cases
```

**Why**: Single pod = single point of failure. HA requires multiple replicas.

**Recommendation**: Also create a PodDisruptionBudget:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-pdb
  labels:
    pdb-name: backend-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: backend
```

---

### 7. Environment Labeling

**Rule**: Production deployments must have `environment: prod` label

**Required**:
```yaml
metadata:
  labels:
    environment: prod  # ✅ Required in claude-hub-prod namespace
```

**Why**: Clear identification of environment for tooling, alerts, and dashboards.

---

## Policy Enforcement

### CI Pipeline

Policies are enforced in `.github/workflows/infra-ci.yaml`:

```yaml
- name: Validate production manifests against stricter policies
  run: |
    conftest test k8s/overlays/prod -p policies/production.rego --output table
```

**Result**: PR blocked if production policies fail

### Manual Testing

Test locally before pushing:

```bash
# Test production overlay
conftest test k8s/overlays/prod -p policies/production.rego

# Test specific file
conftest test k8s/overlays/prod/backend-deployment.yaml -p policies/production.rego --output table
```

---

## Policy Matrix

| Policy | Dev | Staging | Prod | Enforcement |
|--------|-----|---------|------|-------------|
| No :latest tags | ⚠️ Warn | ✅ Required | ✅ Required | CI |
| SHA256 digests | ❌ Not required | ⚠️ Recommended | ✅ Required | CI |
| runAsNonRoot | ✅ Required | ✅ Required | ✅ Required | CI |
| Resource limits | ⚠️ Recommended | ✅ Required | ✅ Required | CI |
| Health probes | ⚠️ Recommended | ⚠️ Recommended | ✅ Required | CI |
| Replicas >= 2 | ❌ Not required | ⚠️ Recommended | ✅ Required | CI |
| seccomp profile | ⚠️ Recommended | ⚠️ Recommended | ✅ Required | CI |
| readOnlyRootFS | ⚠️ Recommended | ⚠️ Recommended | ✅ Required | CI |

---

## Common Violations and Fixes

### Violation: Missing SHA256 Digest

**Error**:
```
Production deployment 'backend' container 'app' must use SHA256 digest (image@sha256:...), not version tags
```

**Fix**:
```bash
# Get the digest
docker pull ghcr.io/sdottatum/backend:v1.2.3
docker inspect ghcr.io/sdottatum/backend:v1.2.3 --format='{{index .RepoDigests 0}}'

# Update deployment
image: ghcr.io/sdottatum/backend@sha256:abc123...
```

---

### Violation: Missing Resource Limits

**Error**:
```
Production deployment 'backend' container 'app' must define resources.limits.cpu
```

**Fix**:
```yaml
containers:
- name: app
  resources:
    requests:
      cpu: "250m"
      memory: "512Mi"
    limits:
      cpu: "1000m"
      memory: "2Gi"
```

---

### Violation: Missing Health Probes

**Error**:
```
Production deployment 'backend' container 'app' must define livenessProbe
```

**Fix**:
```yaml
containers:
- name: app
  livenessProbe:
    httpGet:
      path: /health
      port: 8080
    initialDelaySeconds: 60
    periodSeconds: 30
  readinessProbe:
    httpGet:
      path: /ready
      port: 8080
    initialDelaySeconds: 30
    periodSeconds: 10
```

---

### Violation: Single Replica in Production

**Error**:
```
Production deployment 'backend' must have replicas >= 2 for HA
```

**Fix Option 1** (Recommended): Increase replicas
```yaml
spec:
  replicas: 2
```

**Fix Option 2**: Allow exception (use sparingly)
```yaml
metadata:
  labels:
    allow-single-replica: "true"
```

---

### Violation: Missing seccomp Profile

**Error**:
```
Production deployment 'backend' must set securityContext.seccompProfile.type
```

**Fix**:
```yaml
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
```

---

## Exemptions and Overrides

### Temporary Exemptions

In rare cases, you may need to temporarily bypass a policy. **This is strongly discouraged.**

If absolutely necessary:
1. Document the reason in the deployment annotation
2. Create an issue to track remediation
3. Get approval from security team
4. Set expiration date

```yaml
metadata:
  annotations:
    policy-exemption: "SHA256 digest required after registry migration"
    exemption-expires: "2025-11-15"
    exemption-issue: "https://github.com/org/repo/issues/123"
```

Then update the policy to check for exemption annotation (custom implementation required).

### Permanent Exceptions

Some workloads may require exceptions (e.g., debug pods, one-off jobs):

1. Use `allow-single-replica: "true"` label for non-HA workloads
2. Consider creating a separate namespace with relaxed policies
3. Document why the exception is needed

---

## Best Practices

### 1. Image Building

Build images with digests from CI:

```yaml
# .github/workflows/build.yaml
- name: Build and push image
  run: |
    docker build -t ghcr.io/sdottatum/backend:${GITHUB_SHA} .
    docker push ghcr.io/sdottatum/backend:${GITHUB_SHA}

    # Get and save digest
    DIGEST=$(docker inspect ghcr.io/sdottatum/backend:${GITHUB_SHA} --format='{{index .RepoDigests 0}}')
    echo "IMAGE_DIGEST=${DIGEST}" >> $GITHUB_OUTPUT
```

### 2. Automated Updates

Use renovate or dependabot to update image digests:

```json
// renovate.json
{
  "kubernetes": {
    "fileMatch": ["k8s/.*\\.yaml$"],
    "pinDigests": true
  }
}
```

### 3. Security Scanning

Scan images before deployment:

```bash
trivy image ghcr.io/sdottatum/backend@sha256:abc123...
```

Block deployment if high/critical vulnerabilities found.

### 4. Runtime Policy Enforcement

Consider adding OPA Gatekeeper for runtime enforcement:
- Policies checked at admission time
- Blocks non-compliant pods from being created
- Complements CI-time checks

---

## Related Documentation

- [Base Security Policies](../policies/security.rego)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST Container Security Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)

---

## Questions or Issues?

1. Check [troubleshooting section](#common-violations-and-fixes)
2. Review policy source: `policies/production.rego`
3. Open issue in infrastructure repo
4. Contact security team for exemption requests

---

*Last updated: 2025-10-28*
*Policy version: 1.0*
