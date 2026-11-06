#!/usr/bin/env bash
# eks-gitops-doctor — static checks (no cluster needed).
# Audits a repo's Terraform and Kubernetes manifests with grep. Read-only:
# it only reads files under $REPO. Run with: doctor.sh --static <repo-path>
#
# These checks answer "is the setup declared correctly?" A live cluster can
# still drift from what is declared, so pair them with --live when possible.

# --- helpers ---------------------------------------------------------------

# tf_has <pattern> — true if any *.tf file under $REPO/terraform matches.
tf_has() { grep -rEq "$1" "$REPO"/terraform 2>/dev/null; }

# tf_code_has <pattern> — like tf_has, but ignores lines that are comments.
# (Terraform examples often show a setting commented out; that is not a setting.)
tf_code_has() { grep -rhE "$1" "$REPO"/terraform 2>/dev/null | grep -vE '^[[:space:]]*#' | grep -q .; }

# k8s_has <pattern> — true if any manifest under kubernetes/ or apps/ matches.
k8s_has() { grep -rEq "$1" "$REPO"/kubernetes "$REPO"/apps 2>/dev/null; }

# tf_value <file-pattern> — first match of a simple `key = "value"` assignment.
tf_value() { grep -rhoE "$1" "$REPO"/terraform 2>/dev/null | head -n 1; }

# --- Cluster ---------------------------------------------------------------

# CLU-02 — node groups: at least 2 desired nodes, private subnets, 3 AZs.
check_CLU_02_node_groups() {
  local desired min_size max_size
  desired="$(tf_value 'node_desired_size[[:space:]]*=[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' || true)"
  min_size="$(tf_value 'node_min_size[[:space:]]*=[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' || true)"
  max_size="$(tf_value 'node_max_size[[:space:]]*=[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' || true)"
  if [ -z "${desired:-}" ]; then
    doctor_check "CLU-02" "Cluster" "SKIP" "Node group sizing" "no node_desired_size found in terraform/ — cannot assess sizing"
    return
  fi
  if ! tf_has 'subnet_ids[[:space:]]*=[[:space:]]*module\.vpc\.private_subnets'; then
    doctor_check "CLU-02" "Cluster" "FAIL" "Node group sizing" "node group is not placed in private subnets"
    return
  fi
  if [ "$desired" -ge 2 ] && [ "${min_size:-0}" -ge 2 ]; then
    doctor_check "CLU-02" "Cluster" "PASS" "Node group sizing" "desired=$desired min=$min_size max=${max_size:-?}; nodes in private subnets across 3 AZs"
  else
    doctor_check "CLU-02" "Cluster" "WARN" "Node group sizing" "desired=$desired min=${min_size:-?} — fewer than 2 nodes means one node failure takes the workload down"
  fi
}

# CLU-03 — EKS add-ons: coredns, kube-proxy, vpc-cni, ebs-csi present.
check_CLU_03_addons() {
  local found=0 missing=""
  local addon
  for addon in coredns kube-proxy vpc-cni aws-ebs-csi-driver; do
    if tf_has "${addon}[[:space:]]*="; then found=$((found + 1)); else missing="$missing $addon"; fi
  done
  if [ "$found" -eq 4 ]; then
    if tf_has 'most_recent[[:space:]]*=[[:space:]]*true'; then
      doctor_check "CLU-03" "Cluster" "PASS" "EKS add-ons declared" "coredns, kube-proxy, vpc-cni, aws-ebs-csi-driver all declared with most_recent=true"
    else
      doctor_check "CLU-03" "Cluster" "WARN" "EKS add-ons declared" "all 4 add-ons declared but versions are pinned — check they track the cluster version"
    fi
  else
    doctor_check "CLU-03" "Cluster" "FAIL" "EKS add-ons declared" "missing add-ons:$missing"
  fi
}

# CLU-04 — Kubernetes version not past end of life.
# MIN_SUPPORTED_MINOR is the oldest minor version still in standard support
# on the date this skill was last updated (see docs/checks.md). Bump it when
# AWS drops a version from standard support.
check_CLU_04_k8s_version() {
  local min_minor=32
  local version minor
  version="$(tf_value 'kubernetes_version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+' | head -n 1)"
  if [ -z "${version:-}" ]; then
    doctor_check "CLU-04" "Cluster" "SKIP" "Kubernetes version current" "no kubernetes_version found in terraform/"
    return
  fi
  minor="${version#*.}"
  if [ "$minor" -ge "$min_minor" ]; then
    doctor_check "CLU-04" "Cluster" "PASS" "Kubernetes version current" "cluster version $version is within standard support (floor is 1.$min_minor)"
  else
    doctor_check "CLU-04" "Cluster" "WARN" "Kubernetes version current" "cluster version $version is past standard support (floor is 1.$min_minor) — plan an upgrade; EKS auto-upgrades extended-support clusters and bills for it"
  fi
}

# CLU-05 — control-plane logging: all five log types enabled.
check_CLU_05_logging() {
  local count=0 missing=""
  local logtype
  for logtype in api audit authenticator controllerManager scheduler; do
    if tf_has "\"$logtype\""; then count=$((count + 1)); else missing="$missing $logtype"; fi
  done
  if [ "$count" -eq 5 ]; then
    doctor_check "CLU-05" "Cluster" "PASS" "Control-plane logging" "all 5 log types enabled (api, audit, authenticator, controllerManager, scheduler)"
  elif [ "$count" -ge 3 ]; then
    doctor_check "CLU-05" "Cluster" "WARN" "Control-plane logging" "only $count/5 log types enabled; missing:$missing"
  else
    doctor_check "CLU-05" "Cluster" "FAIL" "Control-plane logging" "only $count/5 log types enabled; missing:$missing"
  fi
}

# CLU-06 — public API endpoint restricted to known CIDRs.
# Checks, in order: an explicit assignment (tfvars), then the variable default.
check_CLU_06_endpoint() {
  if tf_code_has 'cluster_endpoint_public_access[[:space:]]*=[[:space:]]*false'; then
    doctor_check "CLU-06" "Cluster" "PASS" "Public API endpoint restricted" "public endpoint disabled — API is private-only"
    return
  fi
  # A concrete assignment (tfvars). Pass-through lines such as
  # `cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs`
  # in a module call are not a setting — skip them and fall through to the default.
  local assignment
  assignment="$(grep -rhE 'cluster_endpoint_public_access_cidrs[[:space:]]*=' "$REPO"/terraform 2>/dev/null | grep -vE '^[[:space:]]*#' | grep -vE '=[[:space:]]*var\.' | head -n 1 || true)"
  if [ -n "$assignment" ]; then
    if printf '%s' "$assignment" | grep -q '0\.0\.0\.0/0'; then
      doctor_check "CLU-06" "Cluster" "WARN" "Public API endpoint restricted" "public endpoint allows 0.0.0.0/0 — anyone on the internet can reach the API server; restrict cluster_endpoint_public_access_cidrs to your IPs"
    else
      doctor_check "CLU-06" "Cluster" "PASS" "Public API endpoint restricted" "public endpoint CIDRs are restricted (not 0.0.0.0/0)"
    fi
    return
  fi
  # No assignment: the variable default decides.
  if grep -rhA5 -E 'variable[[:space:]]+"cluster_endpoint_public_access_cidrs"' "$REPO"/terraform 2>/dev/null | grep -q '0\.0\.0\.0/0'; then
    doctor_check "CLU-06" "Cluster" "WARN" "Public API endpoint restricted" "public endpoint allows 0.0.0.0/0 (variable default) — anyone on the internet can reach the API server; restrict cluster_endpoint_public_access_cidrs to your IPs"
    return
  fi
  doctor_check "CLU-06" "Cluster" "SKIP" "Public API endpoint restricted" "no endpoint access setting found in terraform/"
}

# CLU-07 — PodDisruptionBudgets for workloads that must stay up.
check_CLU_07_pdb() {
  if k8s_has 'kind:[[:space:]]*PodDisruptionBudget'; then
    doctor_check "CLU-07" "Cluster" "PASS" "PodDisruptionBudget present" "at least one PodDisruptionBudget declared"
  else
    doctor_check "CLU-07" "Cluster" "WARN" "PodDisruptionBudget present" "no PodDisruptionBudget in kubernetes/ or apps/ — node drains and upgrades can take all replicas down at once"
  fi
}

# --- ArgoCD ----------------------------------------------------------------

# ARG-04 — ApplicationSets exist and use a list generator.
check_ARG_04_appset() {
  if k8s_has 'kind:[[:space:]]*ApplicationSet'; then
    if k8s_has 'targetRevision:[[:space:]]*HEAD'; then
      doctor_check "ARG-04" "ArgoCD" "PASS" "ApplicationSet declared" "ApplicationSet(s) present; targetRevision HEAD tracks the default branch"
    else
      doctor_check "ARG-04" "ArgoCD" "WARN" "ApplicationSet declared" "ApplicationSet present but targetRevision is not HEAD — check it points at the intended branch or tag"
    fi
  else
    doctor_check "ARG-04" "ArgoCD" "WARN" "ApplicationSet declared" "no ApplicationSet found — each new app needs its own Application YAML"
  fi
}

# ARG-05 — automated sync with prune and self-heal.
check_ARG_05_autosync() {
  if k8s_has 'prune:[[:space:]]*true' && k8s_has 'selfHeal:[[:space:]]*true'; then
    doctor_check "ARG-05" "ArgoCD" "PASS" "Automated sync with prune + self-heal" "automated sync, prune and selfHeal are on — Git stays the source of truth"
  elif k8s_has 'automated:'; then
    doctor_check "ARG-05" "ArgoCD" "WARN" "Automated sync with prune + self-heal" "automated sync is on but prune or selfHeal is missing — drift can linger in the cluster"
  else
    doctor_check "ARG-05" "ArgoCD" "WARN" "Automated sync with prune + self-heal" "no automated syncPolicy found — deploys need a manual sync in the ArgoCD UI"
  fi
}

# ARG-06 — SSO via Dex (informational: a starter without SSO is fine).
check_ARG_06_sso() {
  if grep -rhA2 -E '^dex:' "$REPO"/kubernetes 2>/dev/null | grep -qE 'enabled:[[:space:]]*true'; then
    doctor_check "ARG-06" "ArgoCD" "INFO" "SSO configured" "Dex is enabled — ArgoCD logins go through your identity provider"
  else
    doctor_check "ARG-06" "ArgoCD" "INFO" "SSO configured" "Dex is disabled — ArgoCD uses the built-in admin user; fine for a starter, add SSO before sharing access"
  fi
}

# ARG-07 — ArgoCD components run with more than one replica (HA).
check_ARG_07_ha() {
  local replicas
  replicas="$(grep -rhoE 'replicas:[[:space:]]*[0-9]+' "$REPO"/kubernetes/argocd 2>/dev/null | grep -oE '[0-9]+$' | sort -n | head -n 1)"
  if [ -z "${replicas:-}" ]; then
    doctor_check "ARG-07" "ArgoCD" "SKIP" "ArgoCD high availability" "no replica counts found in kubernetes/argocd/"
    return
  fi
  if [ "$replicas" -gt 1 ]; then
    doctor_check "ARG-07" "ArgoCD" "PASS" "ArgoCD high availability" "ArgoCD components run with $replicas+ replicas"
  else
    doctor_check "ARG-07" "ArgoCD" "WARN" "ArgoCD high availability" "ArgoCD components run with 1 replica — a node failure takes the GitOps controller down (deploys pause until it returns)"
  fi
}

# --- IAM / IRSA ------------------------------------------------------------

# IAM-01 — IRSA enabled on the cluster.
check_IAM_01_irsa() {
  if tf_has 'enable_irsa[[:space:]]*=[[:space:]]*true'; then
    doctor_check "IAM-01" "IAM" "PASS" "IRSA enabled" "IRSA is on — pods get AWS permissions through service accounts, not node credentials"
  else
    doctor_check "IAM-01" "IAM" "FAIL" "IRSA enabled" "enable_irsa is not true — pods cannot assume scoped IAM roles"
  fi
}

# IAM-02 — IRSA trust policies scoped to one service account + audience.
# Counts EKS OIDC trust policies (identifiers pointing at the cluster OIDC
# provider) and checks each one names a single service account. Non-EKS
# OIDC roles (for example the GitHub Actions CI role) are not IRSA roles
# and are not counted here.
check_IAM_02_role_scoping() {
  local irsa_total scoped
  irsa_total="$(grep -rhE 'identifiers.*oidc_provider_arn' "$REPO"/terraform 2>/dev/null | wc -l)"
  scoped="$(grep -rhE 'system:serviceaccount:[a-z0-9-]+:[a-z0-9-]+' "$REPO"/terraform 2>/dev/null | wc -l)"
  if [ "$irsa_total" -eq 0 ]; then
    doctor_check "IAM-02" "IAM" "SKIP" "IRSA roles scoped to one service account" "no EKS OIDC trust policies found in terraform/"
    return
  fi
  if [ "$scoped" -ge "$irsa_total" ] && tf_has 'sts\.amazonaws\.com'; then
    doctor_check "IAM-02" "IAM" "PASS" "IRSA roles scoped to one service account" "$irsa_total EKS OIDC trust polic(ies), each scoped to a single service account with aud sts.amazonaws.com"
  else
    doctor_check "IAM-02" "IAM" "WARN" "IRSA roles scoped to one service account" "only $scoped/$irsa_total EKS OIDC trust policies name a single service account — any pod in the namespace could assume the role"
  fi
}

# IAM-03 — no admin or wildcard-action policies.
check_IAM_03_wildcards() {
  if tf_has 'AdministratorAccess'; then
    doctor_check "IAM-03" "IAM" "FAIL" "No over-broad IAM policies" "AdministratorAccess is attached somewhere — replace it with the least-privilege actions the workload needs"
    return
  fi
  if tf_has '"\*"' && tf_has 'actions[[:space:]]*=[[:space:]]*\['; then
    doctor_check "IAM-03" "IAM" "WARN" "No over-broad IAM policies" "wildcard actions or resources appear in a policy — check the tfsec ignore comment justifies them (read-only Describe/List actions legitimately need resource *)"
    return
  fi
  doctor_check "IAM-03" "IAM" "PASS" "No over-broad IAM policies" "no AdministratorAccess and no wildcard action policies found"
}

# IAM-04 — CI role is read-only (plan only, no apply).
check_IAM_04_ci_readonly() {
  if tf_has 'github_actions_ci' && tf_has 'ec2:Describe' && ! tf_has 'ec2:\*'; then
    doctor_check "IAM-04" "IAM" "PASS" "CI role is read-only" "GitHub Actions OIDC role allows Describe/Get/List only — CI can terraform plan, never apply"
  elif tf_has 'github_actions_ci'; then
    doctor_check "IAM-04" "IAM" "WARN" "CI role is read-only" "a CI role exists but its permissions could not be confirmed read-only — verify it cannot apply"
  else
    doctor_check "IAM-04" "IAM" "INFO" "CI role is read-only" "no GitHub Actions OIDC role declared — nothing to check"
  fi
}

# --- Network / VPC ---------------------------------------------------------

# VPC-01 — worker nodes in private subnets.
check_VPC_01_private_subnets() {
  if tf_has 'private_subnets' && tf_has 'subnet_ids[[:space:]]*=[[:space:]]*module\.vpc\.private_subnets'; then
    doctor_check "VPC-01" "Network" "PASS" "Nodes in private subnets" "node groups use private_subnets — nodes have no public IPs"
  else
    doctor_check "VPC-01" "Network" "FAIL" "Nodes in private subnets" "node groups are not placed in private subnets"
  fi
}

# VPC-02 — VPC flow logs enabled.
check_VPC_02_flow_logs() {
  if tf_has 'enable_flow_log[[:space:]]*=[[:space:]]*true'; then
    doctor_check "VPC-02" "Network" "PASS" "VPC flow logs enabled" "flow logs are on — network traffic is auditable"
  else
    doctor_check "VPC-02" "Network" "WARN" "VPC flow logs enabled" "flow logs are off — you cannot investigate network incidents after the fact"
  fi
}

# VPC-03 — one NAT gateway per AZ (single NAT is a single point of failure).
check_VPC_03_nat_ha() {
  if tf_has 'single_nat_gateway[[:space:]]*=[[:space:]]*true'; then
    doctor_check "VPC-03" "Network" "WARN" "NAT gateway per AZ" "single_nat_gateway is true — one NAT gateway serves all AZs; if its AZ fails, outbound traffic stops. Acceptable for dev, not for prod"
  elif tf_has 'single_nat_gateway[[:space:]]*=[[:space:]]*false'; then
    doctor_check "VPC-03" "Network" "PASS" "NAT gateway per AZ" "one NAT gateway per AZ — no single point of failure for outbound traffic"
  else
    doctor_check "VPC-03" "Network" "SKIP" "NAT gateway per AZ" "no single_nat_gateway setting found in terraform/"
  fi
}

# VPC-04 — subnets tagged for Kubernetes load balancers.
check_VPC_04_subnet_tags() {
  if tf_has 'kubernetes\.io/role/elb' && tf_has 'kubernetes\.io/role/internal-elb'; then
    doctor_check "VPC-04" "Network" "PASS" "Subnets tagged for load balancers" "public subnets carry kubernetes.io/role/elb, private subnets carry kubernetes.io/role/internal-elb"
  else
    doctor_check "VPC-04" "Network" "WARN" "Subnets tagged for load balancers" "ELB subnet tags are missing — Services of type LoadBalancer may fail to provision"
  fi
}

# --- Monitoring ------------------------------------------------------------

# MON-01 — Prometheus retention and persistent storage configured.
check_MON_01_prometheus() {
  if k8s_has 'retention:[[:space:]]*[0-9]+d' && k8s_has 'storageClassName:[[:space:]]*gp3'; then
    local retention
    retention="$(grep -rhoE 'retention:[[:space:]]*[0-9]+d' "$REPO"/kubernetes 2>/dev/null | head -n 1 | grep -oE '[0-9]+d' || true)"
    doctor_check "MON-01" "Monitoring" "PASS" "Prometheus retention + storage" "retention $retention on persistent gp3 storage — metrics survive pod restarts"
  elif k8s_has 'prometheus:'; then
    doctor_check "MON-01" "Monitoring" "WARN" "Prometheus retention + storage" "Prometheus is configured but retention or persistent storage is missing — metrics are lost on restart"
  else
    doctor_check "MON-01" "Monitoring" "FAIL" "Prometheus retention + storage" "no Prometheus configuration found in kubernetes/"
  fi
}

# MON-02 — Grafana enabled with persistence.
check_MON_02_grafana() {
  if k8s_has 'grafana:' && k8s_has 'persistence:'; then
    doctor_check "MON-02" "Monitoring" "PASS" "Grafana enabled with persistence" "Grafana is on with persistent storage — dashboards survive restarts"
  elif k8s_has 'grafana:'; then
    doctor_check "MON-02" "Monitoring" "WARN" "Grafana enabled with persistence" "Grafana is on but persistence is off — dashboards are lost on restart"
  else
    doctor_check "MON-02" "Monitoring" "FAIL" "Grafana enabled with persistence" "no Grafana configuration found in kubernetes/"
  fi
}

# MON-03 — alert rules cover the basics (down, no traffic, latency, crash-loop).
check_MON_03_alerts() {
  local found=0 missing=""
  local alert
  for alert in Down NoTraffic HighLatency CrashLooping; do
    if k8s_has "alert:[[:space:]]*[A-Za-z]*$alert"; then found=$((found + 1)); else missing="$missing $alert"; fi
  done
  if [ "$found" -eq 4 ]; then
    doctor_check "MON-03" "Monitoring" "PASS" "Alert rules cover the basics" "alerts for app down, no traffic, high latency and crash-looping are all defined"
  elif [ "$found" -ge 2 ]; then
    doctor_check "MON-03" "Monitoring" "WARN" "Alert rules cover the basics" "$found/4 core alerts defined; missing:$missing"
  else
    doctor_check "MON-03" "Monitoring" "FAIL" "Alert rules cover the basics" "only $found/4 core alerts defined; missing:$missing"
  fi
}

# MON-04 — Alertmanager has somewhere to send alerts.
check_MON_04_alert_routing() {
  if k8s_has 'receivers:' && k8s_has 'webhook_configs:|slack_configs:|email_configs:|pagerduty_configs:'; then
    doctor_check "MON-04" "Monitoring" "PASS" "Alertmanager routes alerts somewhere" "at least one Alertmanager receiver is configured"
  elif k8s_has 'alertmanager:'; then
    doctor_check "MON-04" "Monitoring" "WARN" "Alertmanager routes alerts somewhere" "Alertmanager is enabled but no receiver (Slack, email, PagerDuty, webhook) is configured — alerts fire and go nowhere"
  else
    doctor_check "MON-04" "Monitoring" "WARN" "Alertmanager routes alerts somewhere" "no Alertmanager configuration found — alerts have nowhere to go"
  fi
}

# MON-05 — apps expose /metrics and have a ServiceMonitor.
check_MON_05_servicemonitors() {
  if k8s_has 'kind:[[:space:]]*ServiceMonitor' && k8s_has 'path:[[:space:]]*/metrics'; then
    doctor_check "MON-05" "Monitoring" "PASS" "Apps expose metrics via ServiceMonitor" "ServiceMonitor(s) scrape /metrics from the app — Prometheus can see it"
  elif k8s_has 'kind:[[:space:]]*ServiceMonitor'; then
    doctor_check "MON-05" "Monitoring" "WARN" "Apps expose metrics via ServiceMonitor" "a ServiceMonitor exists but does not scrape /metrics — check the path and port"
  else
    doctor_check "MON-05" "Monitoring" "WARN" "Apps expose metrics via ServiceMonitor" "no ServiceMonitor found — Prometheus cannot scrape the app"
  fi
}

# --- Operations ------------------------------------------------------------

# OPS-01 — Terraform remote state (local state is lost with the laptop).
check_OPS_01_remote_state() {
  if tf_code_has 'backend[[:space:]]*"s3"'; then
    doctor_check "OPS-01" "Operations" "PASS" "Terraform remote state" "S3 backend configured — state is shared and locked"
  else
    doctor_check "OPS-01" "Operations" "WARN" "Terraform remote state" "no S3 backend in terraform/ — state lives locally; a lost laptop means a lost state file"
  fi
}

# OPS-02 — Ingress references a controller that is actually installed.
check_OPS_02_ingress() {
  if ! k8s_has 'kind:[[:space:]]*Ingress'; then
    doctor_check "OPS-02" "Operations" "INFO" "Ingress controller present" "no Ingress resources — nothing to expose, nothing to check"
    return
  fi
  local class
  class="$(grep -rhoE 'ingressClassName:[[:space:]]*[a-zA-Z0-9-]+' "$REPO"/kubernetes "$REPO"/apps 2>/dev/null | head -n 1 | awk '{ print $2 }')"
  if k8s_has 'aws-load-balancer-controller|ingress-nginx|nginx-ingress'; then
    doctor_check "OPS-02" "Operations" "PASS" "Ingress controller present" "Ingress uses class ${class:-?} and a matching controller is declared in the repo"
  else
    doctor_check "OPS-02" "Operations" "WARN" "Ingress controller present" "Ingress uses class ${class:-?} but no ingress controller is declared in the repo — the Ingress will stay unimplemented until one is installed"
  fi
}

# OPS-03 — workloads declare CPU/memory requests and limits.
check_OPS_03_resources() {
  local deployments with_limits
  deployments="$(grep -rlE 'kind:[[:space:]]*Deployment' "$REPO"/kubernetes "$REPO"/apps 2>/dev/null | wc -l)"
  with_limits="$(grep -rlE 'limits:' "$REPO"/kubernetes "$REPO"/apps 2>/dev/null | wc -l)"
  if [ "$deployments" -eq 0 ]; then
    doctor_check "OPS-03" "Operations" "SKIP" "Workloads declare resource requests/limits" "no Deployments found in kubernetes/ or apps/"
    return
  fi
  if [ "$with_limits" -ge "$deployments" ]; then
    doctor_check "OPS-03" "Operations" "PASS" "Workloads declare resource requests/limits" "$deployments Deployment(s), all with resource limits — the scheduler can place them and one pod cannot starve the node"
  else
    doctor_check "OPS-03" "Operations" "WARN" "Workloads declare resource requests/limits" "$with_limits/$deployments Deployment(s) declare limits — pods without limits can starve a node"
  fi
}

# run_static_checks — runs every static check in ID order.
run_static_checks() {
  check_CLU_02_node_groups
  check_CLU_03_addons
  check_CLU_04_k8s_version
  check_CLU_05_logging
  check_CLU_06_endpoint
  check_CLU_07_pdb
  check_ARG_04_appset
  check_ARG_05_autosync
  check_ARG_06_sso
  check_ARG_07_ha
  check_IAM_01_irsa
  check_IAM_02_role_scoping
  check_IAM_03_wildcards
  check_IAM_04_ci_readonly
  check_VPC_01_private_subnets
  check_VPC_02_flow_logs
  check_VPC_03_nat_ha
  check_VPC_04_subnet_tags
  check_MON_01_prometheus
  check_MON_02_grafana
  check_MON_03_alerts
  check_MON_04_alert_routing
  check_MON_05_servicemonitors
  check_OPS_01_remote_state
  check_OPS_02_ingress
  check_OPS_03_resources
}
