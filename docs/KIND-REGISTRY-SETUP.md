# KIND Local Registry Setup

This guide explains how to set up a local KIND (Kubernetes IN Docker) cluster with a container registry for fast development iteration.

## Why Local Registry?

**Benefits**:
- ⚡ **Fast image builds**: No network upload time
- 💰 **Cost-free**: No cloud registry charges
- 🔒 **Private**: Images never leave your machine
- 🚀 **Rapid iteration**: Build → Deploy in seconds

**Use Cases**:
- Local development with Tilt
- CI testing without external dependencies
- Offline development
- Testing image building pipeline

## Prerequisites

```bash
# Install KIND
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Verify Docker is running
docker info
```

## Setup

### 1. Create KIND Cluster with Registry

```bash
cd claude-hub-infra
./scripts/setup-kind-registry.sh
```

**What this does**:
1. Creates a Docker registry container on `localhost:5001`
2. Creates a KIND cluster named `claude-hub-dev`
3. Connects registry to cluster network
4. Configures containerd to use the local registry

### 2. Configure kubectl Context

```bash
# Switch to KIND cluster
kubectl config use-context kind-claude-hub-dev

# Verify
kubectl get nodes
kubectl cluster-info
```

### 3. Build and Push Images

```bash
# Build backend image
cd ../claude-hub/python
docker build -f Dockerfile.server -t localhost:5001/claude-hub-backend:latest .

# Push to local registry
docker push localhost:5001/claude-hub-backend:latest

# Verify it's in the registry
curl http://localhost:5001/v2/_catalog
# Expected output: {"repositories":["claude-hub-backend"]}
```

### 4. Update Kubernetes Manifests

Change image references to use `localhost:5001/`:

```yaml
# Before
image: ghcr.io/sdottatum/claude-hub-backend:v1.0.0

# After (for local development)
image: localhost:5001/claude-hub-backend:latest
imagePullPolicy: Always  # Force pull from local registry
```

## Using with Tilt

Add to your `Tiltfile`:

```python
# Tell Tilt about the local registry
allow_k8s_contexts('kind-claude-hub-dev')

# Build images and push to local registry
docker_build(
    'localhost:5001/claude-hub-backend',
    './python',
    dockerfile='./python/Dockerfile.server'
)

# Apply K8s manifests
k8s_yaml('k8s/base/server-deployment.yaml')

# Watch for changes
k8s_resource('claude-hub-backend', port_forwards='9181:9181')
```

Then run:

```bash
tilt up
```

Tilt will automatically:
- Build images on code changes
- Push to local registry
- Update Kubernetes deployments
- Show logs in dashboard

## Verification

### Check Registry Status

```bash
# Registry container
docker ps --filter "name=kind-registry"

# Registry contents
curl http://localhost:5001/v2/_catalog

# Specific image tags
curl http://localhost:5001/v2/claude-hub-backend/tags/list
```

### Check Cluster Status

```bash
# Cluster info
kind get clusters
kubectl cluster-info --context kind-claude-hub-dev

# Registry ConfigMap
kubectl get configmap local-registry-hosting -n kube-public -o yaml
```

### Test Image Pull from Pod

```bash
# Create test pod
kubectl run test-registry \
  --image=localhost:5001/claude-hub-backend:latest \
  --rm -it --restart=Never \
  -- /bin/sh -c "echo 'Registry works!'"

# If successful, pod should start and echo the message
```

## Troubleshooting

### Registry Not Accessible from Pods

**Symptom**: `ErrImagePull` or `ImagePullBackOff` in pod status

**Solution**:
```bash
# Verify registry is connected to KIND network
docker inspect kind-registry | grep -A 5 Networks

# Should show "kind" network
# If not:
docker network connect kind kind-registry
```

### Registry Lost After Docker Restart

**Symptom**: Registry container stopped

**Solution**:
```bash
# Registry is set to --restart=always, but check:
docker start kind-registry

# Or re-run setup script:
./scripts/setup-kind-registry.sh
```

### Images Not Pulling

**Symptom**: Pod uses old image version

**Solution**:
```bash
# Force pull latest
kubectl set image deployment/claude-hub-backend \
  backend=localhost:5001/claude-hub-backend:latest-$(date +%s)

# Or add imagePullPolicy: Always to deployment
```

### KIND Cluster Networking Issues

**Symptom**: Registry cannot resolve or connect

**Solution**:
```bash
# Delete and recreate cluster
kind delete cluster --name claude-hub-dev
./scripts/setup-kind-registry.sh

# This rebuilds with correct containerd config
```

## Cleanup

### Remove Cluster (Keep Registry)

```bash
kind delete cluster --name claude-hub-dev
```

### Remove Registry (Keep Cluster)

```bash
docker stop kind-registry
docker rm kind-registry
```

### Remove Everything

```bash
kind delete cluster --name claude-hub-dev
docker stop kind-registry
docker rm kind-registry
```

## Advanced Configuration

### Custom Registry Port

```bash
export REGISTRY_PORT=5002
./scripts/setup-kind-registry.sh
```

### Multi-Node Cluster

Edit `scripts/setup-kind-registry.sh` and add more nodes:

```yaml
nodes:
- role: control-plane
- role: worker
- role: worker
```

### Use with Existing KIND Cluster

The script checks for existing clusters and prompts before recreating.

## Integration with CI/CD

For CI pipelines, run the setup script in `before_script`:

```yaml
# .gitlab-ci.yml
test:
  before_script:
    - ./scripts/setup-kind-registry.sh
  script:
    - docker build -t localhost:5001/app:test .
    - docker push localhost:5001/app:test
    - kubectl apply -f k8s/
```

## Security Notes

- ⚠️ **Local only**: Registry is bound to `127.0.0.1` - not accessible externally
- ⚠️ **No authentication**: Suitable for local development only
- ⚠️ **No TLS**: Communication is HTTP, not HTTPS
- ✅ **Isolated network**: Registry only accessible within KIND network

## Related Documentation

- [KIND Local Registry Documentation](https://kind.sigs.k8s.io/docs/user/local-registry/)
- [Tilt Documentation](https://docs.tilt.dev/)
- [Docker Registry Configuration](https://docs.docker.com/registry/configuration/)

## Next Steps

After setting up the local registry:

1. **Update Tiltfile** to use `localhost:5001/` for all images
2. **Apply RBAC manifests** from this repo: `kubectl apply -k k8s/base`
3. **Deploy backend** with kubectl access: See `docs/PATH-B-IMPLEMENTATION.md`
4. **Test K8s features**: Pod Logs and Pod Shell should now work
