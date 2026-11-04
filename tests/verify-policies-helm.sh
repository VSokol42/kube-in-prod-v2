#!/bin/bash
set -e

RELEASE_NAME="kyverno-policies"

echo "=================================================="
echo "🔍 Verifying Kyverno Helm Policies"
echo "=================================================="

# 1. Verify Helm Release Status
if helm status "$RELEASE_NAME" -n kyverno &>/dev/null; then
    echo "   ✓ Helm release '$RELEASE_NAME' is installed and active."
else
    echo "   ❌ Error: Helm release '$RELEASE_NAME' is not found in namespace 'kyverno'."
    exit 1
fi

# 2. Test Mutation Policy ('person' label)
echo "--------------------------------------------------"
echo "1️⃣ Testing Mutation Policy ('person' label)..."

# Student namespace test
kubectl run test-pod-student --image=nginx -n student01 --restart=Never --dry-run=client -o yaml | kubectl apply -f -
LABEL_STUDENT=$(kubectl get pod test-pod-student -n student01 -o jsonpath='{.metadata.labels.person}' 2>/dev/null || echo "")
if [ "$LABEL_STUDENT" = "student" ]; then
    echo "   ✓ Success: Student pod correctly received 'person=student'."
else
    echo "   ❌ Failure: Expected 'person=student', got '$LABEL_STUDENT'."
    exit 1
fi
kubectl delete pod test-pod-student -n student01 --grace-period=0 --force &>/dev/null

# Mentor namespace test
kubectl run test-pod-mentor --image=nginx -n mentor-system --restart=Never --dry-run=client -o yaml | kubectl apply -f -
LABEL_MENTOR=$(kubectl get pod test-pod-mentor -n mentor-system -o jsonpath='{.metadata.labels.person}' 2>/dev/null || echo "")
if [ "$LABEL_MENTOR" = "mentor" ]; then
    echo "   ✓ Success: Mentor pod correctly received 'person=mentor'."
else
    echo "   ❌ Failure: Expected 'person=mentor', got '$LABEL_MENTOR'."
    exit 1
fi
kubectl delete pod test-pod-mentor -n mentor-system --grace-period=0 --force &>/dev/null


# 3. Test Audit Policy (Read-Only Root Filesystem)
echo "--------------------------------------------------"
echo "2️⃣ Testing Audit Policy (Read-Only Root Filesystem)..."

TEST_POD="audit-test-nginx"
kubectl run "$TEST_POD" --image=nginx --namespace="default" --dry-run=client -o yaml | kubectl apply -f -

echo "⏳ Waiting for non-compliant audit test pod to start..."
kubectl wait --for=condition=Ready pod/"$TEST_POD" -n "default" --timeout=30s
echo "   ✓ Audit mode successfully allowed non-compliant pod to run."

# Cleanup test pod
kubectl delete pod "$TEST_POD" -n "default" --grace-period=0 --force &>/dev/null

echo ""
echo "=================================================="
echo "✨ SUCCESS: All Helm-managed Kyverno policies verified! ✨"
echo "=================================================="