# Contributing to eks-gitops-doctor

Thanks for helping. This is a small, focused project: a skill that audits
EKS + ArgoCD setups and writes a scored report. Contributions that make the
checks more accurate, the report clearer, or the docs more honest are welcome.

## How to contribute

1. Fork the repo and create a branch: `git checkout -b fix/clu-06-edge-case`.
2. Make your change. If you add or change a check:
   - Add the check to `scripts/checks/static.sh` or `scripts/checks/live.sh`
     with an ID in the existing series (`CLU-`, `ARG-`, `IAM-`, `VPC-`,
     `MON-`, `OPS-`, `HELM-`).
   - Document it in `docs/checks.md` (what it checks, why it matters, how
     to fix) and in `SKILL.md` if it changes the category table.
   - Keep the check read-only. If a check needs a new command, it must be a
     diagnostic (`get`, `describe`, `list`, `plan`) — never `apply`,
     `delete`, `scale`, or `edit`.
3. Run the local checks (see below) and make sure they pass.
4. Update `CHANGELOG.md` under `[Unreleased]`.
5. Open a pull request. Describe what you changed, which repo or cluster you
   tested against, and paste the before/after report lines for the affected
   checks.

## Local checks

```bash
bash -n scripts/doctor.sh scripts/lib/common.sh scripts/checks/*.sh
shellcheck scripts/doctor.sh scripts/lib/common.sh scripts/checks/*.sh
python3 scripts/check-links.py .
./scripts/doctor.sh --static tests/fixtures/minimal-repo
```

The fixture run must exit 0 and report `Overall: 94/100 — Grade A` with
exactly the two deliberate warnings (`CLU-07`, `ARG-04`). If your change
alters that, update the fixture or the expected values in CI — and say why
in the PR.

## Style

- Bash: `set -euo pipefail`, double-quote variables, `snake_case` functions.
  Keep functions short and one check per function.
- Markdown: one sentence per line where practical (cleaner diffs), ATX
  headings, tables for comparisons.
- Docs: plain language, no hype. If a claim cannot be verified, do not
  write it. Never invent users, stars, or metrics.

## Reporting issues

Open an issue with:

- The command you ran and the report output (or the failing lines).
- The repo layout if it is a static-check miss (which files live where).
- `kubectl version` / `terraform version` if it is a live-check problem.

Security issues (for example a check that leaks a secret into a report):
see `docs/security.md` — report them privately first.
