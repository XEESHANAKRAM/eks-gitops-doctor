# Troubleshooting

## `doctor.sh: command not found` / `Permission denied`

The script is not executable. Run:

```bash
chmod +x scripts/doctor.sh
./scripts/doctor.sh --static <repo>
```

## `error: repo path not found`

The `--static` path does not exist or is not a directory. Check the path —
it must be the repo root (the directory containing `terraform/`,
`kubernetes/`, `apps/`).

## Every check is SKIP

The repo layout does not match what the static checks expect. They look for:

```
<repo>/terraform/*.tf
<repo>/kubernetes/**/*.yaml
<repo>/apps/**/*.yaml
```

If your Terraform lives in `infra/` or your manifests in `manifests/`, the
checks cannot see them. Either restructure to the conventional layout or
symlink the directories into place. The report's SKIP details say which
files each check looked for.

## A check says WARN but the setup is actually fine

Static checks read files with text matching, not a full parser. Known
blind spots:

- Values built from `locals` or `for_each` (for example add-ons generated
  from a list) — the check looks for literal names and misses them.
- Settings in a file the check does not scan (for example a second
  `terraform/` directory, or values split across overlays).
- A `kubernetes_version` set in `terraform.tfvars` with a different key
  name.

If a WARN is wrong, confirm it by hand (`kubectl`, `terraform show`, or the
AWS console) and treat the report line as a prompt to check, not a verdict.
Open an issue with the repo layout if you think the check should handle it.

## Live checks all SKIP even though kubectl works

Run `kubectl cluster-info`. If that fails, the kubeconfig context is wrong
or expired — fix the context first (`kubectl config use-context <name>`).
The doctor never changes your kubeconfig; it only reads the current context.

## `HELM-01` is SKIP

`helm` is not installed, or there is no cluster context. Install Helm 3
(`https://helm.sh/docs/intro/install/`) and re-run.

## `terraform plan` in --live mode is SKIPped

`TF-01` runs only when `terraform` is installed **and** the repo's
`terraform/` directory was already initialised (a `.terraform/` folder
exists). The skill never runs `terraform init` itself — that would write
state and lock files into the repo. If the check is SKIPped, run
`terraform init` in the repo's `terraform/` directory yourself, then
re-run the doctor with `--live`.

## Shellcheck failures in CI

Run shellcheck locally first:

```bash
shellcheck --severity=warning scripts/doctor.sh scripts/lib/common.sh scripts/checks/*.sh
```

Fix the reported lines — usually unquoted variables or unused assignments.
Do not add `# shellcheck disable` comments without explaining why in the PR.

## Link check failures in CI

`python3 scripts/check-links.py .` lists the broken relative links. Fix the
target path in the Markdown file — do not delete the link to make the check
pass unless the section it pointed to is genuinely gone.
