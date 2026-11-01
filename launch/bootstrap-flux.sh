#!/bin/bash
set -e



SETTINGS_FILE="./infrastructure/cluster-settings.yaml"


cat $SETTINGS_FILE

if ! command -v flux &> /dev/null; then
    echo "❌ Error: Flux CLI is not installed. Please install it first (e.g., 'brew install fluxcd/tap/flux' or via curl)."
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN environment variable is not set."
    echo "   Run: export GITHUB_TOKEN=\"your_token\" before executing this script."
    exit 1
fi

if ! command -v yq &> /dev/null; then
    echo "❌ Error: 'yq' is required."
    exit 1
fi

CLUSTER_NAME=$(yq eval '.clusterName // "multi-node-cluster"' "$SETTINGS_FILE" -r)
GITHUB_OWNER="VSokol42"
GITHUB_REPO="kube-in-prod-v1"
BRANCH="module3"
TARGET_PATH="clusters/${CLUSTER_NAME}"

echo "=================================================="
echo "🚀 Bootstrapping Flux CD for GitOps"
echo "=================================================="
echo "Repository: github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
echo "Branch:     ${BRANCH}"
echo "Path:       ${TARGET_PATH}"
echo "=================================================="

# Run Flux bootstrap targeting the module5 branch
flux bootstrap github \
  --owner="${GITHUB_OWNER}" \
  --repository="${GITHUB_REPO}" \
  --branch="${BRANCH}" \
  --path="${TARGET_PATH}" \
  --personal \
  --components-extra=image-reflector-controller,image-automation-controller

echo "⏳ Waiting for Flux controllers to reconcile..."
flux check

echo ""
echo "=================================================="
echo "✨ Flux CD successfully bootstrapped! ✨"
echo "=================================================="