# Sample report walkthrough

This walks through every finding in
[`examples/sample-report.md`](../examples/sample-report.md) — a **real** run
of the skill against the author's own
[eks-gitops-starter](https://github.com/XEESHANAKRAM/eks-gitops-starter)
repo, produced on 2026-11-06 with:

```bash
./scripts/doctor.sh --static ../eks-gitops-starter --output examples/sample-report.md
```

The starter is **not deployed** — there is no live cluster behind it — so the
seven live checks are honestly `SKIP`ped. This is a static audit of the repo's
Terraform and manifests only. The score therefore reflects the *declared*
setup, not a running cluster.

## The headline

```
Overall: 82/100 — Grade B
16 passed, 9 warnings, 0 failures, 1 notes, 7 skipped.
```

Grade B means: good shape with a few gaps worth fixing. Zero FAILs means
nothing is broken outright. The nine WARNs are the fix list, in priority
order.

## Score by category

| Category | Score | Why |
| -------- | ----- | --- |
| Cluster 20% | 75% | 1.31 past support, no PDB, open endpoint |
| ArgoCD 25% | 83% | Single-replica components |
| IAM 15% | 88% | Read-only wildcard policy (documented, unavoidable) |
| Network 15% | 88% | Single NAT gateway (documented cost trade-off) |
| Monitoring 15% | 90% | Alertmanager has no receiver |
| Operations 10% | 67% | Local state, Ingress with no controller |

Operations scores lowest — two of its three checks are WARN. That is where
the cheapest fixes live.

## The nine warnings, one by one

### 1. CLU-04 — Kubernetes 1.31 is past standard support

The starter pins `kubernetes_version = "1.31"`. Kubernetes 1.31 reached end
of life in October 2025; EKS standard support has ended too. The fix is an
upgrade to 1.32 or newer, one minor version at a time, with the add-ons
bumped alongside. Until then EKS keeps the cluster on the extended-support
track and bills for it.

### 2. CLU-06 — Public API endpoint allows 0.0.0.0/0

The variable `cluster_endpoint_public_access_cidrs` defaults to
`["0.0.0.0/0"]`. The starter does this deliberately so it works out of the
box with `kubectl`, and its own docs say to restrict it — but the default is
still open. Fix: set it to your IPs, for example `["203.0.113.10/32"]`.

### 3. CLU-07 — No PodDisruptionBudget

No PDB exists anywhere in `kubernetes/` or `apps/`. The demo app runs two
replicas, so a node drain could evict both at once. Fix: add a PDB with
`minAvailable: 1` for the demo app.

### 4. ARG-07 — ArgoCD runs with 1 replica

Server, controller, and repo-server all run a single replica. A node failure
pauses deploys and self-healing until the pod is rescheduled. Fix: set
`replicas: 2` in `kubernetes/argocd/values.yaml`. (For a dev starter this is
acceptable; for anything shared, fix it.)

### 5. IAM-03 — Wildcard in the CI policy

The GitHub Actions CI role uses `ec2:Describe*`, `eks:Describe*`, and
friends on resource `*`. This is a WARN, not a FAIL, because AWS does not
support resource-level permissions for those read-only actions — the
wildcard is unavoidable, and the role is read-only and CI-only. The starter
documents this with a `tfsec:ignore` comment. Nothing to fix; the warning
exists so a reviewer sees it and agrees.

### 6. VPC-03 — Single NAT gateway

`single_nat_gateway = true` in the tfvars. One gateway serves all three AZs,
so an AZ failure cuts outbound internet for every private subnet. This is a
documented cost trade-off (about $32/month saved per gateway) and fine for
dev. For production, set it to `false`.

### 7. MON-04 — Alertmanager has no receiver

Alertmanager is enabled, but no Slack, email, PagerDuty, or webhook receiver
is configured. The five alert rules fire — and nobody hears them. This is the
most actionable finding in the report: add one Slack webhook receiver and
the whole alerting chain starts working.

### 8. OPS-01 — No Terraform remote state

The S3 backend block in `terraform/versions.tf` is commented out, so state
lives on whoever ran `apply` last. Fix: uncomment it, create the bucket, and
`terraform init -reconfigure`.

### 9. OPS-02 — Ingress with no controller

`apps/demo-app/k8s/ingress.yaml` declares an Ingress with class `nginx`,
but no ingress controller is installed anywhere in the repo. The Ingress
will stay unimplemented until one is. Fix: install NGINX Ingress or the AWS
Load Balancer Controller, or delete the Ingress until you do.

## What passed, and why it matters

The passes are as informative as the warnings: all five control-plane log
types are on (CLU-05), nodes are in private subnets (VPC-01), flow logs are
on (VPC-02), IRSA is on with both roles scoped to a single service account
(IAM-01, IAM-02), ArgoCD auto-sync has prune + self-heal (ARG-05), the
ApplicationSet pattern is in place (ARG-04), Prometheus keeps 15 days on
persistent gp3 storage (MON-01), Grafana persists (MON-02), all four core
alerts exist (MON-03), the demo app exposes `/metrics` via a ServiceMonitor
(MON-05), and the demo Deployment has requests and limits (OPS-03).

## What was skipped, and what it would take to cover

Six checks need a live cluster: node readiness (CLU-01), ArgoCD pods
(ARG-01), Application sync + health (ARG-02), drift (ARG-03), Prometheus
pods (MON-01L), Helm release status (HELM-01), and `terraform plan`
(TF-01). To cover them, deploy the starter and run:

```bash
./scripts/doctor.sh --static ../eks-gitops-starter --live --output report.md
```

Until the starter is deployed, any claim about the *running* cluster would
be invented — so the report does not make one.
