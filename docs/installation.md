# Installation

## Requirements

| Need | For | Version |
| ---- | --- | ------- |
| `bash` | Everything | 4+ (`bash --version`) |
| `grep`, `awk`, `sed` | Text checks | Any modern version |
| `python3` | The Markdown link check (`scripts/check-links.py`) | 3.8+ |
| `kubectl` | `--live` checks only | Any version that talks to your cluster |
| `helm` | The Helm release check (`HELM-01`) only | 3.x |
| `terraform` | `terraform plan` in `--live` mode (planned, optional) | 1.5+ |

No other dependencies. There is nothing to compile and no package to
install — the skill is a set of shell scripts plus docs.

## Install

```bash
git clone https://github.com/XEESHANAKRAM/eks-gitops-doctor.git
cd eks-gitops-doctor
chmod +x scripts/doctor.sh
```

That is the whole install. The scripts are meant to be run from the repo
directory, but `doctor.sh` works from anywhere — it finds its own `lib/`
and `checks/` relative to its own location.

## Use as an agent skill

If your agent supports the open Agent Skills format (Claude Code, Codex,
Cursor), point it at this repo or copy the repo into your skills directory.
`SKILL.md` carries the name, description, rules, and scoring rubric; the
agent reads it and runs `scripts/doctor.sh` for you. No extra setup.

## Verify the install

```bash
# Syntax-check every script
bash -n scripts/doctor.sh scripts/lib/common.sh scripts/checks/*.sh

# Run the doctor against the bundled fixture repo — expect Grade A, 94/100
./scripts/doctor.sh --static tests/fixtures/minimal-repo
```

If that prints a report ending in `Overall: 94/100 — Grade A`, the install
is good. If it does not, see [troubleshooting](troubleshooting.md).
