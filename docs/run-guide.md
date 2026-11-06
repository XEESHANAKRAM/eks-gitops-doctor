# Run guide

A step-by-step run of the skill, with the output to expect at each step.
Outputs marked **(expected)** are illustrative — your numbers will differ.
Outputs marked **(real)** are copied from an actual run on 2026-11-06.

## Step 1 — Clone the skill

```bash
git clone https://github.com/XEESHANAKRAM/eks-gitops-doctor.git
cd eks-gitops-doctor
```

## Step 2 — Verify the install (fixture run)

```bash
./scripts/doctor.sh --static tests/fixtures/minimal-repo
```

**(Expected)** — a report ending with:

```
**Overall: 94/100 — Grade A**
21 passed, 2 warnings, 0 failures, 3 notes, 7 skipped.
```

The two warnings are deliberate (`CLU-07` no PodDisruptionBudget, `ARG-04`
no ApplicationSet). If you see a different score, the install is broken —
see [troubleshooting](troubleshooting.md).

## Step 3 — Audit a repo (static)

```bash
./scripts/doctor.sh --static /path/to/your-eks-repo --output report.md
```

**(Real)** — against the author's eks-gitops-starter repo:

```
Report written to report.md
```

and `report.md` starts:

```markdown
# EKS GitOps Health Report

- **Target:** `/home/hatch/workspace/github-profile/projects/eks-gitops-starter`
- **Mode:** static
- **Generated:** 2026-11-06 05:29 UTC
```

and ends:

```markdown
**Overall: 82/100 — Grade B**

Good shape with a few gaps worth fixing. Start with the WARN items in Cluster and ArgoCD.
```

The full real report is in
[`examples/sample-report.md`](../examples/sample-report.md); every finding
is explained in [`sample-report.md`](sample-report.md).

## Step 4 — Audit a live cluster

Point `kubectl` at your cluster first, then:

```bash
kubectl cluster-info   # confirm you can reach the cluster (expected: cluster info)
./scripts/doctor.sh --live --output live-report.md
```

**(Expected)** — the seven live checks now report `PASS`/`WARN`/`FAIL` instead
of `SKIP`, for example:

```
| CLU-01 | PASS | Nodes Ready — 3/3 nodes Ready |
| ARG-02 | PASS | Applications Synced + Healthy — 2/2 Applications Synced and Healthy |
```

If `kubectl` cannot reach a cluster, the live checks report `SKIP` with the
reason — the run still succeeds and still writes a report.

## Step 5 — Both together (the full audit)

```bash
./scripts/doctor.sh --static /path/to/your-eks-repo --live --output report.md
```

**(Expected)** — all 33 checks scored, no `SKIP`s except the ones whose tools
are genuinely missing (for example `HELM-01` when `helm` is not installed,
or `TF-01` when the repo was never `terraform init`ed).

## Step 6 — Act on the fix list

Open the report, work through **Fix list** top to bottom (FAIL first, then
WARN), and re-run the doctor after each fix to confirm the check flips to
`PASS`. The skill never applies fixes itself — you make the change, it
verifies it.

## What a healthy run looks like

**(Expected)** — a repo with everything in place:

```
**Overall: 94/100 — Grade A**
21 passed, 2 warnings, 0 failures, 3 notes, 7 skipped.
```

(The 7 skipped are the live checks, when no cluster is connected. With
`--live` against a healthy cluster, expect 27 passed, 2 warnings, 0
failures, 3 notes, 1 skipped (`TF-01`, unless the fixture repo was
`terraform init`ed) — 96/100, Grade A.)

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | Report written, no check FAILED |
| 1 | Report written, at least one check FAILED |
| 2 | Usage error (bad flag, missing repo path) |
