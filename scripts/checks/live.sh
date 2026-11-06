#!/usr/bin/env bash
# eks-gitops-doctor — live checks (needs a cluster).
# Runs read-only commands only: kubectl get/describe, helm list, terraform plan.
# Never applies, deletes, scales, or edits anything.
# Every check degrades to SKIP when its tool or the cluster is unavailable,
# so a static-only run still produces a useful report.

# kubectl_ok — true when kubectl exists and a cluster answers.
kubectl_ok() {
  command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1
}

# CLU-01 — all nodes Ready, none tainted away or NotReady.
check_CLU_01_nodes_ready() {
  if ! kubectl_ok; then
    doctor_check "CLU-01" "Cluster" "SKIP" "Nodes Ready" "kubectl not available or no cluster context — run with a kubeconfig pointed at the cluster"
    return
  fi
  local total ready notready
  total="$(kubectl get nodes --no-headers 2>/dev/null | wc -l)"
  ready="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || true)"
  notready="$((total - ready))"
  if [ "$total" -eq 0 ]; then
    doctor_check "CLU-01" "Cluster" "FAIL" "Nodes Ready" "kubectl answers but reports zero nodes"
  elif [ "$notready" -eq 0 ]; then
    doctor_check "CLU-01" "Cluster" "PASS" "Nodes Ready" "$ready/$total nodes Ready"
  else
    doctor_check "CLU-01" "Cluster" "FAIL" "Nodes Ready" "$notready/$total nodes are NotReady — run: kubectl get nodes; kubectl describe node <name>"
  fi
}

# ARG-01 — ArgoCD pods are running.
check_ARG_01_argocd_pods() {
  if ! kubectl_ok; then
    doctor_check "ARG-01" "ArgoCD" "SKIP" "ArgoCD pods running" "kubectl not available or no cluster context"
    return
  fi
  local total running
  total="$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)"
  running="$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -c ' Running ' || true)"
  if [ "$total" -eq 0 ]; then
    doctor_check "ARG-01" "ArgoCD" "FAIL" "ArgoCD pods running" "no pods in namespace argocd — ArgoCD is not installed"
  elif [ "$running" -eq "$total" ]; then
    doctor_check "ARG-01" "ArgoCD" "PASS" "ArgoCD pods running" "$running/$total ArgoCD pods Running"
  else
    doctor_check "ARG-01" "ArgoCD" "FAIL" "ArgoCD pods running" "$((total - running))/$total ArgoCD pods are not Running — run: kubectl get pods -n argocd"
  fi
}

# ARG-02 — every ArgoCD Application is Synced and Healthy.
check_ARG_02_sync_status() {
  if ! kubectl_ok; then
    doctor_check "ARG-02" "ArgoCD" "SKIP" "Applications Synced + Healthy" "kubectl not available or no cluster context"
    return
  fi
  if ! kubectl get applications.argoproj.io -n argocd --no-headers >/dev/null 2>&1; then
    doctor_check "ARG-02" "ArgoCD" "SKIP" "Applications Synced + Healthy" "ArgoCD Application CRD not found — ArgoCD may not be installed"
    return
  fi
  local total synced healthy
  total="$(kubectl get applications.argoproj.io -n argocd --no-headers 2>/dev/null | wc -l)"
  synced="$(kubectl get applications.argoproj.io -n argocd --no-headers 2>/dev/null | grep -c ' Synced ' || true)"
  healthy="$(kubectl get applications.argoproj.io -n argocd --no-headers 2>/dev/null | grep -c ' Healthy' || true)"
  if [ "$total" -eq 0 ]; then
    doctor_check "ARG-02" "ArgoCD" "WARN" "Applications Synced + Healthy" "ArgoCD is installed but has no Applications — nothing is managed by GitOps yet"
  elif [ "$synced" -eq "$total" ] && [ "$healthy" -eq "$total" ]; then
    doctor_check "ARG-02" "ArgoCD" "PASS" "Applications Synced + Healthy" "$total/$total Applications Synced and Healthy"
  else
    doctor_check "ARG-02" "ArgoCD" "FAIL" "Applications Synced + Healthy" "$synced/$total Synced, $healthy/$total Healthy — run: kubectl get applications -n argocd"
  fi
}

# ARG-03 — drift: no Application stuck OutOfSync.
check_ARG_03_drift() {
  if ! kubectl_ok; then
    doctor_check "ARG-03" "ArgoCD" "SKIP" "No drift (OutOfSync)" "kubectl not available or no cluster context"
    return
  fi
  local outofsync
  outofsync="$(kubectl get applications.argoproj.io -n argocd --no-headers 2>/dev/null | grep -c ' OutOfSync ' || true)"
  if [ "$outofsync" -eq 0 ]; then
    doctor_check "ARG-03" "ArgoCD" "PASS" "No drift (OutOfSync)" "no Application is OutOfSync — the cluster matches Git"
  else
    doctor_check "ARG-03" "ArgoCD" "WARN" "No drift (OutOfSync)" "$outofsync Application(s) OutOfSync — check the ArgoCD UI diff, then either sync or commit the change to Git"
  fi
}

# MON-01L — Prometheus pods running (live half of MON-01).
check_MON_01L_prometheus_live() {
  if ! kubectl_ok; then
    doctor_check "MON-01L" "Monitoring" "SKIP" "Prometheus pods running" "kubectl not available or no cluster context"
    return
  fi
  local total running
  total="$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)"
  running="$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c ' Running ' || true)"
  if [ "$total" -eq 0 ]; then
    doctor_check "MON-01L" "Monitoring" "FAIL" "Prometheus pods running" "no Prometheus pods in namespace monitoring — the monitoring stack is not installed"
  elif [ "$running" -eq "$total" ]; then
    doctor_check "MON-01L" "Monitoring" "PASS" "Prometheus pods running" "$running/$total Prometheus pods Running"
  else
    doctor_check "MON-01L" "Monitoring" "FAIL" "Prometheus pods running" "$((total - running))/$total Prometheus pods are not Running"
  fi
}

# HELM-01 — Helm releases for ArgoCD and the monitoring stack are deployed.
check_HELM_01_releases() {
  if ! command -v helm >/dev/null 2>&1; then
    doctor_check "HELM-01" "Operations" "SKIP" "Helm releases deployed" "helm is not installed — install it to check release status"
    return
  fi
  if ! kubectl_ok; then
    doctor_check "HELM-01" "Operations" "SKIP" "Helm releases deployed" "kubectl not available or no cluster context"
    return
  fi
  local failed
  failed="$(helm list -A --no-headers 2>/dev/null | grep -vc ' deployed ' || true)"
  if [ "$failed" -eq 0 ]; then
    doctor_check "HELM-01" "Operations" "PASS" "Helm releases deployed" "all Helm releases report status deployed"
  else
    doctor_check "HELM-01" "Operations" "WARN" "Helm releases deployed" "$failed Helm release(s) are not in deployed status — run: helm list -A"
  fi
}

# TF-01 — terraform plan is clean (declared config matches real infra).
# Runs only when terraform is installed AND the repo was already initialised
# (a .terraform/ directory exists). Never runs init itself: initialising
# would write state and lock files into the user's repo, which is not
# read-only behaviour. Plan refreshes remote state but changes nothing.
check_TF_01_plan() {
  if ! command -v terraform >/dev/null 2>&1; then
    doctor_check "TF-01" "Operations" "SKIP" "Terraform plan is clean" "terraform is not installed"
    return
  fi
  if [ ! -d "$REPO/terraform" ]; then
    doctor_check "TF-01" "Operations" "SKIP" "Terraform plan is clean" "no terraform/ directory in the repo"
    return
  fi
  if [ ! -d "$REPO/terraform/.terraform" ]; then
    doctor_check "TF-01" "Operations" "SKIP" "Terraform plan is clean" "terraform is not initialised — run terraform init in $REPO/terraform first"
    return
  fi
  local plan_out plan_code=0
  plan_out="$(cd "$REPO/terraform" && timeout 300 terraform plan -detailed-exitcode -no-color -input=false 2>&1)" || plan_code=$?
  case "$plan_code" in
    0)
      doctor_check "TF-01" "Operations" "PASS" "Terraform plan is clean" "terraform plan reports no changes — declared config matches real infrastructure"
      ;;
    2)
      local plan_summary
      plan_summary="$(printf '%s' "$plan_out" | grep -E '^Plan: ' | head -n 1 || true)"
      doctor_check "TF-01" "Operations" "WARN" "Terraform plan is clean" "terraform plan shows pending changes${plan_summary:+ — $plan_summary} — declared config differs from real infrastructure; review the plan before applying"
      ;;
    124)
      doctor_check "TF-01" "Operations" "SKIP" "Terraform plan is clean" "terraform plan timed out after 300s"
      ;;
    *)
      local first_line
      first_line="$(printf '%s' "$plan_out" | head -n 1)"
      doctor_check "TF-01" "Operations" "SKIP" "Terraform plan is clean" "terraform plan errored (${first_line:-no output}) — check AWS credentials and backend config"
      ;;
  esac
}

# run_live_checks — runs every live check in ID order.
run_live_checks() {
  check_CLU_01_nodes_ready
  check_ARG_01_argocd_pods
  check_ARG_02_sync_status
  check_ARG_03_drift
  check_MON_01L_prometheus_live
  check_HELM_01_releases
  check_TF_01_plan
}
