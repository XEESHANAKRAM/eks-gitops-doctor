# Security

## Read-only guarantee

eks-gitops-doctor is a diagnostic tool. The only commands it runs are:

| Command | What it does |
| ------- | ------------ |
| File reads (`grep`, `awk`) | Reads Terraform and YAML files in the audited repo |
| `kubectl get` / `kubectl describe` | Reads cluster state |
| `helm list` | Reads Helm release status |
| `terraform plan -detailed-exitcode` | Compares declared config with real infrastructure |

It never runs `kubectl apply`, `kubectl delete`, `kubectl scale`,
`terraform apply`, `helm install`, `helm upgrade`, or any other command
that changes a cluster, a repo, or a cloud account. If a fix needs a
change, the skill writes it in the report — it does not make it.

Two details worth knowing:

- `terraform plan` refreshes remote state, which is a read against your
  AWS account and state backend. It changes nothing, but it does need AWS
  credentials. It runs only when the repo was already `terraform init`ed;
  the skill never runs `terraform init` itself, because that would write
  state and lock files into the repo.
- The skill never modifies your kubeconfig. It uses whichever context is
  already current.

## No secrets collected

The skill never reads, prints, copies, or stores:

- Kubernetes Secret objects or their values
- Kubeconfig credentials or tokens
- AWS credentials or session tokens
- Passwords, private keys, or certificates

The report contains check results and file paths — findings, not values.
If you ever see a secret in a report, that is a bug: report it privately
(see below) and do not share the report.

## What the skill does with your data

Nothing leaves your machine. The scripts run locally; there is no telemetry,
no analytics, and no network call except the ones `kubectl`, `helm`, and
`terraform` make to your own cluster and cloud account. The report file is
written only where you tell it to (`--output`), and `.gitignore` excludes
generated reports (`report.md`, `doctor-report*.md`) so they are not
committed by accident.

## Reporting a security issue

If you find a check that leaks a secret, a command that writes where it
should only read, or any other security problem, please report it privately
first — open a GitHub issue titled "SECURITY" with minimal detail and ask
for a contact, or email the maintainer — and give time to fix it before
disclosing publicly.
