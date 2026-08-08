#!/usr/bin/env bash
# Turns one package's lint.json (+ optional deprecation-scan.json) into GitHub
# annotations and a markdown fragment for the sticky comment. Prefers core's
# own package-ci/annotate.php — the shared implementation docs/MARKET.md §6.4
# in mindstellar/shopclass calls for — and falls back to a minimal renderer
# here when that tool hasn't shipped in this run's package-ci/ (see
# fetch-package-ci.sh and its MISSING.txt).
#
# Usage: tools/annotate-result.sh <slug> <out-dir> <package-ci-dir> <fragment.md>
# Exit 0 = no error-level finding, 1 = at least one.
set -euo pipefail

SLUG="${1:?usage: annotate-result.sh <slug> <out-dir> <package-ci-dir> <fragment.md>}"
OUT_DIR="${2:?}"
PACKAGE_CI_DIR="${3:?}"
FRAGMENT="${4:?}"

LINT_JSON="${OUT_DIR}/lint.json"
if [[ ! -f "${LINT_JSON}" ]]; then
  echo "annotate-result.sh: ${LINT_JSON} not found (validation step did not run to completion)." >&2
  exit 1
fi

if [[ -f "${PACKAGE_CI_DIR}/annotate.php" ]]; then
  # Note: smoke.json is deliberately not passed here — validate-theme.sh
  # already folds smoke-install findings into lint.json's errors/warnings
  # (so its own exit code is correct with or without annotate.php), and
  # annotate.php would otherwise report the same findings a second time
  # under a separate "Smoke install" gate.
  args=(--slug="${SLUG}" --lint="${LINT_JSON}" --comment-out="${FRAGMENT}")
  [[ -f "${OUT_DIR}/deprecation-scan.json" ]] && args+=(--deprecations="${OUT_DIR}/deprecation-scan.json")
  php "${PACKAGE_CI_DIR}/annotate.php" "${args[@]}"
  exit $?
fi

echo "::notice::package-ci/annotate.php is not available this run — using the fallback renderer." >&2

DEP_JSON="${OUT_DIR}/deprecation-scan.json"
dep_warnings_count=0
if [[ -f "${DEP_JSON}" ]] && jq empty "${DEP_JSON}" 2>/dev/null; then
  dep_warnings_count="$(jq '.warnings | length' "${DEP_JSON}")"
fi

errors_count="$(jq '.errors | length' "${LINT_JSON}")"
warnings_count="$(jq '.warnings | length' "${LINT_JSON}")"

jq -r '.errors[] | if .line then "::error file=\(.file // ""),line=\(.line)::\(.message)" else "::error::\(.message)" end' "${LINT_JSON}"
jq -r '.warnings[] | if .line then "::warning file=\(.file // ""),line=\(.line)::\(.message)" else "::warning::\(.message)" end' "${LINT_JSON}"
if [[ "${dep_warnings_count}" -gt 0 ]]; then
  jq -r '.warnings[] | if .line then "::warning file=\(.file // ""),line=\(.line)::[deprecated API] \(.message)" else "::warning::[deprecated API] \(.message)" end' "${DEP_JSON}"
fi

{
  echo "## Package CI — \`${SLUG}\`"
  echo
  echo "| Errors | Warnings | Deprecated-API warnings |"
  echo "|---|---|---|"
  echo "| ${errors_count} | ${warnings_count} | ${dep_warnings_count} |"
  echo
  echo "### Errors"
  echo
  if [[ "${errors_count}" -eq 0 ]]; then
    echo "None."
  else
    jq -r '.errors[] | "- " + .message' "${LINT_JSON}"
  fi
  echo
  echo "### Warnings — not blocking"
  echo
  if [[ "${warnings_count}" -eq 0 && "${dep_warnings_count}" -eq 0 ]]; then
    echo "None."
  else
    jq -r '.warnings[] | "- " + .message' "${LINT_JSON}"
    [[ "${dep_warnings_count}" -gt 0 ]] && jq -r '.warnings[] | "- [deprecated API] " + .message' "${DEP_JSON}"
  fi
} >"${FRAGMENT}"

[[ "${errors_count}" -eq 0 ]] && exit 0
exit 1
