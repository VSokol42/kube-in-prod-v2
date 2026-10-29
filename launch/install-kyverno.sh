#!/bin/bash
set -e

echo "=================================================="
echo "📦 Installing Kyverno via Server-Side Apply (Forced)"
echo "=================================================="

KYVERNO_VERSION="v1.12.5"
INSTALL_URL="https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/install.yaml"

echo "🧹 Cleaning up any broken or partially applied resources..."
kubectl delete -f "$INSTALL_URL" --ignore-not-found=true || true

echo "🚀 Applying Kyverno manifest using server-side apply with force-conflicts..."
kubectl apply --server-side --force-conflicts -f "$INSTALL_URL"

echo "⏳ Waiting for Kyverno controllers to become ready..."
kubectl rollout status deployment/kyverno-admission-controller -n kyverno --timeout=120s
kubectl rollout status deployment/kyverno-reports-controller -n kyverno --timeout=120s
kubectl rollout status deployment/kyverno-cleanup-controller -n kyverno --timeout=120s

echo "✨ Kyverno installed and ready successfully! ✨"