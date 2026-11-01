#!/bin/bash
set -e

CHART_PATH="./charts/kyverno-policies"
RELEASE_NAME="kyverno-policies"

echo "=================================================="
echo "📦 Deploying Kyverno Policies via Helm Chart"
echo "=================================================="

if ! command -v helm &> /dev/null; then
    echo "❌ Error: Helm CLI is required but not installed."
    exit 1
fi

if [ ! -d "$CHART_PATH" ]; then
    echo "❌ Error: Chart directory not found at '$CHART_PATH'."
    exit 1
fi

echo "🚀 Installing/Upgrading Helm release '$RELEASE_NAME'..."
helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" --namespace kyverno

echo "✨ Kyverno policies Helm chart deployed successfully! ✨"