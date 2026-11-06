# FAQ

## Does the skill change anything in my cluster?

No. It runs `kubectl get`, `helm list`, `terraform plan`, and file reads
only. It never applies, deletes, scales, or edits anything. The only thing
it writes is the report file, and only when you pass `--output`.

## Does it need a live cluster?

No. `--static` audits a repo's Terraform and manifests with no cluster at
all. The seven live checks are skipped and excluded from scoring.
Add `--live` when you have a cluster to check — a static report can only
speak for what is *declared*, not what is actually running.

## Does it send anything anywhere?

No. Everything runs locally on your machine. No telemetry, no network calls
except the ones `kubectl`, `helm`, and `terraform` make to your own cluster
and cloud account.

## Does it collect secrets?

No. It never reads Secret objects, kubeconfigs, or credential files, and
the report contains findings, not values. See [security](security.md).

## Can I use it in CI?

Yes — that is one of the main uses. It exits 1 when any check FAILs, so a
failing audit fails the workflow. See [usage](usage.md#in-ci).

## My repo layout is different — will it work?

Partly. The static checks look for `terraform/`, `kubernetes/`, and `apps/`
under the repo root. Checks that cannot find their files report `SKIP` with
the reason, so the report tells you what it could not see. If your layout is
different, symlink your directories into place or open an issue — layout
support is the most likely next improvement.

## The score dropped after I added a check — is that a bug?

Probably not. New checks change the denominator. A repo that was 90/100
across 26 checks can be 86/100 across 33 if the new checks find gaps. The
fix list tells you exactly what changed.

## Why is Kubernetes 1.31 a warning? It still works.

It works, but it is past standard support (the bundled floor is 1.32, set
November 2026). EKS keeps such clusters on the extended-support track and
bills for it, and standard-track security patches stop. The check is a WARN,
not a FAIL, for exactly this reason — it is a planning item, not an outage.

## Why does the CI role wildcard get a warning if it is unavoidable?

Because a reviewer should see it and agree, every time. Read-only
`Describe*`/`Get*`/`List*` actions legitimately need resource `*` — AWS
does not support resource-level permissions for them. The warning exists so
the exception stays visible and documented, instead of silently accepted.

## Who made this, and is it a copy of something?

It was built by Zeeshan Akram in November 2026, as a companion to his
[eks-gitops-starter](https://github.com/XEESHANAKRAM/eks-gitops-starter).
It is original work, written in the style of a complete, polished
open-source project — not a copy of anyone else's project, names, or
branding.

## The skill is new — are there really no users yet?

Correct: it was built in November 2026 and has no users, stars, or downloads
to quote yet. The README says so plainly. If you use it, an issue describing
your setup is the most useful feedback.
