#!/usr/bin/env bash
# Assembles the one sticky PR comment from per-package fragments
# (tools/annotate-result.sh output), or reports "nothing changed" when the
# PR touched no package — the comment always appears, so a clean run is
# visible rather than silent.
#
# Usage: tools/build-sticky-comment.sh <fragments-dir> <any:true|false>
# Prints the full comment body (including the hidden marker) to stdout.
set -euo pipefail

FRAGMENTS_DIR="${1:?usage: build-sticky-comment.sh <fragments-dir> <any>}"
ANY="${2:?}"
MARKER="<!-- shopclass-themes:pr-validate -->"

echo "${MARKER}"
echo
echo "# PR validation"
echo

if [[ "${ANY}" != "true" ]]; then
  echo "No package changes in this PR — no \`external/*.json\` registration and no \`themes/<slug>/\` source were touched. Nothing to validate."
  exit 0
fi

shopt -s nullglob
frags=("${FRAGMENTS_DIR}"/*.md)

if [[ ${#frags[@]} -eq 0 ]]; then
  echo "Package changes were detected, but no result was produced for any of them — check the workflow run for a job-level failure."
  exit 0
fi

while IFS= read -r f; do
  cat "${f}"
  echo
done < <(printf '%s\n' "${frags[@]}" | sort)
