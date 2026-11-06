# Usage

## Run modes

```bash
# Static audit — reads Terraform + manifests, no cluster needed
./scripts/doctor.sh --static /path/to/your-eks-repo

# Live audit — checks the cluster kubectl points at
./scripts/doctor.sh --live

# Both in one report (recommended when the repo is deployed)
./scripts/doctor.sh --static /path/to/your-eks-repo --live

# Save the report instead of printing it
./scripts/doctor.sh --static /path/to/your-eks-repo --output report.md
```

## What each mode covers

| Mode | Checks run | Needs |
| ---- | ---------- | ----- |
| `--static <repo>` | 26 static checks over `terraform/`, `kubernetes/`, `apps/` | The repo on disk |
| `--live` | 7 live checks (`CLU-01`, `ARG-01`, `ARG-02`, `ARG-03`, `MON-01L`, `HELM-01`, `TF-01`) | `kubectl` with a working context |
| Both | All 33 | Both of the above |

In `--static` mode the seven live checks are recorded as `SKIP` and excluded
from scoring, so the report is honest about what was not covered. A static
report can only speak for what is *declared* in the repo — a live cluster
can still have drifted from it. Run `--live` when you can.

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | Report written, no check FAILED |
| 1 | Report written, at least one check FAILED |
| 2 | Usage error (bad flag, missing repo path) |

CI can gate on the exit code: fail the build when the audit finds a FAIL.

## Reading the report

The report is Markdown with five sections:

1. **Score** — one row per category with its weight and score, then the
   overall score and grade (A–F). See [SKILL.md](../SKILL.md#scoring) for
   the bands.
2. **Findings** — one row per check: ID, result (`PASS` / `WARN` / `FAIL` /
   `INFO` / `SKIP`), and what it means in plain language.
3. **Fix list** — FAIL items first, then WARN items, in check order. This is
   the work list.
4. **Skipped checks** — what was not run and why, and the command that would
   cover it.
5. Footer — what generated the report and the read-only promise.

A real example is in
[`examples/sample-report.md`](../examples/sample-report.md), walked through
in [`sample-report.md`](sample-report.md).

## In CI

Run the doctor against the repo itself on every push, so a bad change fails
the build before it reaches the cluster:

```yaml
- name: Audit the platform repo
  run: ./scripts/doctor.sh --static . --output doctor-report.md
- name: Upload the report
  uses: actions/upload-artifact@v4
  with:
    name: eks-gitops-doctor-report
    path: doctor-report.md
```

Because the doctor exits 1 on any FAIL, a failing audit fails the workflow.
WARNs do not fail the build — they are the fix list, not a gate.

## Repo layout the static checks expect

The static checks look for the conventional layout used by
[eks-gitops-starter](https://github.com/XEESHANAKRAM/eks-gitops-starter):

```
your-repo/
  terraform/     # *.tf — cluster, VPC, IAM
  kubernetes/    # ArgoCD values, monitoring values, alert rules
  apps/          # app manifests (Deployments, Services, ServiceMonitors)
```

If your repo lays things out differently, the checks that cannot find their
files report `SKIP` with the reason — the report will tell you what it could
not see. See [troubleshooting](troubleshooting.md) for the common cases.
