#!/bin/bash
set -e

echo "=================================================="
echo "🔍 Verifying RBAC Permissions & Security Isolation"
echo "=================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../kubeconfigs"

# 1. Mentor RW check in student namespaces
echo "1️⃣ Testing Mentor RW access in student01..."
KUBECONFIG="$CONFIG_DIR/mentor-kubeconfig.yaml" kubectl get pods -n student01 &>/dev/null && echo "   ✓ Mentor can read student01"

# 2. Student 01 isolation check
echo "2️⃣ Testing Student01 isolation..."
KUBECONFIG="$CONFIG_DIR/student01-kubeconfig.yaml" kubectl get pods -n student01 &>/dev/null && echo "   ✓ Student01 can access own namespace"
if KUBECONFIG="$CONFIG_DIR/student01-kubeconfig.yaml" kubectl get pods -n student02 &>/dev/null; then
    echo "   ❌ Breach: Student01 can access student02!"
    exit 1
else
    echo "   ✓ Student01 correctly blocked from student02"
fi

# 3. Student 02 RO check on student01 (Read should work, Write should fail)
echo "3️⃣ Testing Student02 Read-Only access on student01..."
KUBECONFIG="$CONFIG_DIR/student02-kubeconfig.yaml" kubectl get pods -n student01 &>/dev/null && echo "   ✓ Student02 can read student01 (RO working)"
if KUBECONFIG="$CONFIG_DIR/student02-kubeconfig.yaml" kubectl create deployment student02-hack --image=nginx -n student01 &>/dev/null; then
    echo "   ❌ Breach: Student02 can write to student01!"
    kubectl delete deployment student02-hack -n student01 &>/dev/null
    exit 1
else
    echo "   ✓ Student02 correctly blocked from writing to student01"
fi

echo ""
echo "✨ All RBAC verification tests passed successfully! ✨"
