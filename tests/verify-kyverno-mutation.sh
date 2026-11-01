#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="$SCRIPT_DIR/manifests/mutate-person-label.yaml"

echo "=================================================="
echo "🛡️ Kyverno Mutation Verification: 'person' Label"
echo "=================================================="

# 1. Apply the mutation policy
echo "📂 Applying Kyverno Mutating ClusterPolicy..."
kubectl apply -f "$POLICY_FILE"

# Give Kyverno a moment to register the policy webhook
sleep 2

# 2. Test Student Namespace
echo "--------------------------------------------------"
echo "1️⃣ Testing Pod creation in student namespace ('student01')..."
kubectl run test-pod-student --image=nginx -n student01 --restart=Never --dry-run=client -o yaml | kubectl apply -f -

LABEL_STUDENT=$(kubectl get pod test-pod-student -n student01 -o jsonpath='{.metadata.labels.person}' 2>/dev/null || echo "")
echo "   Observed label 'person' in student01: '$LABEL_STUDENT'"

if [ "$LABEL_STUDENT" = "student" ]; then
    echo "   ✓ Success: Student pod correctly labeled with 'person=student'."
else
    echo "   ❌ Failure: Expected 'person=student', got '$LABEL_STUDENT'."
    exit 1
fi
kubectl delete pod test-pod-student -n student01 --grace-period=0 --force &>/dev/null

# 3. Test Mentor Namespace
echo "--------------------------------------------------"
echo "2️⃣ Testing Pod creation in mentor namespace ('mentor-system')..."
kubectl run test-pod-mentor --image=nginx -n mentor-system --restart=Never --dry-run=client -o yaml | kubectl apply -f -

LABEL_MENTOR=$(kubectl get pod test-pod-mentor -n mentor-system -o jsonpath='{.metadata.labels.person}' 2>/dev/null || echo "")
echo "   Observed label 'person' in mentor-system: '$LABEL_MENTOR'"

if [ "$LABEL_MENTOR" = "mentor" ]; then
    echo "   ✓ Success: Mentor pod correctly labeled with 'person=mentor'."
else
    echo "   ❌ Failure: Expected 'person=mentor', got '$LABEL_MENTOR'."
    exit 1
fi
kubectl delete pod test-pod-mentor -n mentor-system --grace-period=0 --force &>/dev/null

# 4. Test Other Namespace (default)
echo "--------------------------------------------------"
echo "3️⃣ Testing Pod creation in other namespace ('default')..."
kubectl run test-pod-default --image=nginx -n default --restart=Never --dry-run=client -o yaml | kubectl apply -f -

LABEL_DEFAULT=$(kubectl get pod test-pod-default -n default -o jsonpath='{.metadata.labels.person}' 2>/dev/null || echo "")
echo "   Observed label 'person' in default: '${LABEL_DEFAULT:-<none>}'"

if [ -z "$LABEL_DEFAULT" ]; then
    echo "   ✓ Success: Default namespace pod correctly left unlabeled."
else
    echo "   ❌ Failure: Pod in default namespace unexpectedly received label 'person=$LABEL_DEFAULT'."
    exit 1
fi
kubectl delete pod test-pod-default -n default --grace-period=0 --force &>/dev/null

echo ""
echo "=================================================="
echo "✨ SUCCESS: All Kyverno mutation tests passed perfectly! ✨"
echo "=================================================="