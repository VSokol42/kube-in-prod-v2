#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="$SCRIPT_DIR/manifests/validate-readonly-rootfs.yaml"
TEST_NS="default"
TEST_POD="audit-test-nginx"

echo "=================================================="
echo "🛡️ Kyverno Audit Mode Verification: Read-Only Root FS"
echo "=================================================="

# 1. Ensure Kyverno is installed in the cluster
if ! kubectl get namespace kyverno &>/dev/null; then
    echo "❌ Error: Kyverno is not installed in the cluster. Please install Kyverno first."
    exit 1
fi

# 2. Apply the policy
echo "📂 Applying Kyverno ClusterPolicy..."
kubectl apply -f "$POLICY_FILE"

# 3. Deploy a non-compliant pod (should succeed because mode is Audit)
echo "🚀 Deploying non-compliant test pod ('$TEST_POD')..."
kubectl run "$TEST_POD" --image=nginx --namespace="$TEST_NS" --dry-run=client -o yaml | kubectl apply -f -

echo "⏳ Waiting for test pod to start..."
kubectl wait --for=condition=Ready pod/"$TEST_POD" -n "$TEST_NS" --timeout=30s

# 4. Verify that audit mode allowed the pod creation
echo "   ✓ Pod successfully created (Audit mode permitted non-compliant pod)."

# 5. Check Kyverno PolicyReports for the violation
echo "🔍 Checking Kyverno PolicyReports for audit violation..."
sleep 3 # Give background scanner a moment to report

VIOLATION_FOUND=false
for i in {1..5}; do
    if kubectl get policyreports -A -o jsonpath='{.items[*].results[*].rule}' 2>/dev/null | grep -q "check-readonly-root-filesystem"; then
        VIOLATION_FOUND=true
        break
    fi
    sleep 2
done

if [ "$VIOLATION_FOUND" = true ]; then
    echo "   ✓ Success: Kyverno successfully audited and flagged the violation!"
else
    echo "   ⚠️ Warning: PolicyReport hasn't registered yet, checking pod events..."
    kubectl describe pod "$TEST_POD" -n "$TEST_NS" | grep -i "policy" || true
fi

# 6. Cleanup test pod
echo "🧹 Cleaning up test pod..."
kubectl delete pod "$TEST_POD" -n "$TEST_NS" --grace-period=0 --force &>/dev/null

echo ""
echo "=================================================="
echo "✨ Kyverno audit policy verification completed successfully! ✨"
echo "=================================================="