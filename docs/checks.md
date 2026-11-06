# Checks reference

Every check the doctor runs, what it looks at, why it matters, and how to
fix it. Check IDs are stable — the report, the docs, and the scripts all use
the same ones.

Results: `PASS` (full credit), `WARN` (half credit — a real gap, not an
outage), `FAIL` (no credit), `INFO` (a note, excluded from scoring), `SKIP`
(could not run, excluded from scoring).

Weights: Cluster 20% · ArgoCD 25% · IAM 15% · Network 15% · Monitoring 15% ·
Operations 10%.

---

## Cluster (20%)

### CLU-01 — Nodes Ready (live)

**What:** `kubectl get nodes` — every node must report `Ready`.
**Why:** A NotReady node is not scheduling pods. If your app has two
replicas and both land on the sick node, the app is down.
**Fix:** `kubectl describe node <name>` — check kubelet logs, disk pressure,
and memory pressure. Drain and replace the node if it does not recover.

### CLU-02 — Node group sizing (static)

**What:** `node_desired_size` and `node_min_size` are at least 2, and the
node group uses `module.vpc.private_subnets`.
**Why:** One node is a single point of failure; two is the minimum for a
workload that must survive a node loss. Private subnets mean nodes have no
public IPs.
**Fix:** Raise `node_desired_size` / `node_min_size` to 2 or more, and point
`subnet_ids` at the private subnets.

### CLU-03 — EKS add-ons declared (static)

**What:** `coredns`, `kube-proxy`, `vpc-cni`, and `aws-ebs-csi-driver` are
all declared in `cluster_addons`, ideally with `most_recent = true`.
**Why:** Missing CoreDNS breaks service discovery; missing VPC CNI breaks
pod networking; missing EBS CSI means no PersistentVolumes.
**Fix:** Add the missing add-on to `cluster_addons` in `terraform/eks.tf`
and `terraform apply`.

### CLU-04 — Kubernetes version current (static)

**What:** `kubernetes_version` is at or above the bundled floor (currently
**1.32**, set November 2026 — the oldest version still in AWS standard
support at the time of writing).
**Why:** A version past standard support is auto-upgraded by EKS on the
extended-support track, which AWS bills for — and you stop getting security
patches on the standard track.
**Fix:** Bump `kubernetes_version` (and the add-on versions) and upgrade
one minor version at a time. Update the floor in
`scripts/checks/static.sh` (`min_minor`) when AWS drops a version.

### CLU-05 — Control-plane logging (static)

**What:** All five log types are enabled: `api`, `audit`, `authenticator`,
`controllerManager`, `scheduler`.
**Why:** Without audit logs you cannot answer "who did what?" after an
incident. Without API logs you cannot debug a failing control plane.
**Fix:** Set `cluster_enabled_log_types` to all five in `terraform/eks.tf`.

### CLU-06 — Public API endpoint restricted (static)

**What:** `cluster_endpoint_public_access_cidrs` is not `0.0.0.0/0`
(checked in tfvars first, then the variable default).
**Why:** An open endpoint lets anyone on the internet reach your Kubernetes
API server. Authentication still protects it, but you are one leaked
credential away from a takeover.
**Fix:** Set `cluster_endpoint_public_access_cidrs` to your office/VPN CIDRs,
for example `["203.0.113.10/32"]`. For production, consider disabling the
public endpoint entirely (`cluster_endpoint_public_access = false`) and
reaching the API through a bastion or VPN.

### CLU-07 — PodDisruptionBudget present (static)

**What:** At least one `PodDisruptionBudget` exists in `kubernetes/` or
`apps/`.
**Why:** Without a PDB, a node drain or cluster upgrade can evict all
replicas of a workload at once.
**Fix:** Add a PDB per critical workload, for example `minAvailable: 1` for
a 2-replica app.

---

## ArgoCD (25%)

### ARG-01 — ArgoCD pods running (live)

**What:** Every pod in namespace `argocd` is `Running`.
**Why:** ArgoCD is the deploy pipeline. If its pods are down, nothing
deploys — and nothing self-heals.
**Fix:** `kubectl get pods -n argocd`, then `kubectl describe` / `kubectl logs`
on the failing pod.

### ARG-02 — Applications Synced + Healthy (live)

**What:** Every ArgoCD Application is `Synced` and `Healthy`.
**Why:** An unhealthy Application means the cluster is not running what Git
says it should run.
**Fix:** Open the Application in the ArgoCD UI, read the diff and the
resource health, fix the cause (often a bad image tag or a missing secret),
and let auto-sync converge it.

### ARG-03 — No drift, OutOfSync (live)

**What:** No Application reports `OutOfSync`.
**Why:** Drift means someone changed the cluster by hand, or Git moved and
the cluster has not caught up. Either way, Git is no longer the truth.
**Fix:** Check the UI diff. If the change was deliberate, commit it to Git.
If it was accidental, sync the Application to revert it.

### ARG-04 — ApplicationSet declared (static)

**What:** An `ApplicationSet` exists (a list generator is the usual pattern).
**Why:** Without one, every new app needs a hand-written Application YAML —
slow, and easy to get subtly wrong.
**Fix:** Add an ApplicationSet with a list generator; one element per app.

### ARG-05 — Automated sync with prune + self-heal (static)

**What:** `syncPolicy.automated` is on with `prune: true` and
`selfHeal: true` on the Applications.
**Why:** Prune deletes resources removed from Git; self-heal reverts manual
changes. Without them, GitOps is a suggestion, not a guarantee.
**Fix:** Add the `syncPolicy` block to the Application or ApplicationSet
template.

### ARG-06 — SSO configured (static, INFO)

**What:** Whether Dex is enabled in the ArgoCD Helm values.
**Why:** The built-in admin user is fine for a starter, but shared admin
passwords do not scale and cannot be revoked per person.
**Fix (when you are ready):** Enable Dex and wire it to your identity
provider (Google, GitHub, Okta). Until then, this stays an INFO note, not
a penalty.

### ARG-07 — ArgoCD high availability (static)

**What:** ArgoCD server, controller, and repo-server run with more than one
replica.
**Why:** One replica means one node failure pauses all deploys and
self-healing until the pod is rescheduled.
**Fix:** Set `replicas: 2` (or 3) for `server`, `controller`, and
`repoServer` in `kubernetes/argocd/values.yaml`. For real HA also run
`redis-ha` instead of the single Redis.

---

## IAM (15%)

### IAM-01 — IRSA enabled (static)

**What:** `enable_irsa = true` on the cluster.
**Why:** IRSA lets each pod assume its own scoped IAM role. Without it,
pods inherit the node's permissions — usually far broader than they need.
**Fix:** Set `enable_irsa = true` in `terraform/eks.tf`.

### IAM-02 — IRSA roles scoped to one service account (static)

**What:** Each EKS OIDC trust policy names a single
`system:serviceaccount:<namespace>:<name>` and audience `sts.amazonaws.com`.
**Why:** A trust policy scoped to a namespace (or to no subject at all) lets
any pod in that namespace assume the role.
**Fix:** Tighten the `StringEquals` condition on `:sub` to the exact service
account, and keep `:aud` as `sts.amazonaws.com`.

### IAM-03 — No over-broad IAM policies (static)

**What:** No `AdministratorAccess`, and no wildcard actions or resources
unless justified.
**Why:** A wildcard policy attached to a workload role is a privilege
escalation waiting for a vulnerability.
**Fix:** Replace wildcards with the exact actions and resources the workload
needs. Note: read-only `Describe*`/`Get*`/`List*` actions legitimately
require resource `*` — AWS does not support resource-level permissions for
them. If that is your case, keep the `tfsec:ignore` comment explaining why.

### IAM-04 — CI role is read-only (static)

**What:** A GitHub Actions OIDC role exists and allows `Describe`/`Get`/
`List` only — enough for `terraform plan`, never `apply`.
**Why:** CI that can apply can destroy. The apply step should be a human,
deliberate action.
**Fix:** Scope the CI role's policy to read-only actions, and keep
`terraform apply` out of the workflow.

---

## Network (15%)

### VPC-01 — Nodes in private subnets (static)

**What:** Node groups use `module.vpc.private_subnets`.
**Why:** Nodes with public IPs are directly reachable from the internet.
**Fix:** Point `subnet_ids` at the private subnets.

### VPC-02 — VPC flow logs enabled (static)

**What:** `enable_flow_log = true` on the VPC.
**Why:** Without flow logs, a network incident leaves no trail — you cannot
tell what talked to what.
**Fix:** Set `enable_flow_log = true` (CloudWatch Logs destination is the
usual choice).

### VPC-03 — NAT gateway per AZ (static)

**What:** `single_nat_gateway` is `false`.
**Why:** One NAT gateway serves all AZs. If its AZ fails, every private
subnet loses outbound internet — including the ability to pull images.
**Fix:** Set `single_nat_gateway = false`. It costs roughly $32/month per
extra gateway; that is the price of the redundancy. For a dev starter, one
gateway is a legitimate, documented trade-off — the check says WARN, not FAIL.

### VPC-04 — Subnets tagged for load balancers (static)

**What:** Public subnets carry `kubernetes.io/role/elb = 1`, private subnets
carry `kubernetes.io/role/internal-elb = 1`.
**Why:** The AWS cloud controller uses these tags to pick subnets for load
balancers. Without them, `Service` type `LoadBalancer` can fail to provision.
**Fix:** Add the tags in `terraform/vpc.tf`.

---

## Monitoring (15%)

### MON-01 — Prometheus retention + storage (static)

**What:** Prometheus has a `retention` (for example `15d`) and persistent
storage on `gp3`.
**Why:** Without persistence, a Prometheus restart wipes history — and with
it, the ability to see what happened before an incident.
**Fix:** Set `retention` and a `volumeClaimTemplate` with a `gp3` storage
class in the kube-prometheus-stack values.

### MON-01L — Prometheus pods running (live)

**What:** Prometheus pods in namespace `monitoring` are `Running`.
**Why:** A down Prometheus means no metrics, no alerts, and no history.
**Fix:** `kubectl get pods -n monitoring`, then describe/logs on the failing
pod — usually storage (PVC pending) or memory limits.

### MON-02 — Grafana enabled with persistence (static)

**What:** Grafana is enabled and has persistence on.
**Why:** Without persistence, dashboards are lost on every restart.
**Fix:** Enable `grafana.persistence` in the monitoring values.

### MON-03 — Alert rules cover the basics (static)

**What:** Alerts exist for app down, no traffic, high latency, and
crash-looping.
**Why:** These four catch most real incidents: the app is dead, the app is
up but nobody can reach it, the app is slow, or a pod keeps crashing.
**Fix:** Add the missing `PrometheusRule` entries — see
`kubernetes/monitoring/alert-rules.yaml` in eks-gitops-starter for a working
example.

### MON-04 — Alertmanager routes alerts somewhere (static)

**What:** Alertmanager has at least one receiver (`webhook_configs`,
`slack_configs`, `email_configs`, or `pagerduty_configs`).
**Why:** Alerts that fire and go nowhere are the same as no alerts. This is
the most common monitoring gap in small setups.
**Fix:** Add a receiver — a Slack webhook is the usual first one — in the
Alertmanager config.

### MON-05 — Apps expose metrics via ServiceMonitor (static)

**What:** A `ServiceMonitor` scrapes `/metrics` from the app.
**Why:** Without it, Prometheus never sees the app, and the app alerts in
MON-03 have nothing to evaluate.
**Fix:** Add a ServiceMonitor selecting the app's Service, with an endpoint
on `path: /metrics`.

---

## Operations (10%)

### OPS-01 — Terraform remote state (static)

**What:** An `s3` backend is configured (uncommented) in `terraform/`.
**Why:** Local state lives on one laptop. Lose the laptop, lose the state —
and with it, Terraform's memory of what exists.
**Fix:** Uncomment and fill in the `backend "s3"` block, then
`terraform init -reconfigure`.

### OPS-02 — Ingress controller present (static)

**What:** If any `Ingress` exists, a controller (AWS Load Balancer
Controller, NGINX) is declared in the repo.
**Why:** An Ingress with no controller is never implemented — the hostname
never resolves to anything.
**Fix:** Install a controller, or remove the Ingress until you do.

### OPS-03 — Workloads declare resource requests/limits (static)

**What:** Deployments declare CPU/memory `requests` and `limits`.
**Why:** Without requests the scheduler cannot place pods sensibly; without
limits one pod can starve a node.
**Fix:** Add `resources.requests` and `resources.limits` to each container.

### HELM-01 — Helm releases deployed (live)

**What:** Every Helm release reports status `deployed`.
**Why:** A release in `failed` or `pending-*` status means the last install
or upgrade did not complete — the cluster may be running a half-applied
chart.
**Fix:** `helm list -A`, then `helm history <release>` and `helm rollback`
or a corrected `helm upgrade`.

### TF-01 — Terraform plan is clean (live)

**What:** `terraform plan -detailed-exitcode` in the repo's `terraform/`
directory reports no changes. Runs only when `terraform` is installed and
the repo was already initialised (a `.terraform/` directory exists) — the
skill never runs `terraform init` itself, because that would write state
and lock files into the repo.
**Why:** A plan with pending changes means the real infrastructure has
drifted from what Git declares — or Git moved and nobody applied it.
**Fix:** Read the plan output, decide whether the change belongs in Git or
in the real world, then commit it or apply it deliberately.
