---
name: eks-gitops-doctor
description: Audit an EKS + ArgoCD GitOps setup end to end and write a scored report with fixes. Use when asked to check cluster health, ArgoCD sync/drift status, ApplicationSets, IRSA roles, VPC/subnets, control-plane logging, or Prometheus/Grafana monitoring gaps. Runs diagnostic commands only — read-only, never applies, deletes, scales, or edits anything in a cluster.
---

# eks-gitops-doctor

You are auditing an EKS + ArgoCD GitOps setup. Your job: run the checks,
score the setup honestly, and write a report the owner can act on.

## Rules (non-negotiable)

1. **Read-only.** You may run `kubectl get` / `kubectl describe`, `helm list`,
   `terraform plan`, and read files. You must never run `kubectl apply`,
   `kubectl delete`, `kubectl scale`, `terraform apply`, `helm install`,
   `helm upgrade`, or anything that changes a cluster, a repo, or AWS.
   If a fix needs a change, write it in the report — do not make it.
2. **No secrets.** Never print, copy, or store credentials, tokens, kubeconfigs,
   or secret values. The report contains findings, not secrets.
3. **Honest scoring.** A check you could not run is SKIP, not PASS. A check
   against a repo that is not deployed cannot speak for the live cluster —
   say so in the report. Never invent users, stars, uptime, or metrics.
4. **Report first, fix second.** The deliverable is the scored report with a
   prioritised fix list. Fixes are suggestions in the report, not actions.

## How to run it

The skill ships runnable scripts in `scripts/`. Prefer them over ad-hoc
commands — they encode the full check list and the scoring rubric.

```bash
# Static audit of a repo (no cluster needed — Terraform + manifests only)
./scripts/doctor.sh --static /path/to/eks-repo

# Live audit of the cluster kubectl points at
./scripts/doctor.sh --live

# Both, in one report
./scripts/doctor.sh --static /path/to/eks-repo --live

# Save the report to a file
./scripts/doctor.sh --static /path/to/eks-repo --output report.md
```

Exit code is 1 when any check FAILs, 0 otherwise, so CI can gate on it.

## What it checks

Six categories, 33 checks, weighted to 100. Full detail — what each check
looks at, why it matters, and how to fix it — is in `docs/checks.md`.

| Category | Weight | Covers |
| -------- | ------ | ------ |
| Cluster | 20% | Nodes and node groups, EKS add-on versions, Kubernetes version vs end of life, control-plane logging, public API endpoint, PodDisruptionBudgets |
| ArgoCD | 25% | Pods running, Applications Synced + Healthy, drift (OutOfSync), ApplicationSets, automated sync with prune + self-heal, SSO, high availability |
| IAM | 15% | IRSA enabled, trust policies scoped to one service account, no over-broad policies, CI role read-only |
| Network | 15% | Nodes in private subnets, VPC flow logs, NAT gateway per AZ, ELB subnet tags |
| Monitoring | 15% | Prometheus retention + storage, Grafana persistence, core alert rules, Alertmanager receivers, ServiceMonitors |
| Operations | 10% | Terraform remote state, Ingress controller present, resource requests/limits |

Checks that need a live cluster (`CLU-01`, `ARG-01`, `ARG-02`, `ARG-03`,
`MON-01L`, `HELM-01`, `TF-01`) are SKIPped in `--static` mode and excluded from scoring.

## Scoring

Each check is `PASS` (full credit), `WARN` (half credit — a real gap, not an
outage), `FAIL` (no credit), `INFO` (a note, excluded from scoring), or
`SKIP` (could not run, excluded from scoring). A category score is the
fraction of its scored checks passed; the overall score is the weighted sum.

| Score | Grade | Meaning |
| ----- | ----- | ------- |
| 90–100 | A | Healthy. Fix WARN items when convenient. |
| 75–89 | B | Good shape with a few gaps worth fixing. |
| 60–74 | C | Usable, but several gaps need attention. |
| 40–59 | D | Significant gaps — fix FAIL items before relying on the setup. |
| 0–39 | F | Not healthy — do not rely on this setup. |

## Report format

The script writes Markdown: a score table by category, an overall score and
grade, a findings table (one row per check), a fix list ordered FAIL first
then WARN, and a skipped-checks section. See `examples/sample-report.md` —
a real run against the author's
[eks-gitops-starter](https://github.com/XEESHANAKRAM/eks-gitops-starter)
repo (82/100, Grade B) — and `docs/sample-report.md` for a walkthrough of
every finding in it.

## When the user asks for a fix

1. Point at the check ID and the fix in `docs/checks.md`.
2. Show the exact change (file + diff) and ask before applying it — the
   skill itself never edits anything.
3. Re-run the doctor after the fix and confirm the check flips to PASS.

## Known limitations

- Static checks read Terraform and YAML with text matching, not a full
  parser. Unusual layouts (for example a value built from locals, or a
  `for_each` over add-ons) can produce a SKIP or a wrong WARN — the report
  says what was and was not found, so a human can judge.
- The bundled minimum Kubernetes version (currently 1.32) is a snapshot from
  November 2026. When AWS drops a version from standard support, bump
  `min_minor` in `scripts/checks/static.sh` and update `docs/checks.md`.
- `terraform plan` in `--live` mode needs AWS credentials and an already
  initialised `terraform/` directory (a `.terraform/` folder). The script
  never runs `terraform init` itself — initialising would write state and
  lock files into the repo, which is not read-only behaviour. If the repo
  is not initialised, `TF-01` reports `SKIP`.
