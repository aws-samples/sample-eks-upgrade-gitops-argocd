#!/usr/bin/env bash
# Post-upgrade validation script for EKS cluster version upgrades.
# Run this after terraform apply and ArgoCD sync complete to verify
# the cluster is healthy at the new Kubernetes version.
#
# Required environment variables:
#   CLUSTER_NAME       - EKS cluster name
#   EXPECTED_VERSION   - Expected Kubernetes version after upgrade (e.g., "1.31")
#   AWS_REGION         - AWS region (e.g., "us-east-1")

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME must be set}"
EXPECTED_VERSION="${EXPECTED_VERSION:?EXPECTED_VERSION must be set}"
AWS_REGION="${AWS_REGION:-us-east-1}"
TEST_POD_NAME="eks-upgrade-dns-test-$(date +%s)"

PASS=0
FAIL=0

log_pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
log_fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
log_warn() { echo "  [WARN] $1"; }
log_step() { echo ""; echo "==> $1"; }

cleanup() {
  kubectl delete pod "$TEST_POD_NAME" -n default --ignore-not-found --grace-period=0 &>/dev/null || true
}
trap cleanup EXIT

echo "=========================================="
echo "EKS Post-Upgrade Validation"
echo "Cluster:          $CLUSTER_NAME"
echo "Expected version: $EXPECTED_VERSION"
echo "Region:           $AWS_REGION"
echo "=========================================="

# --------------------------------------------------------------------------
log_step "1. Asserting cluster version"
ACTUAL_VERSION=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.version' \
  --output text)

if [ "$ACTUAL_VERSION" = "$EXPECTED_VERSION" ]; then
  log_pass "Cluster version is $ACTUAL_VERSION (expected $EXPECTED_VERSION)"
else
  log_fail "Cluster version is $ACTUAL_VERSION (expected $EXPECTED_VERSION)"
fi

# --------------------------------------------------------------------------
log_step "2. Asserting all nodes are Ready at the new version"
TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
NOT_READY=0
OLD_VERSION_NODES=0

while IFS= read -r line; do
  NODE_NAME=$(echo "$line" | awk '{print $1}')
  NODE_STATUS=$(echo "$line" | awk '{print $2}')
  KUBELET_VERSION=$(echo "$line" | awk '{print $5}' | sed 's/v//')

  if [ "$NODE_STATUS" != "Ready" ]; then
    log_fail "Node $NODE_NAME is not Ready (status: $NODE_STATUS)"
    NOT_READY=$((NOT_READY + 1))
  fi

  # Kubelet minor version must match the cluster version.
  KUBELET_MINOR=$(echo "$KUBELET_VERSION" | cut -d'.' -f2)
  EXPECTED_MINOR=$(echo "$EXPECTED_VERSION" | cut -d'.' -f2)
  if [ "$KUBELET_MINOR" != "$EXPECTED_MINOR" ]; then
    log_warn "Node $NODE_NAME kubelet version $KUBELET_VERSION does not match expected 1.${EXPECTED_MINOR}.x"
    OLD_VERSION_NODES=$((OLD_VERSION_NODES + 1))
  fi
done < <(kubectl get nodes --no-headers \
  -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,A:.status.conditions[-1].status,B:.metadata.labels.eks.amazonaws.com/nodegroup,KUBELET:.status.nodeInfo.kubeletVersion \
  2>/dev/null)

if [ "$NOT_READY" -eq 0 ]; then
  log_pass "All $TOTAL_NODES nodes are Ready"
fi
if [ "$OLD_VERSION_NODES" -gt 0 ]; then
  log_warn "$OLD_VERSION_NODES node(s) still running old kubelet version — node group rolling update may still be in progress"
else
  log_pass "All nodes are running kubelet version 1.${EXPECTED_MINOR}.x"
fi

# --------------------------------------------------------------------------
log_step "3. Checking kube-system pods"
NOT_RUNNING=$(kubectl get pods -n kube-system \
  --field-selector='status.phase!=Running,status.phase!=Succeeded' \
  --no-headers 2>/dev/null || true)

if [ -z "$NOT_RUNNING" ]; then
  TOTAL=$(kubectl get pods -n kube-system --no-headers | wc -l | tr -d ' ')
  log_pass "All $TOTAL kube-system pods are Running or Succeeded"
else
  log_fail "Pods in kube-system not Running:\n$NOT_RUNNING"
fi

# --------------------------------------------------------------------------
log_step "4. Checking EKS add-on versions"
for ADDON in coredns kube-proxy vpc-cni aws-ebs-csi-driver; do
  ADDON_STATUS=$(aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$ADDON" \
    --region "$AWS_REGION" \
    --query 'addon.status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

  ADDON_VERSION=$(aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$ADDON" \
    --region "$AWS_REGION" \
    --query 'addon.addonVersion' \
    --output text 2>/dev/null || echo "N/A")

  if [ "$ADDON_STATUS" = "ACTIVE" ]; then
    log_pass "Add-on $ADDON: ACTIVE (version: $ADDON_VERSION)"
  elif [ "$ADDON_STATUS" = "NOT_FOUND" ]; then
    log_warn "Add-on $ADDON: not found in cluster"
  else
    log_fail "Add-on $ADDON: status is $ADDON_STATUS (version: $ADDON_VERSION)"
  fi
done

# --------------------------------------------------------------------------
log_step "5. Checking ArgoCD application health"
if kubectl get namespace argocd &>/dev/null; then
  ARGOCD_PODS_FAILING=$(kubectl get pods -n argocd \
    --field-selector='status.phase!=Running' \
    --no-headers 2>/dev/null | grep -v "Completed" || true)

  if [ -z "$ARGOCD_PODS_FAILING" ]; then
    log_pass "All ArgoCD pods are healthy"
  else
    log_fail "ArgoCD pods not healthy:\n$ARGOCD_PODS_FAILING"
  fi

  # Check upgrade-monitor ConfigMap reflects the expected version.
  CM_NAME="eks-upgrade-state-${CLUSTER_NAME}"
  TRACKED_VERSION=$(kubectl get configmap "$CM_NAME" \
    -n kube-system \
    -o jsonpath='{.data.desiredVersion}' 2>/dev/null || echo "NOT_FOUND")

  if [ "$TRACKED_VERSION" = "$EXPECTED_VERSION" ]; then
    log_pass "ArgoCD upgrade-monitor ConfigMap reflects version $EXPECTED_VERSION"
  else
    log_fail "ArgoCD upgrade-monitor ConfigMap shows version '$TRACKED_VERSION' (expected '$EXPECTED_VERSION')"
  fi
else
  log_warn "ArgoCD namespace not found. Skipping ArgoCD health check."
fi

# --------------------------------------------------------------------------
log_step "6. Running DNS connectivity test"
cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $TEST_POD_NAME
  namespace: default
  labels:
    app: eks-upgrade-dns-test
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 5
  containers:
    - name: dns-test
      image: busybox:1.28
      command: ["sh", "-c", "nslookup kubernetes.default.svc.cluster.local && echo DNS_OK"]
EOF

echo "  Waiting for DNS test pod to complete (up to 60s)..."
for i in $(seq 1 12); do
  POD_PHASE=$(kubectl get pod "$TEST_POD_NAME" -n default \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
  if [ "$POD_PHASE" = "Succeeded" ]; then
    break
  fi
  if [ "$POD_PHASE" = "Failed" ]; then
    break
  fi
  sleep 5
done

POD_LOGS=$(kubectl logs "$TEST_POD_NAME" -n default 2>/dev/null || echo "")
if echo "$POD_LOGS" | grep -q "DNS_OK"; then
  log_pass "DNS resolution test passed (resolved kubernetes.default.svc.cluster.local)"
else
  log_fail "DNS resolution test failed. Logs:\n$POD_LOGS"
fi

# --------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "Post-Upgrade Validation Summary"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL — $FAIL check(s) failed. Review the cluster state before proceeding with further upgrades."
  exit 1
else
  echo "RESULT: PASS — All post-upgrade validation checks passed."
  exit 0
fi
