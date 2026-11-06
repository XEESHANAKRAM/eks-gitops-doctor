#!/usr/bin/env bash
# eks-gitops-doctor — audit an EKS + ArgoCD GitOps setup and write a scored report.
#
# Usage:
#   doctor.sh --static <repo-path> [--output report.md]   audit Terraform + manifests, no cluster needed
#   doctor.sh --live [--output report.md]                 audit the live cluster kubectl points at
#   doctor.sh --static <repo-path> --live                 both: static audit plus live cluster checks
#
# Read-only by design. The only commands it runs are file reads, kubectl get,
# helm list, and (in --live mode, if a terraform/ directory exists) terraform
# plan. It never applies, deletes, scales, or edits anything.
#
# Exit code: 0 when the report was written, 1 when FAIL checks exist,
# 2 on usage errors.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=checks/static.sh
source "$SCRIPT_DIR/checks/static.sh"
# shellcheck source=checks/live.sh
source "$SCRIPT_DIR/checks/live.sh"

MODE="static"
REPO="."
OUTPUT=""
RUN_LIVE=false

usage() {
  sed -n '2,12p' "$0"
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --static)
      MODE="static"; REPO="${2:?--static needs a repo path}"; shift 2 ;;
    --live)
      RUN_LIVE=true; shift ;;
    --output)
      OUTPUT="${2:?--output needs a file path}"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "error: unknown argument: $1" >&2; usage ;;
  esac
done

if [ "$RUN_LIVE" = true ] && [ "$MODE" = "static" ] && [ "$REPO" = "." ]; then
  MODE="live"
fi

if [ ! -d "$REPO" ]; then
  echo "error: repo path not found: $REPO" >&2
  exit 2
fi
REPO="$(cd "$REPO" && pwd)"

DOCTOR_RESULTS_FILE="$(mktemp)"
export DOCTOR_RESULTS_FILE
trap 'rm -f "$DOCTOR_RESULTS_FILE"' EXIT

GENERATED="$(date -u '+%Y-%m-%d %H:%M UTC')"

# Static checks always run when a repo path is given (they are the default).
if [ "$MODE" = "static" ]; then
  run_static_checks
fi

# Live checks run when --live is passed. In static-only mode they are
# recorded as SKIP so the report is honest about what was not covered.
if [ "$RUN_LIVE" = true ]; then
  run_live_checks
else
  doctor_check "CLU-01" "Cluster" "SKIP" "Nodes Ready" "live check not run — no cluster connected (use --live)"
  doctor_check "ARG-01" "ArgoCD" "SKIP" "ArgoCD pods running" "live check not run — no cluster connected (use --live)"
  doctor_check "ARG-02" "ArgoCD" "SKIP" "Applications Synced + Healthy" "live check not run — no cluster connected (use --live)"
  doctor_check "ARG-03" "ArgoCD" "SKIP" "No drift (OutOfSync)" "live check not run — no cluster connected (use --live)"
  doctor_check "MON-01L" "Monitoring" "SKIP" "Prometheus pods running" "live check not run — no cluster connected (use --live)"
  doctor_check "HELM-01" "Operations" "SKIP" "Helm releases deployed" "live check not run — no cluster connected (use --live)"
  doctor_check "TF-01" "Operations" "SKIP" "Terraform plan is clean" "live check not run — no cluster connected (use --live)"
fi

LABEL="$MODE"
[ "$RUN_LIVE" = true ] && [ "$MODE" = "static" ] && LABEL="static + live"

REPORT="$(doctor_render_report "$REPO" "$LABEL" "$GENERATED")"

if [ -n "$OUTPUT" ]; then
  printf '%s\n' "$REPORT" > "$OUTPUT"
  echo "Report written to $OUTPUT"
else
  printf '%s\n' "$REPORT"
fi

# Exit 1 when any check failed, so CI and scripts can gate on it.
FAIL_COUNT="$(awk -F'\t' '$3 == "FAIL" { c++ } END { print c + 0 }' "$DOCTOR_RESULTS_FILE")"
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "$FAIL_COUNT check(s) FAILED." >&2
  exit 1
fi
exit 0
