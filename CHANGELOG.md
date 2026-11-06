# Changelog

All notable changes to eks-gitops-doctor are recorded here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-11-06

### Added

- Initial release.
- `SKILL.md` in the open Agent Skills format (name + description frontmatter).
- `scripts/doctor.sh`: static audit of Terraform + Kubernetes manifests,
  live audit via `kubectl`/`helm`/`terraform plan`, Markdown report with
  weighted scoring (6 categories, 33 checks, grades A–F). Read-only by design.
- Static checks: cluster health, add-ons, Kubernetes version vs end of life,
  control-plane logging, public API endpoint, PodDisruptionBudgets, ArgoCD
  ApplicationSets and auto-sync, IRSA role scoping, VPC/subnets and flow
  logs, Prometheus/Grafana/alerts, remote state, Ingress, resource limits.
- Live checks: node readiness, ArgoCD pods, Application sync + health,
  drift, Prometheus pods, Helm release status, and `terraform plan` drift
  (runs only when the repo was already `terraform init`ed; never runs init).
- `examples/sample-report.md`: real run against the author's
  eks-gitops-starter repo (82/100, Grade B), with a walkthrough in
  `docs/sample-report.md`.
- Docs: installation, usage, run guide, checks reference, troubleshooting,
  FAQ, security. Architecture diagram as hand-written SVG.
- CI: `bash -n`, shellcheck, SKILL.md frontmatter validation, Markdown link
  check, and an end-to-end doctor run against a fixture repo.
