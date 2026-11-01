#!/bin/bash
set -e

echo "=================================================="
echo "🔍 Verifying Flux CD Installation & Reconciliation"
echo "=================================================="

# 1. Check if the flux-system namespace exists
if ! kubectl get namespace flux-system &>/dev/null; then
    echo "❌ Error: Namespace 'flux-system' not found. Flux is not installed."
    exit 1
fi
echo "   ✓ Namespace 'flux-system' exists."

# 2. Check if Flux CLI is available
if ! command -v flux &> /dev/null; then
    echo "❌ Error: Flux CLI is not installed."
    exit 1
fi

# 3. Check deployment status of core Flux controllers
echo "⏳ Checking Flux core controller deployments..."
CONTROLLERS=(
    "source-controller"
    "kustomize-controller"
    "helm-controller"
    "notification-controller"
)

for ctrl in "${CONTROLLERS[@]}"; do
    if kubectl rollout status deployment/$ctrl -n flux-system --timeout=30s &>/dev/null; then
        echo "   ✓ Deployment '$ctrl' is ready."
    else
        echo "   ❌ Error: Deployment '$ctrl' failed or timed out."
        exit 1
    fi
done

# 4. Run native Flux health check
echo "🏥 Running 'flux check'..."
if flux check; then
    echo "   ✓ Flux check passed successfully."
else
    echo "   ❌ Error: 'flux check' reported issues."
    exit 1
fi

# 5. Check GitRepository source reconciliation status
echo "🔗 Verifying Git repository synchronization status..."
if kubectl get gitrepository flux-system -n flux-system &>/dev/null; then
    READY_STATUS=$(kubectl get gitrepository flux-system -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$READY_STATUS" = "True" ]; then
        echo "   ✓ GitRepository 'flux-system' is successfully synced."
    else
        echo "   ⚠️ Warning: GitRepository 'flux-system' is not ready yet (Status: $READY_STATUS)."
        kubectl describe gitrepository flux-system -n flux-system
        exit 1
    fi
else
    echo "   ❌ Error: GitRepository resource 'flux-system' not found."
    exit 1
fi

echo ""
echo "=================================================="
echo "✨ SUCCESS: Flux CD is installed and healthy! ✨"
echo "=================================================="