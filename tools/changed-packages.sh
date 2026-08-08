#!/usr/bin/env bash
# Maps the files a PR touched to the two things this registry validates
# separately: changed external/<slug>.json registrations and changed
# themes/<slug>/ source trees (docs/MARKET.md §6.1 in mindstellar/shopclass,
# adapted — this repo's dominant PR is a manifest, not source).
#
# Usage: tools/changed-packages.sh <base-ref> [<head-ref>]
# Writes external/themes/any to $GITHUB_OUTPUT when running in Actions,
# otherwise prints the same as a JSON object on stdout.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=tools/lib.sh
source "${SCRIPT_DIR}/lib.sh"

BASE_REF="${1:?usage: changed-packages.sh <base-ref> [<head-ref>]}"
HEAD_REF="${2:-HEAD}"

if ! git rev-parse --verify --quiet "${BASE_REF}" >/dev/null; then
  log_err "Base ref '${BASE_REF}' not found. Checkout needs fetch-depth: 0."
  exit 2
fi

mapfile -t changed_files < <(git diff --name-only "${BASE_REF}...${HEAD_REF}" --)

external_slugs=()
theme_slugs=()

for f in "${changed_files[@]}"; do
  if [[ "${f}" =~ ^external/([a-z0-9][a-z0-9-]{1,40})\.json$ ]]; then
    external_slugs+=("${BASH_REMATCH[1]}")
  elif [[ "${f}" =~ ^themes/([a-z0-9][a-z0-9-]{1,40})/ ]]; then
    theme_slugs+=("${BASH_REMATCH[1]}")
  fi
done

json_array() {
  if [[ $# -eq 0 ]]; then
    printf '[]'
    return
  fi
  printf '%s\n' "$@" | sort -u | jq -R . | jq -s -c .
}

external_json="[]"
themes_json="[]"
[[ ${#external_slugs[@]} -gt 0 ]] && external_json="$(json_array "${external_slugs[@]}")"
[[ ${#theme_slugs[@]} -gt 0 ]] && themes_json="$(json_array "${theme_slugs[@]}")"

any=false
[[ "${external_json}" != "[]" || "${themes_json}" != "[]" ]] && any=true

log_info "Changed external manifests: ${external_json}"
log_info "Changed in-repo themes:     ${themes_json}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "external=${external_json}"
    echo "themes=${themes_json}"
    echo "any=${any}"
  } >>"${GITHUB_OUTPUT}"
else
  jq -n --argjson external "${external_json}" --argjson themes "${themes_json}" --argjson any "${any}" \
    '{external: $external, themes: $themes, any: $any}'
fi
