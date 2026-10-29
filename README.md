# kube-in-prod-v2
Homeworks for course "Kubernetes in Production" ver2
# Tasks
Module 02 – Security & Policy as Code

1.Створити Kubernetes кластер з неймспейсом для ментора і 3 неймспейсами для студентів (e.g. student01, student02, student03)

Ментор і кожний студент мають мати окремі kubeconfig файли.

Впровадити RBAC:

- Ментор повинен мати RW доступ до неймспейсів студентів

- 01 і 03 студенти мають RW доступи тільки до своїх неймспейсів

- Студент 02 має RO доступ до неймспейсу студента 01 і неймспейсу default

- Ані ментор, ані студенти не повинні мати права Cluster Admin

2. Створити Kyverno policy для валідації readonly root filesystem в режимі аудиту.

3. Створити Kyverno policy для додавання label "person" в поди. В студентських неймспейсах цей label має мати значення "student", у ментора відповідно "mentor", всі інші неймспейси не мають мати цього лейбла взагалі.

 

Module 03 – Platform Engineering

1. Налаштувати GitOps систему (ArgoCD, Flux etc.) для майбутніх змін.

2. Переписати полісі з ДЗ Module02 на використання Helm чартів

 

Module 04 – Service Mesh

1. Встановити Istio servicemesh в режимі sidecar

2. Створити Kyverno policy всі поди з лейблом "person: student" буде запускати з istio-sidecar контейнером

 

Module 05 – Observability & Troubleshooting

1. Додати в кластер моніторинг систему (на ваш вибір).

2. Створити дашборд для відстеження навантаження на ноди по студентським неймспейсам.

3. Створити дашборд і алярм при знаходженні в логах поди сповіщення про не проходження аудиту по readonly root filesystem.

# Solution for module 02

## 1. Cluster creation

Let use Kind WSL2. Kind cluster will be consist of control plane and 3 worker nodes, with networking for future solutions.

All scripts (create/verify) and configs for kind cluster will be placed on dir *launch* 

Configs:

*cluster-settings.yaml* - cluster's base definition - name, kubernetes version, startup timeout.

```yaml
clusterName: "my-cluster-v1"
kubernetesVersion: "v1.27.3"
timeoutSeconds: 90
```

*kind-config.yaml* - Kind cluster manifest, with ports mapping for Nginx, Grafana and Prometheus for next tasks

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "127.0.0.1"
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
      - containerPort: 9090
        hostPort: 9090
        protocol: TCP
      - containerPort: 30000
        hostPort: 30000
        protocol: TCP
  - role: worker
  - role: worker
  - role: worker
```

Scripts:

*create-cluster.sh* - create cluster with configs on the same dir (using mikefarah/yq for pasring yaml), wait for nodes to be ready and aplly custom label to workers

```bash
#!/bin/bash
set -e

# Automatically resolve the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$SCRIPT_DIR/cluster-settings.yaml"
KIND_CONFIG="$SCRIPT_DIR/kind-config.yaml"

echo $SCRIPT_DIR

# Load settings from cluster-settings.yaml (with Python3/yq fallback)
if command -v yq &> /dev/null; then
    CLUSTER_NAME=$(yq eval '.clusterName' "$SETTINGS_FILE")
    TIMEOUT=$(yq eval '.timeoutSeconds' "$SETTINGS_FILE")
elif command -v python3 &> /dev/null; then
    CLUSTER_NAME=$(python3 -c "import yaml; print(yaml.safe_load(open('$SETTINGS_FILE'))['clusterName'])")
    TIMEOUT=$(python3 -c "import yaml; print(yaml.safe_load(open('$SETTINGS_FILE'))['timeoutSeconds'])")
else
    CLUSTER_NAME="multi-node-cluster"
    TIMEOUT=90
fi

echo "=================================================="
echo "🚀 Creating KIND Cluster: '$CLUSTER_NAME'"
echo "=================================================="

# Check requirements
if ! command -v kind &> /dev/null; then
    echo "❌ Error: 'kind' is not installed."
    exit 1
fi

if [ ! -f "$KIND_CONFIG" ]; then
    echo "❌ Error: Kind config file not found at '$KIND_CONFIG'."
    exit 1
fi

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "⚠️ Cluster '$CLUSTER_NAME' already exists!"
    read -p "Do you want to delete it and recreate a fresh one? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️ Deleting existing cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
    else
        echo "Aborted."
        exit 0
    fi
fi

# Create cluster using the external config file path
echo "⏳ Provisioning cluster..."
kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"

# Post-creation: Wait for nodes and apply monitoring labels
echo "⏳ Waiting for nodes to become ready (timeout: ${TIMEOUT}s)..."
kubectl wait --for=condition=Ready nodes --all --timeout="${TIMEOUT}s"

echo "🏷️ Applying Prometheus monitoring labels to worker nodes..."
kubectl label node "${CLUSTER_NAME}-worker" node-group=workers --overwrite=true || true
kubectl label node "${CLUSTER_NAME}-worker2" node-group=workers --overwrite=true || true
kubectl label node "${CLUSTER_NAME}-worker3" node-group=workers --overwrite=true || true

echo ""
echo "✨ SUCCESS: Cluster '$CLUSTER_NAME' is ready! ✨"
```

*verify-cluster.sh* - checks if the cluster is alive, verifies node readiness, tests labels, and prints connection details

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$SCRIPT_DIR/cluster-settings.yaml"

# Load cluster name
if command -v yq &> /dev/null; then
    CLUSTER_NAME=$(yq eval '.clusterName' "$SETTINGS_FILE")
elif command -v python3 &> /dev/null; then
    CLUSTER_NAME=$(python3 -c "import yaml; print(yaml.safe_load(open('$SETTINGS_FILE'))['clusterName'])")
else
    CLUSTER_NAME="multi-node-cluster"
fi

echo "=================================================="
echo "🔍 Verifying KIND Cluster: '$CLUSTER_NAME'"
echo "=================================================="

# 1. Check if cluster exists in Kind
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "❌ Cluster '$CLUSTER_NAME' is NOT running or not found."
    exit 1
fi
echo "✓ Kind cluster status: Running"

# 2. Check Kubectl context and nodes
echo ""
echo "--- Kubernetes Nodes & Status ---"
if kubectl cluster-info &> /dev/null; then
    kubectl get nodes -o wide --show-labels
else
    echo "❌ Error: Cannot connect to Kubernetes API. Check your kubeconfig."
    exit 1
fi

# 3. Check Mapped Ports/Endpoints
echo ""
echo "--- Docker Container & Port Mapping Check ---"
docker ps --filter "name=${CLUSTER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "✨ Verification Complete: Cluster is healthy and accessible! ✨"
```

## 2. Kyverno policy creation for ro

## 3. Kyverno policy creation 