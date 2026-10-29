#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Automatically search for cluster-settings.yaml in common repo locations
SETTINGS_FILE=""
POSSIBLE_PATHS=(
    "$SCRIPT_DIR/cluster-settings.yaml"
    "$SCRIPT_DIR/../hack/cluster-settings.yaml"
    "$SCRIPT_DIR/../launch/cluster-settings.yaml"
    "$SCRIPT_DIR/../cluster-settings.yaml"
    "./cluster-settings.yaml"
    "./hack/cluster-settings.yaml"
    "./launch/cluster-settings.yaml"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SETTINGS_FILE="$path"
        break
    fi
done

echo "📁 Using settings file: ${SETTINGS_FILE:-None found (using defaults)}"

CONFIG_DIR="$(dirname "$SETTINGS_FILE")/../kubeconfigs"
if [ ! -d "$CONFIG_DIR" ]; then
    CONFIG_DIR="$SCRIPT_DIR/../kubeconfigs"
fi

if ! command -v yq &> /dev/null; then
    echo "❌ Error: 'yq' is required but not installed."
    exit 1
fi

echo "=================================================="
echo "🛡️ Security Check: Verifying NO Cluster Admin Privileges"
echo "=================================================="

# Extract names via yq with robust fallbacks if keys are missing
MENTOR_NAME=""
STUDENT_NAMES=""

if [ -f "$SETTINGS_FILE" ]; then
    MENTOR_NAME=$(yq eval '.mentor.name // ""' "$SETTINGS_FILE" -r 2>/dev/null || true)
    STUDENT_NAMES=$(yq eval '.students[].name // ""' "$SETTINGS_FILE" -r 2>/dev/null || true)
fi

# Fallback to standard names if yaml parsing returned nothing
[ -z "$MENTOR_NAME" ] || [ "$MENTOR_NAME" = "null" ] && MENTOR_NAME="mentor"
[ -z "$STUDENT_NAMES" ] || [ "$STUDENT_NAMES" = "null" ] && STUDENT_NAMES="student01 student02 student03"

ALL_USERS="$MENTOR_NAME $STUDENT_NAMES"

for user in $ALL_USERS; do
    [ -z "$user" ] || [ "$user" = "null" ] && continue
    config_file="$CONFIG_DIR/${user}-kubeconfig.yaml"
    
    echo "--------------------------------------------------"
    echo "🔍 Checking user: '$user'"
    
    if [ ! -f "$config_file" ]; then
        echo "❌ Error: Kubeconfig not found at '$config_file'."
        exit 1
    fi

    # Test 1: Check wildcard cluster-wide actions (* on *)
    if KUBECONFIG="$config_file" kubectl auth can-i '*' '*' --all-namespaces 2>/dev/null | grep -q "yes"; then
        echo "   ❌ SECURITY BREACH: '$user' has cluster-admin wildcard permissions (*/*)!"
        exit 1
    else
        echo "   ✓ Passed: '$user' does NOT have wildcard root privileges."
    fi

    # Test 2: Check cluster node listing
    if KUBECONFIG="$config_file" kubectl get nodes &>/dev/null; then
        echo "   ❌ SECURITY BREACH: '$user' has permission to list cluster nodes!"
        exit 1
    else
        echo "   ✓ Passed: '$user' cannot access cluster-scoped nodes."
    fi

    # Test 3: Check ClusterRoles viewing
    if KUBECONFIG="$config_file" kubectl get clusterroles &>/dev/null; then
        echo "   ❌ SECURITY BREACH: '$user' can view cluster-roles!"
        exit 1
    else
        echo "   ✓ Passed: '$user' cannot view cluster-scoped roles."
    fi
done

echo ""
echo "=================================================="
echo "✨ SUCCESS: Neither mentor nor any student has Cluster Admin privileges! ✨"
echo "=================================================="