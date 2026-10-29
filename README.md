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

Launch scripts to:

Create cluster

**./launch/create-cluster.sh**


Output:

```
/mnt/d/study/k8s/kube-in-prod-v2/launch
==================================================
🚀 Creating KIND Cluster: 'my-cluster-v1'
==================================================
⏳ Provisioning cluster...
Creating cluster "my-cluster-v1" ...
 ✓ Ensuring node image (kindest/node:v1.37.0) 🖼️
 ✓ Preparing nodes 📦 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-my-cluster-v1"
You can now use your cluster with:

kubectl cluster-info --context kind-my-cluster-v1

Have a question, bug, or feature request? Let us know! https://kind.sigs.k8s.io/#community 🙂
⏳ Waiting for nodes to become ready (timeout: 90s)...
node/my-cluster-v1-control-plane condition met
node/my-cluster-v1-worker condition met
node/my-cluster-v1-worker2 condition met
node/my-cluster-v1-worker3 condition met
🏷️ Applying Prometheus monitoring labels to worker nodes...
node/my-cluster-v1-worker labeled
node/my-cluster-v1-worker2 labeled
node/my-cluster-v1-worker3 labeled

✨ SUCCESS: Cluster 'my-cluster-v1' is ready! ✨
```

Verify cluster:

**./launch/verify-cluster.sh**

Output:

```
==================================================
🔍 Verifying KIND Cluster: 'my-cluster-v1'
==================================================
✓ Kind cluster status: Running

--- Kubernetes Nodes & Status ---
NAME                          STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION                              CONTAINER-RUNTIME    LABELS
my-cluster-v1-control-plane   Ready    control-plane   32s   v1.37.0   172.19.0.2    <none>        Debian GNU/Linux 13 (trixie)   6.18.54.1-microsoft-standard-WSL2 (amd64)   containerd://2.3.4   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=my-cluster-v1-control-plane,kubernetes.io/os=linux,node-role.kubernetes.io/control-plane=,node.kubernetes.io/exclude-from-external-load-balancers=
my-cluster-v1-worker          Ready    <none>          21s   v1.37.0   172.19.0.4    <none>        Debian GNU/Linux 13 (trixie)   6.18.54.1-microsoft-standard-WSL2 (amd64)   containerd://2.3.4   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=my-cluster-v1-worker,kubernetes.io/os=linux,node-group=workers
my-cluster-v1-worker2         Ready    <none>          21s   v1.37.0   172.19.0.5    <none>        Debian GNU/Linux 13 (trixie)   6.18.54.1-microsoft-standard-WSL2 (amd64)   containerd://2.3.4   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=my-cluster-v1-worker2,kubernetes.io/os=linux,node-group=workers
my-cluster-v1-worker3         Ready    <none>          21s   v1.37.0   172.19.0.3    <none>        Debian GNU/Linux 13 (trixie)   6.18.54.1-microsoft-standard-WSL2 (amd64)   containerd://2.3.4   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=my-cluster-v1-worker3,kubernetes.io/os=linux,node-group=workers

--- Docker Container & Port Mapping Check ---
NAMES                         STATUS          PORTS
my-cluster-v1-worker2         Up 37 seconds
my-cluster-v1-control-plane   Up 37 seconds   0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:9090->9090/tcp, 0.0.0.0:30000->30000/tcp, 127.0.0.1:46649->6443/tcp
my-cluster-v1-worker3         Up 37 seconds
my-cluster-v1-worker          Up 37 seconds

✨ Verification Complete: Cluster is healthy and accessible! ✨
```

Namespaces and service accounts descibed in
*launch/manifests/namespaces-accounts.yaml*

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mentor-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mentor
  namespace: mentor-system
---
apiVersion: v1
kind: Namespace
metadata:
  name: student01
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: student01
  namespace: student01
---
apiVersion: v1
kind: Namespace
metadata:
  name: student02
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: student02
  namespace: student02
---
apiVersion: v1
kind: Namespace
metadata:
  name: student03
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: student03
  namespace: student03
```

RBAC policies

*launch/manifests/rbac-policies.yaml*

```yaml
# --- MENTOR: RW Access to Student Namespaces ---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: student01
  name: mentor-rw
rules:
- apiGroups: ["", "apps", "batch", "networking.k8s.io"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: student01
  name: mentor-rw-student01
subjects:
- kind: ServiceAccount
  name: mentor
  namespace: mentor-system
roleRef:
  kind: Role
  name: mentor-rw
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: student02
  name: mentor-rw
rules:
- apiGroups: ["", "apps", "batch", "networking.k8s.io"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: student02
  name: mentor-rw-student02
subjects:
- kind: ServiceAccount
  name: mentor
  namespace: mentor-system
roleRef:
  kind: Role
  name: mentor-rw
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: student03
  name: mentor-rw
rules:
- apiGroups: ["", "apps", "batch", "networking.k8s.io"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: student03
  name: mentor-rw-student03
subjects:
- kind: ServiceAccount
  name: mentor
  namespace: mentor-system
roleRef:
  kind: Role
  name: mentor-rw
  apiGroup: rbac.authorization.k8s.io

# --- STUDENT 01: RW Access only to own namespace ---
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: student01
  name: student01-rw
rules:
- apiGroups: ["", "apps", "batch", "networking.k8s.io"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: student01
  name: student01-rw-binding
subjects:
- kind: ServiceAccount
  name: student01
  namespace: student01
roleRef:
  kind: Role
  name: student01-rw
  apiGroup: rbac.authorization.k8s.io

# --- STUDENT 02: RW to own namespace + RO to student01 and default ---
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: student02
  name: student02-rw
rules:
- apiGroups: ["", "apps", "batch", "networking.k8s.io"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: student02
  name: student02-rw-binding
subjects:
- kind: ServiceAccount
  name: student02
  namespace: student02
roleRef:
  kind: Role
  name: student02-rw
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: student02-readonly-clusterrole
rules:
- apiGroups: ["", "apps", "batch"]
  resources: ["pods", "services", "deployments", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: student01
  name: student02-ro-student01-binding
subjects:
- kind: ServiceAccount
  name: student02
  namespace: student02
roleRef:
  kind: ClusterRole
  name: student02-readonly-clusterrole
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: default
  name: student02-ro-default-binding
subjects:
- kind: ServiceAccount
  name: student02
  namespace: student02
roleRef:
  kind: ClusterRole
  name: student02-readonly-clusterrole
  apiGroup: rbac.authorization.k8s.io

# --- STUDENT 03: RW Access only to own namespace ---
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: student03
  name: student03-rw
rules:
- apiGroups: ["", "apps", "batch", "networking.k8s.io"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: student03
  name: student03-rw-binding
subjects:
- kind: ServiceAccount
  name: student03
  namespace: student03
roleRef:
  kind: Role
  name: student03-rw
  apiGroup: rbac.authorization.k8s.io
```

Generate kubeconfigs adn aplly RBAC with script

*launch/apply-rbac.sh*
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$SCRIPT_DIR/cluster-settings.yaml"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"
OUTPUT_DIR="$SCRIPT_DIR/../kubeconfigs"
mkdir -p "$OUTPUT_DIR"

if ! command -v yq &> /dev/null; then
    echo "❌ Error: 'yq' is required but not installed."
    exit 1
fi

CLUSTER_NAME=$(yq eval '.clusterName' "$SETTINGS_FILE")

echo "=================================================="
echo "🛡️ Applying Static RBAC Manifests & Generating Kubeconfigs"
echo "=================================================="

# Apply static YAML manifests
kubectl apply -f "$MANIFESTS_DIR/namespaces-accounts.yaml"
kubectl apply -f "$MANIFESTS_DIR/rbac-policies.yaml"

# Helper to generate isolated kubeconfig files for each user
generate_kubeconfig() {
    local user_name=$1
    local user_ns=$2
    local config_out="$OUTPUT_DIR/${user_name}-kubeconfig.yaml"

    echo "🔑 Generating kubeconfig for $user_name..."

    # Create static long-lived token secret for ServiceAccount
    kubectl apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: ${user_name}-token
  namespace: ${user_ns}
  annotations:
    kubernetes.io/service-account.name: "${user_name}"
type: kubernetes.io/service-account-token
EOF

    local server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    local ca_data=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

    local token=""
    for i in {1..5}; do
        token=$(kubectl get secret "${user_name}-token" -n "${user_ns}" -o jsonpath='{.data.token}' 2>/dev/null | base64 --decode || true)
        if [ -n "$token" ]; then break; fi
        sleep 1
    done

    cat <<EOF > "$config_out"
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${ca_data}
    server: ${server}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    namespace: ${user_ns}
    user: ${user_name}
  name: ${user_name}-context
current-context: ${user_name}-context
users:
- name: ${user_name}
  user:
    token: ${token}
EOF
}

# Generate kubeconfigs for mentor and all 3 students
generate_kubeconfig "mentor" "mentor-system"
generate_kubeconfig "student01" "student01"
generate_kubeconfig "student02" "student02"
generate_kubeconfig "student03" "student03"

echo "✨ RBAC applied and kubeconfigs saved to 'kubeconfigs/'! ✨"
```

**./launch.aplly-rbac.sh**

output

```
==================================================
🛡️ Applying Static RBAC Manifests & Generating Kubeconfigs
==================================================
namespace/mentor-system created
serviceaccount/mentor created
namespace/student01 created
serviceaccount/student01 created
namespace/student02 created
serviceaccount/student02 created
namespace/student03 created
serviceaccount/student03 created
role.rbac.authorization.k8s.io/mentor-rw created
rolebinding.rbac.authorization.k8s.io/mentor-rw-student01 created
role.rbac.authorization.k8s.io/mentor-rw created
rolebinding.rbac.authorization.k8s.io/mentor-rw-student02 created
role.rbac.authorization.k8s.io/mentor-rw created
rolebinding.rbac.authorization.k8s.io/mentor-rw-student03 created
role.rbac.authorization.k8s.io/student01-rw created
rolebinding.rbac.authorization.k8s.io/student01-rw-binding created
role.rbac.authorization.k8s.io/student02-rw created
rolebinding.rbac.authorization.k8s.io/student02-rw-binding created
clusterrole.rbac.authorization.k8s.io/student02-readonly-clusterrole created
rolebinding.rbac.authorization.k8s.io/student02-ro-student01-binding created
rolebinding.rbac.authorization.k8s.io/student02-ro-default-binding created
role.rbac.authorization.k8s.io/student03-rw created
rolebinding.rbac.authorization.k8s.io/student03-rw-binding created
🔑 Generating kubeconfig for mentor...
🔑 Generating kubeconfig for student01...
🔑 Generating kubeconfig for student02...
🔑 Generating kubeconfig for student03...
✨ RBAC applied and kubeconfigs saved to 'kubeconfigs/'! ✨
```

Verify RBAC

*launch/verify-rbac.sh*

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$SCRIPT_DIR/cluster-settings.yaml"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"
OUTPUT_DIR="$SCRIPT_DIR/../kubeconfigs"
mkdir -p "$OUTPUT_DIR"

if ! command -v yq &> /dev/null; then
    echo "❌ Error: 'yq' is required but not installed."
    exit 1
fi

CLUSTER_NAME=$(yq eval '.clusterName' "$SETTINGS_FILE")

echo "=================================================="
echo "🛡️ Applying Static RBAC Manifests & Generating Kubeconfigs"
echo "=================================================="

# Apply static YAML manifests
kubectl apply -f "$MANIFESTS_DIR/namespaces-accounts.yaml"
kubectl apply -f "$MANIFESTS_DIR/rbac-policies.yaml"

# Helper to generate isolated kubeconfig files for each user
generate_kubeconfig() {
    local user_name=$1
    local user_ns=$2
    local config_out="$OUTPUT_DIR/${user_name}-kubeconfig.yaml"

    echo "🔑 Generating kubeconfig for $user_name..."

    # Create static long-lived token secret for ServiceAccount
    kubectl apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: ${user_name}-token
  namespace: ${user_ns}
  annotations:
    kubernetes.io/service-account.name: "${user_name}"
type: kubernetes.io/service-account-token
EOF

    local server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    local ca_data=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

    local token=""
    for i in {1..5}; do
        token=$(kubectl get secret "${user_name}-token" -n "${user_ns}" -o jsonpath='{.data.token}' 2>/dev/null | base64 --decode || true)
        if [ -n "$token" ]; then break; fi
        sleep 1
    done

    cat <<EOF > "$config_out"
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${ca_data}
    server: ${server}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    namespace: ${user_ns}
    user: ${user_name}
  name: ${user_name}-context
current-context: ${user_name}-context
users:
- name: ${user_name}
  user:
    token: ${token}
EOF
}

# Generate kubeconfigs for mentor and all 3 students
generate_kubeconfig "mentor" "mentor-system"
generate_kubeconfig "student01" "student01"
generate_kubeconfig "student02" "student02"
generate_kubeconfig "student03" "student03"

echo "✨ RBAC applied and kubeconfigs saved to 'kubeconfigs/'! ✨"hawk@LAPTOP-M41QRI3E:/mnt/d/study/k8s/kube-in-prod-v2/launch$ cat verify-rbac.sh
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
```

**./launch/verify-rbac.sh**

Output

```
==================================================
🔍 Verifying RBAC Permissions & Security Isolation
==================================================
1️⃣ Testing Mentor RW access in student01...
   ✓ Mentor can read student01
2️⃣ Testing Student01 isolation...
   ✓ Student01 can access own namespace
   ✓ Student01 correctly blocked from student02
3️⃣ Testing Student02 Read-Only access on student01...
   ✓ Student02 can read student01 (RO working)
   ✓ Student02 correctly blocked from writing to student01

✨ All RBAC verification tests passed successfully! ✨
```

Verify that no cluster admin prviledges in mentor and student0*

*launch/verify-no-cluster-admin.sh*

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Automatically search for cluster-settings.yaml in common repo locations
SETTINGS_FILE=""
POSSIBLE_PATHS=(
    "$SCRIPT_DIR/cluster-settings.yaml"
    "$SCRIPT_DIR/../launch/cluster-settings.yaml"
    "$SCRIPT_DIR/../cluster-settings.yaml"
    "./cluster-settings.yaml"
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
```

Run
**./launch/verify-no-cluster-admin.sh**

Output

```
📁 Using settings file: /mnt/d/study/k8s/kube-in-prod-v2/launch/cluster-settings.yaml
==================================================
🛡️ Security Check: Verifying NO Cluster Admin Privileges
==================================================
--------------------------------------------------
🔍 Checking user: 'mentor'
   ✓ Passed: 'mentor' does NOT have wildcard root privileges.
   ✓ Passed: 'mentor' cannot access cluster-scoped nodes.
   ✓ Passed: 'mentor' cannot view cluster-scoped roles.
--------------------------------------------------
🔍 Checking user: 'student01'
   ✓ Passed: 'student01' does NOT have wildcard root privileges.
   ✓ Passed: 'student01' cannot access cluster-scoped nodes.
   ✓ Passed: 'student01' cannot view cluster-scoped roles.
--------------------------------------------------
🔍 Checking user: 'student02'
   ✓ Passed: 'student02' does NOT have wildcard root privileges.
   ✓ Passed: 'student02' cannot access cluster-scoped nodes.
   ✓ Passed: 'student02' cannot view cluster-scoped roles.
--------------------------------------------------
🔍 Checking user: 'student03'
   ✓ Passed: 'student03' does NOT have wildcard root privileges.
   ✓ Passed: 'student03' cannot access cluster-scoped nodes.
   ✓ Passed: 'student03' cannot view cluster-scoped roles.

==================================================
✨ SUCCESS: Neither mentor nor any student has Cluster Admin privileges! ✨
==================================================
```


## 2. Kyverno policy creation for validating the read-only root filesystem in audit mode

**./launch/verify-kyverno-audit.sh**

Install Kyverno into cluster with --force-conflicts

```bash
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
```

Kyverno policy manifest in Audit mode

*./launch/manifests/validate-readonly-rootfs.yaml*

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-readonly-root-filesystem
  annotations:
    policies.kyverno.io/title: Validate Read-Only Root Filesystem
    policies.kyverno.io/severity: medium
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Root filesystems should be set to read-only (readOnlyRootFilesystem: true)
      to prevent malicious modifications to container images. This policy operates
      in Audit mode.
spec:
  validationFailureAction: Audit
  background: true
  rules:
    - name: check-readonly-root-filesystem
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Container root filesystem must be read-only (securityContext.readOnlyRootFilesystem: true)."
        pattern:
          spec:
            =(initContainers):
              - securityContext:
                  readOnlyRootFilesystem: true
            =(ephemeralContainers):
              - securityContext:
                  readOnlyRootFilesystem: true
            containers:
              - securityContext:
                  readOnlyRootFilesystem: true
```

This script automates the validation process:

1. Applies the kyverno audit policy.

2. Deploys a non-compliant test pod (missing readOnlyRootFilesystem).

3. Confirms that the pod successfully starts (since the policy is in Audit mode, it doesn't block creation).

4. Inspects Kyverno's PolicyReport to verify that the audit violation has been successfully detected and logged.

5. Cleans up the test resources.

*launch/verify-kyverno-audit.sh*

```bash
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
```

run

**./launch/verify-kyverno-policy.sh**


Output

```
==================================================
🛡️ Kyverno Audit Mode Verification: Read-Only Root FS
==================================================
📂 Applying Kyverno ClusterPolicy...
clusterpolicy.kyverno.io/validate-readonly-root-filesystem created
🚀 Deploying non-compliant test pod ('audit-test-nginx')...
pod/audit-test-nginx created
⏳ Waiting for test pod to start...
pod/audit-test-nginx condition met
   ✓ Pod successfully created (Audit mode permitted non-compliant pod).
🔍 Checking Kyverno PolicyReports for audit violation...
   ✓ Success: Kyverno successfully audited and flagged the violation!
🧹 Cleaning up test pod...

==================================================
✨ Kyverno audit policy verification completed successfully! ✨
==================================================
```

## 3. Kyverno policy creation 

1. Kyverno Mutating Policy Manifest

This policy uses two rules:

Student Namespaces (student*): Automatically adds person: student.

Mentor Namespace (mentor-system): Automatically adds person: mentor.

Other Namespaces: Because they do not match either rule, Kyverno leaves them alone, ensuring no person label is added elsewhere.

*/launch/manifests/mutate-person-label.yaml*

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: mutate-person-label
  annotations:
    policies.kyverno.io/title: Mutate Person Label by Namespace
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Adds the 'person' label to pods depending on their namespace ('student' for 
      student namespaces, 'mentor' for mentor namespaces). Other namespaces are ignored.
spec:
  rules:
    - name: add-student-person-label
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - "student*"
      mutate:
        patchStrategicMerge:
          metadata:
            labels:
              person: student

    - name: add-mentor-person-label
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - "mentor-system"
      mutate:
        patchStrategicMerge:
          metadata:
            labels:
              person: mentor
```

Verification script testing across all three scenarios:

Deploys a test pod in student01 and confirms it gets person=student.

Deploys a test pod in mentor-system and confirms it gets person=mentor.

Deploys a test pod in default and confirms it does not get the person label.

Cleans up all test resources afterward

*/launch/verify-kyverno-mutation.sh*

```bash
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
```

Output

```
==================================================
🛡️ Kyverno Mutation Verification: 'person' Label
==================================================
📂 Applying Kyverno Mutating ClusterPolicy...
clusterpolicy.kyverno.io/mutate-person-label created
--------------------------------------------------
1️⃣ Testing Pod creation in student namespace ('student01')...
pod/test-pod-student created
   Observed label 'person' in student01: 'student'
   ✓ Success: Student pod correctly labeled with 'person=student'.
--------------------------------------------------
2️⃣ Testing Pod creation in mentor namespace ('mentor-system')...
pod/test-pod-mentor created
   Observed label 'person' in mentor-system: 'mentor'
   ✓ Success: Mentor pod correctly labeled with 'person=mentor'.
--------------------------------------------------
3️⃣ Testing Pod creation in other namespace ('default')...
pod/test-pod-default created
   Observed label 'person' in default: '<none>'
   ✓ Success: Default namespace pod correctly left unlabeled.

==================================================
✨ SUCCESS: All Kyverno mutation tests passed perfectly! ✨
==================================================
```