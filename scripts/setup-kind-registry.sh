#!/bin/bash
set -euo pipefail

# Setup KIND cluster with local registry for fast development
# Based on: https://kind.sigs.k8s.io/docs/user/local-registry/

CLUSTER_NAME="${CLUSTER_NAME:-claude-hub-dev}"
REGISTRY_NAME="${REGISTRY_NAME:-kind-registry}"
REGISTRY_PORT="${REGISTRY_PORT:-5001}"

echo "🚀 Setting up KIND cluster with local registry..."
echo ""
echo "Configuration:"
echo "  Cluster: ${CLUSTER_NAME}"
echo "  Registry: ${REGISTRY_NAME}"
echo "  Registry Port: ${REGISTRY_PORT}"
echo ""

# Check if KIND is installed
if ! command -v kind &> /dev/null; then
    echo "❌ KIND not found. Installing..."
    echo "Please install KIND: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Create registry container unless it already exists
if [ "$(docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null || true)" != 'true' ]; then
    echo "📦 Creating local registry container..."
    docker run \
        -d --restart=always \
        -p "127.0.0.1:${REGISTRY_PORT}:5000" \
        --name "${REGISTRY_NAME}" \
        registry:2
    echo "✅ Registry started on localhost:${REGISTRY_PORT}"
else
    echo "✅ Registry already running on localhost:${REGISTRY_PORT}"
fi

# Create KIND cluster with containerd registry config dir enabled
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "⚠️  Cluster ${CLUSTER_NAME} already exists"
    read -p "Delete and recreate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Deleting existing cluster..."
        kind delete cluster --name "${CLUSTER_NAME}"
    else
        echo "Keeping existing cluster. Skipping to registry configuration..."
        SKIP_CLUSTER_CREATE=true
    fi
fi

if [ "${SKIP_CLUSTER_CREATE:-false}" != "true" ]; then
    echo "🏗️  Creating KIND cluster..."
    cat <<EOF | kind create cluster --name="${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REGISTRY_PORT}"]
    endpoint = ["http://${REGISTRY_NAME}:5000"]
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
    echo "✅ Cluster created"
fi

# Connect the registry to the cluster network if not already connected
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${REGISTRY_NAME}")" = 'null' ]; then
    echo "🔗 Connecting registry to cluster network..."
    docker network connect "kind" "${REGISTRY_NAME}"
    echo "✅ Registry connected to cluster network"
else
    echo "✅ Registry already connected to cluster network"
fi

# Document the local registry
echo "📝 Documenting local registry..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 Next steps:"
echo ""
echo "1. Build and push an image:"
echo "   docker build -t localhost:${REGISTRY_PORT}/claude-hub-backend:latest ."
echo "   docker push localhost:${REGISTRY_PORT}/claude-hub-backend:latest"
echo ""
echo "2. Use in Kubernetes:"
echo "   image: localhost:${REGISTRY_PORT}/claude-hub-backend:latest"
echo ""
echo "3. Verify registry is working:"
echo "   curl http://localhost:${REGISTRY_PORT}/v2/_catalog"
echo ""
echo "4. Set KUBECONFIG for this cluster:"
echo "   export KUBECONFIG=\$(kind get kubeconfig --name=${CLUSTER_NAME})"
echo ""
echo "🔧 Cluster info:"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
echo ""
echo "📦 Registry info:"
docker ps --filter "name=${REGISTRY_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
