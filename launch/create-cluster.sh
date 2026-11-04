#!/bin/bash
set -e

# Automatically resolve the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$SCRIPT_DIR/cluster-settings.yaml"
KIND_CONFIG="$SCRIPT_DIR/kind-config.yaml"

echo $SCRIPT_DIR

# Load settings from cluster-settings.yaml (with Python3/yq fallback)
if command -v yq &> /dev/null; then
    CLUSTER_NAME=$(yq eval '.clusterName' "$SETTINGS_FILE")
    TIMEOUT=$(yq eval '.timeoutSeconds' "$SETTINGS_FILE")
elif command -v python3 &> /dev/null; then
    CLUSTER_NAME=$(python3 -c "import yaml; print(yaml.safe_load(open('$SETTINGS_FILE'))['clusterName'])")
    TIMEOUT=$(python3 -c "import yaml; print(yaml.safe_load(open('$SETTINGS_FILE'))['timeoutSeconds'])")
else
    CLUSTER_NAME="multi-node-cluster"
    TIMEOUT=90
fi

echo "=================================================="
echo "🚀 Creating KIND Cluster: '$CLUSTER_NAME'"
echo "=================================================="

# Check requirements
if ! command -v kind &> /dev/null; then
    echo "❌ Error: 'kind' is not installed."
    exit 1
fi

if [ ! -f "$KIND_CONFIG" ]; then
    echo "❌ Error: Kind config file not found at '$KIND_CONFIG'."
    exit 1
fi

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "⚠️ Cluster '$CLUSTER_NAME' already exists!"
    read -p "Do you want to delete it and recreate a fresh one? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️ Deleting existing cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
    else
        echo "Aborted."
        exit 0
    fi
fi

# Create cluster using the external config file path
echo "⏳ Provisioning cluster..."
kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"

# Post-creation: Wait for nodes and apply monitoring labels
echo "⏳ Waiting for nodes to become ready (timeout: ${TIMEOUT}s)..."
kubectl wait --for=condition=Ready nodes --all --timeout="${TIMEOUT}s"

echo "🏷️ Applying Prometheus monitoring labels to worker nodes..."
kubectl label node "${CLUSTER_NAME}-worker" node-group=workers --overwrite=true || true
kubectl label node "${CLUSTER_NAME}-worker2" node-group=workers --overwrite=true || true
kubectl label node "${CLUSTER_NAME}-worker3" node-group=workers --overwrite=true || true

echo ""
echo "✨ SUCCESS: Cluster '$CLUSTER_NAME' is ready! ✨"