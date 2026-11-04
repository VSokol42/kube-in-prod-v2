#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$SCRIPT_DIR/cluster-settings.yaml"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"
OUTPUT_DIR="$SCRIPT_DIR/../kubeconfigs"
mkdir -p "$OUTPUT_DIR"

if ! command -v yq &> /dev/null; then
    echo "❌ Error: 'yq' is required but not installed."
    exit 1
fi

CLUSTER_NAME=$(yq eval '.clusterName' "$SETTINGS_FILE")

echo "=================================================="
echo "🛡️ Applying Static RBAC Manifests & Generating Kubeconfigs"
echo "=================================================="

# Apply static YAML manifests
kubectl apply -f "$MANIFESTS_DIR/namespaces-accounts.yaml"
kubectl apply -f "$MANIFESTS_DIR/rbac-policies.yaml"

# Helper to generate isolated kubeconfig files for each user
generate_kubeconfig() {
    local user_name=$1
    local user_ns=$2
    local config_out="$OUTPUT_DIR/${user_name}-kubeconfig.yaml"

    echo "🔑 Generating kubeconfig for $user_name..."
    
    # Create static long-lived token secret for ServiceAccount
    kubectl apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: ${user_name}-token
  namespace: ${user_ns}
  annotations:
    kubernetes.io/service-account.name: "${user_name}"
type: kubernetes.io/service-account-token
EOF

    local server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    local ca_data=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    
    local token=""
    for i in {1..5}; do
        token=$(kubectl get secret "${user_name}-token" -n "${user_ns}" -o jsonpath='{.data.token}' 2>/dev/null | base64 --decode || true)
        if [ -n "$token" ]; then break; fi
        sleep 1
    done

    cat <<EOF > "$config_out"
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${ca_data}
    server: ${server}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    namespace: ${user_ns}
    user: ${user_name}
  name: ${user_name}-context
current-context: ${user_name}-context
users:
- name: ${user_name}
  user:
    token: ${token}
EOF
}

# Generate kubeconfigs for mentor and all 3 students
generate_kubeconfig "mentor" "mentor-system"
generate_kubeconfig "student01" "student01"
generate_kubeconfig "student02" "student02"
generate_kubeconfig "student03" "student03"

echo "✨ RBAC applied and kubeconfigs saved to 'kubeconfigs/'! ✨"