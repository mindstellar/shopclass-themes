#!/usr/bin/env bash
# Validates one in-repo theme, themes/<slug>/ — the exception path (README.md,
# themes/README.md): full source lives here, so unlike validate-external.sh
# every finding below is inside this PR's control and every error blocks it,
# matching PACKAGE-SPEC.md §8's "Blocking" list for a monorepo package.
#
# Usage: tools/validate-theme.sh <slug> [package-ci-dir] [out-dir]
# Writes <out-dir>/lint.json ({ok, errors, warnings}). Exit 0 = no error-level
# finding. Deprecation scanning and smoke install run only when package-ci/
# actually has the tool (see fetch-package-ci.sh) — their absence is reported,
# never treated as a failure, per docs/MARKET.md §6.3/§6.5.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=tools/lib.sh
source "${SCRIPT_DIR}/lib.sh"

SLUG="${1:?usage: validate-theme.sh <slug> [package-ci-dir] [out-dir]}"
PACKAGE_CI_DIR="${2:-package-ci}"
OUT_DIR="${3:-validation-out/theme-${SLUG}}"
THEME_DIR="themes/${SLUG}"
SCHEMA="schema/theme.schema.json"

mkdir -p "${OUT_DIR}"
ERR_FILE="$(mktemp)"
WARN_FILE="$(mktemp)"
trap 'rm -f "${ERR_FILE}" "${WARN_FILE}"' EXIT

add_error()   { jq -nc --arg m "$1" '{file:null,line:null,message:$m}' >>"${ERR_FILE}"; }
add_warning() { jq -nc --arg m "$1" '{file:null,line:null,message:$m}' >>"${WARN_FILE}"; }

output_and_exit() {
  local errors_json warnings_json ok=true
  errors_json="$(jq -s -c '.' "${ERR_FILE}")"
  warnings_json="$(jq -s -c '.' "${WARN_FILE}")"
  [[ "${errors_json}" != "[]" ]] && ok=false

  jq -n --argjson ok "${ok}" --argjson errors "${errors_json}" --argjson warnings "${warnings_json}" \
    '{ok:$ok, errors:$errors, warnings:$warnings}' >"${OUT_DIR}/lint.json"

  printf 'validate-theme: %s — %d error(s), %d warning(s)\n' "${SLUG}" "$(jq 'length' <<<"${errors_json}")" "$(jq 'length' <<<"${warnings_json}")"
  if [[ "${errors_json}" != "[]" ]]; then
    echo "Errors:"
    jq -r '.[] | "  - " + .message' <<<"${errors_json}"
  fi
  if [[ "${warnings_json}" != "[]" ]]; then
    echo "Warnings (not blocking):"
    jq -r '.[] | "  - " + .message' <<<"${warnings_json}"
  fi

  [[ "${ok}" == "true" ]] && exit 0
  exit 1
}

if [[ ! -d "${THEME_DIR}" ]]; then
  add_error "${THEME_DIR}/ does not exist."
  output_and_exit
fi

if ! [[ "${SLUG}" =~ ^[a-z0-9][a-z0-9-]{1,40}$ ]]; then
  add_error "\"${SLUG}\" does not match ^[a-z0-9][a-z0-9-]{1,40}\$ (PACKAGE-SPEC §1)."
fi

MANIFEST="${THEME_DIR}/shopclass.json"
if [[ -f "${MANIFEST}" ]]; then
  if jq empty "${MANIFEST}" 2>/dev/null; then
    schema_json="$(php "${SCRIPT_DIR}/schema-lint.php" "${SCHEMA}" "${MANIFEST}" --json)"
    if [[ "$(jq -r '.ok' <<<"${schema_json}")" != "true" ]]; then
      while IFS= read -r e; do add_error "shopclass.json: ${e}"; done < <(jq -r '.errors[]' <<<"${schema_json}")
    fi
    manifest_slug="$(jq -r '.slug // empty' "${MANIFEST}")"
    if [[ -n "${manifest_slug}" && "${manifest_slug}" != "${SLUG}" ]]; then
      add_error "shopclass.json slug \"${manifest_slug}\" does not match directory themes/${SLUG}/"
    fi
  else
    add_error "${MANIFEST} is not valid JSON."
  fi
else
  add_error "${MANIFEST} is missing (required for an in-repo theme, PACKAGE-SPEC §7)."
fi

# package-lint.php owns structure/header/version/security — the same checker
# an external registration's downloaded artifact is run through, so a theme
# hosted here is held to no lower a bar than one hosted elsewhere.
if [[ -f "${PACKAGE_CI_DIR}/package-lint.php" ]]; then
  core_version="$(cat "${PACKAGE_CI_DIR}/CORE_VERSION" 2>/dev/null || echo "0.0.0")"
  compat_flag=()
  [[ -f "${PACKAGE_CI_DIR}/Compatibility.php" ]] && compat_flag=(--compat="${PACKAGE_CI_DIR}/Compatibility.php")
  lint_json="$(php "${PACKAGE_CI_DIR}/package-lint.php" --type=theme --core="${core_version}" "${compat_flag[@]}" --json "${THEME_DIR}" 2>"${OUT_DIR}/lint-stderr.log" || true)"
  echo "${lint_json}" >"${OUT_DIR}/package-lint.json"
  if [[ -n "${lint_json}" ]] && jq empty <<<"${lint_json}" 2>/dev/null; then
    while IFS= read -r e; do add_error "${e}"; done < <(jq -r '.errors[].message' <<<"${lint_json}")
    while IFS= read -r w; do add_warning "${w}"; done < <(jq -r '.warnings[].message' <<<"${lint_json}")
  else
    add_error "package-lint.php produced no usable output — see ${OUT_DIR}/lint-stderr.log."
  fi
else
  add_error "package-lint.php is unavailable in ${PACKAGE_CI_DIR} — cannot validate structure/header/security for an in-repo theme without it. See ${PACKAGE_CI_DIR}/MISSING.txt."
fi

# php -l — a single-version baseline, not the full PHP 8.0-8.5 compatibility
# matrix PACKAGE-SPEC §8 describes; that needs PHPCompatibility tooling this
# harness does not vendor yet, tracked separately from this PR-validation build.
while IFS= read -r -d '' f; do
  if ! out="$(php -l "${f}" 2>&1)"; then
    add_error "php -l: ${out}"
  fi
done < <(find "${THEME_DIR}" -name '*.php' -print0)

# Deprecated-API scan — warn-only, and only when the tool shipped this run.
# Findings are written to deprecation-scan.json and read from there by
# annotate-result.sh (either via package-ci/annotate.php's --deprecations, or
# its own fallback), not folded into lint.json here — that would report the
# same warning twice once annotate.php merges the two files itself.
if [[ -f "${PACKAGE_CI_DIR}/deprecation-scan.php" && -f "${PACKAGE_CI_DIR}/deprecated-api.json" ]]; then
  dep_json="$(php "${PACKAGE_CI_DIR}/deprecation-scan.php" --inventory="${PACKAGE_CI_DIR}/deprecated-api.json" --json "${THEME_DIR}" 2>"${OUT_DIR}/deprecation-stderr.log" || true)"
  echo "${dep_json}" >"${OUT_DIR}/deprecation-scan.json"
else
  add_warning "Deprecated-API scan skipped — deprecation-scan.php and/or deprecated-api.json are not in ${PACKAGE_CI_DIR} this run (never blocking; see ${PACKAGE_CI_DIR}/MISSING.txt if present)."
fi

# Smoke install — boots a real core container and drives the actual admin/
# public HTTP flow (PACKAGE-SPEC §6.5). Blocking, per MARKET.md §6.2 gate 9:
# unlike an external registration's artifact checks, this is this PR's own
# source, so a failure here is squarely this PR's to fix.
smoke_rc=0
run_smoke_install theme "${SLUG}" "${THEME_DIR}" "${OUT_DIR}/smoke.json" "${PACKAGE_CI_DIR}" || smoke_rc=$?
case "${smoke_rc}" in
  0) : ;;
  1)
    while IFS= read -r s; do
      add_error "[smoke install] step \"${s}\" failed"
    done < <(jq -r '.steps[] | select(.ok == false) | .name' "${OUT_DIR}/smoke.json" 2>/dev/null)
    while IFS= read -r f; do
      add_error "[smoke install] ${f}"
    done < <(jq -r '.fatals[]?' "${OUT_DIR}/smoke.json" 2>/dev/null)
    unexpected="$(jq -r '.unexpected_output // empty' "${OUT_DIR}/smoke.json" 2>/dev/null)"
    [[ -n "${unexpected}" ]] && add_error "[smoke install] unexpected output during install: ${unexpected}"
    while IFS= read -r t; do
      add_warning "[smoke install] uninstall left table \`${t}\` behind"
    done < <(jq -r '.tables_left[]?' "${OUT_DIR}/smoke.json" 2>/dev/null)
    while IFS= read -r p; do
      add_warning "[smoke install] uninstall left preference \`${p}\` behind"
    done < <(jq -r '.prefs_left[]?' "${OUT_DIR}/smoke.json" 2>/dev/null)
    ;;
  2)
    add_warning "Smoke install skipped: smoke-install.sh and/or a usable Docker daemon are not available this run. This is a tooling gap, never a finding about the theme."
    ;;
esac

output_and_exit
