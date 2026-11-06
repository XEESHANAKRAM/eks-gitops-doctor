#!/usr/bin/env bash
# eks-gitops-doctor — shared check framework.
# Sourced by scripts/doctor.sh and the check modules. Not meant to be run directly.
#
# How it works:
#   1. doctor.sh creates a results file and exports DOCTOR_RESULTS_FILE.
#   2. Each check calls doctor_check with an ID, category, status and detail.
#   3. doctor_render_report reads the results, scores them and prints Markdown.
#
# Statuses: PASS | WARN | FAIL | INFO | SKIP
#   PASS — the check is satisfied.
#   WARN — a real gap, but not an outage (half credit).
#   FAIL — broken or missing (no credit).
#   INFO — a note for the reader; excluded from scoring.
#   SKIP — could not run (for example no live cluster); excluded from scoring.
#
# Category weights sum to 100. A category score is the fraction of its
# scored checks passed (WARN counts as half). The overall score is the
# weighted sum of the category scores.

# Category weights (must sum to 100).
declare -A DOCTOR_WEIGHTS=(
  [Cluster]=20
  [ArgoCD]=25
  [IAM]=15
  [Network]=15
  [Monitoring]=15
  [Operations]=10
)

# Ordered list of categories, for stable report output.
DOCTOR_CATEGORIES=(Cluster ArgoCD IAM Network Monitoring Operations)

# doctor_check <id> <category> <status> <title> <detail>
# Records one check result. Detail is a single line (no newlines).
doctor_check() {
  local id="$1" category="$2" status="$3" title="$4" detail="$5"
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$category" "$status" "$title" "$detail" >> "$DOCTOR_RESULTS_FILE"
}

# doctor_grade <score> — letter grade for a 0-100 score.
doctor_grade() {
  local score="$1"
  if awk -v s="$score" 'BEGIN { exit !(s >= 90) }'; then echo "A"
  elif awk -v s="$score" 'BEGIN { exit !(s >= 75) }'; then echo "B"
  elif awk -v s="$score" 'BEGIN { exit !(s >= 60) }'; then echo "C"
  elif awk -v s="$score" 'BEGIN { exit !(s >= 40) }'; then echo "D"
  else echo "F"; fi
}

# doctor_render_report <target> <mode> <generated-date>
# Prints the full Markdown report to stdout.
doctor_render_report() {
  local target="$1" mode="$2" generated="$3"
  local results="$DOCTOR_RESULTS_FILE"

  local total_pass=0 total_warn=0 total_fail=0 total_info=0 total_skip=0
  local overall=0

  # Per-category tallies, computed with awk from the results file.
  echo "# EKS GitOps Health Report"
  echo
  echo "- **Target:** \`$target\`"
  echo "- **Mode:** $mode"
  echo "- **Generated:** $generated"
  echo "- **Skill:** eks-gitops-doctor (read-only audit — nothing was applied, deleted, scaled, or edited)"
  echo

  # --- Score by category ---
  echo "## Score"
  echo
  echo "| Category | Weight | Checks scored | Score |"
  echo "| -------- | ------ | ------------- | ----- |"

  local cat earned possible pct weighted
  for cat in "${DOCTOR_CATEGORIES[@]}"; do
    read -r earned possible <<< "$(awk -F'\t' -v c="$cat" '
      $2 == c && $3 == "PASS" { p++ }
      $2 == c && $3 == "WARN" { w++ }
      $2 == c && $3 == "FAIL" { f++ }
      END {
        earned = (p * 1) + (w * 0.5)
        possible = p + w + f
        printf "%s %s", earned, possible
      }' "$results")"
    if [ "$possible" -gt 0 ]; then
      pct="$(awk -v e="$earned" -v p="$possible" 'BEGIN { printf "%.0f", (e / p) * 100 }')"
      weighted="$(awk -v p="$pct" -v w="${DOCTOR_WEIGHTS[$cat]}" 'BEGIN { printf "%.2f", (p * w) / 100 }')"
      overall="$(awk -v o="$overall" -v w="$weighted" 'BEGIN { printf "%.2f", o + w }')"
      printf '| %s | %s%% | %s/%s | %s%% |\n' "$cat" "${DOCTOR_WEIGHTS[$cat]}" "$earned" "$possible" "$pct"
    else
      printf '| %s | %s%% | 0/0 (all skipped) | — |\n' "$cat" "${DOCTOR_WEIGHTS[$cat]}"
    fi
  done

  local overall_int grade
  overall_int="$(awk -v o="$overall" 'BEGIN { printf "%.0f", o }')"
  grade="$(doctor_grade "$overall_int")"

  echo
  echo "**Overall: $overall_int/100 — Grade $grade**"
  echo
  case "$grade" in
    A) echo "Healthy. Fix the WARN items when convenient; nothing is urgent." ;;
    B) echo "Good shape with a few gaps worth fixing. Start with the WARN items in Cluster and ArgoCD." ;;
    C) echo "Usable, but several gaps need attention. Work through the WARN and FAIL items in priority order." ;;
    D) echo "Significant gaps. Treat the FAIL items as a fix list before relying on this setup." ;;
    F) echo "Not healthy. Do not rely on this setup until the FAIL items are fixed." ;;
  esac
  echo

  # --- Findings ---
  echo "## Findings"
  echo

  # Counts for the summary line.
  total_pass="$(awk -F'\t' '$3 == "PASS" { c++ } END { print c + 0 }' "$results")"
  total_warn="$(awk -F'\t' '$3 == "WARN" { c++ } END { print c + 0 }' "$results")"
  total_fail="$(awk -F'\t' '$3 == "FAIL" { c++ } END { print c + 0 }' "$results")"
  total_info="$(awk -F'\t' '$3 == "INFO" { c++ } END { print c + 0 }' "$results")"
  total_skip="$(awk -F'\t' '$3 == "SKIP" { c++ } END { print c + 0 }' "$results")"
  echo "$total_pass passed, $total_warn warnings, $total_fail failures, $total_info notes, $total_skip skipped."
  echo

  echo "| Check | Result | What it means |"
  echo "| ----- | ------ | ------------- |"
  awk -F'\t' '{ printf "| %s | %s | %s — %s |\n", $1, $3, $4, $5 }' "$results"
  echo

  # --- Fix list (FAIL first, then WARN) ---
  if [ "$total_fail" -gt 0 ] || [ "$total_warn" -gt 0 ]; then
    echo "## Fix list (highest priority first)"
    echo
    awk -F'\t' '$3 == "FAIL" { printf "1. **%s — %s**: %s\n", $1, $4, $5 }' "$results"
    awk -F'\t' '$3 == "WARN" { printf "1. **%s — %s**: %s\n", $1, $4, $5 }' "$results"
    echo
    echo "See \`docs/checks.md\` in the eks-gitops-doctor repo for what each check"
    echo "looks at, why it matters, and how to fix it."
    echo
  fi

  if [ "$total_skip" -gt 0 ]; then
    echo "## Skipped checks"
    echo
    echo "These checks need a live cluster and were not run in this mode:"
    echo
    awk -F'\t' '$3 == "SKIP" { printf "- **%s — %s**: %s\n", $1, $4, $5 }' "$results"
    echo
    echo "Run \`./scripts/doctor.sh --live\` with \`kubectl\` pointed at the cluster to cover them."
    echo
  fi

  echo "---"
  echo
  echo "_Generated by [eks-gitops-doctor](https://github.com/XEESHANAKRAM/eks-gitops-doctor) — read-only audit. No changes were made to the cluster or the repo._"
}
