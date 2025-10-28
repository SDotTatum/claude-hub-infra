#!/bin/bash
set -euo pipefail

# Install ArgoCD to Kubernetes cluster
# Based on: https://argo-cd.readthedocs.io/en/stable/getting_started/

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.9.3}"
NAMESPACE="${NAMESPACE:-argocd}"

echo "🚀 Installing ArgoCD ${ARGOCD_VERSION}..."
echo ""

# Check kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ kubectl is not configured. Please set KUBECONFIG or run 'kubectl config use-context <context>'"
    exit 1
fi

echo "📋 Current cluster:"
kubectl config current-context
echo ""

read -p "Install ArgoCD to this cluster? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Create namespace
echo "📦 Creating namespace ${NAMESPACE}..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "📥 Installing ArgoCD ${ARGOCD_VERSION}..."
kubectl apply -n ${NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml

# Wait for rollout
echo "⏳ Waiting for ArgoCD to be ready (this may take 2-3 minutes)..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    deployment/argocd-repo-server \
    deployment/argocd-dex-server \
    -n ${NAMESPACE}

echo ""
echo "✅ ArgoCD installed successfully!"
echo ""
echo "📋 Next steps:"
echo ""
echo "1. Get admin password:"
echo "   kubectl -n ${NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "2. Port-forward to access UI:"
echo "   kubectl port-forward svc/argocd-server -n ${NAMESPACE} 8080:443"
echo "   Then visit: https://localhost:8080"
echo ""
echo "3. Login:"
echo "   Username: admin"
echo "   Password: (from step 1)"
echo ""
echo "4. Install ArgoCD CLI (optional):"
echo "   curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
echo "   chmod +x argocd"
echo "   sudo mv argocd /usr/local/bin/"
echo ""
echo "5. Create Applications:"
echo "   kubectl apply -f clusters/dev/argocd/applications/"
echo ""
echo "📊 ArgoCD status:"
kubectl get pods -n ${NAMESPACE}
