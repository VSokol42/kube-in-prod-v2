#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$SCRIPT_DIR/cluster-settings.yaml"

# Load cluster name
if command -v yq &> /dev/null; then
    CLUSTER_NAME=$(yq eval '.clusterName' "$SETTINGS_FILE")
elif command -v python3 &> /dev/null; then
    CLUSTER_NAME=$(python3 -c "import yaml; print(yaml.safe_load(open('$SETTINGS_FILE'))['clusterName'])")
else
    CLUSTER_NAME="multi-node-cluster"
fi

echo "=================================================="
echo "🔍 Verifying KIND Cluster: '$CLUSTER_NAME'"
echo "=================================================="

# 1. Check if cluster exists in Kind
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "❌ Cluster '$CLUSTER_NAME' is NOT running or not found."
    exit 1
fi
echo "✓ Kind cluster status: Running"

# 2. Check Kubectl context and nodes
echo ""
echo "--- Kubernetes Nodes & Status ---"
if kubectl cluster-info &> /dev/null; then
    kubectl get nodes -o wide --show-labels
else
    echo "❌ Error: Cannot connect to Kubernetes API. Check your kubeconfig."
    exit 1
fi

# 3. Check Mapped Ports/Endpoints
echo ""
echo "--- Docker Container & Port Mapping Check ---"
docker ps --filter "name=${CLUSTER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "✨ Verification Complete: Cluster is healthy and accessible! ✨"