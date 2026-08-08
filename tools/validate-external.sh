#!/usr/bin/env bash
# Validates one external/<slug>.json registration end to end: the manifest
# itself, that it points at something real, and — by downloading the newest
# release asset it names — whether that asset actually satisfies
# PACKAGE-SPEC.md.
#
# Findings are split into two buckets on purpose, not by severity:
#   errors   — wrong with the manifest itself; entirely the registrant's to fix
#              in this PR (bad JSON/schema, slug mismatch, unreachable repo,
#              no releases, an invalid or non-matching asset_pattern).
#   warnings — wrong with the artifact the registered repo currently
#              publishes (missing LICENSE, a package-lint finding, a
#              Version/tag mismatch). A registrant who does not control the
#              upstream repo cannot fix this from inside this PR, so it is
#              surfaced loudly but never blocks the registration — see
#              CONTRIBUTING.md/README.md for the reasoning this encodes.
#
# Usage: tools/validate-external.sh <slug> [package-ci-dir] [out-dir]
# Writes <out-dir>/lint.json ({ok, errors, warnings}, same shape package-lint.php
# uses) and prints a human summary. Exit 0 = no error-level finding.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=tools/lib.sh
source "${SCRIPT_DIR}/lib.sh"

SLUG="${1:?usage: validate-external.sh <slug> [package-ci-dir] [out-dir]}"
PACKAGE_CI_DIR="${2:-package-ci}"
OUT_DIR="${3:-validation-out/external-${SLUG}}"
MANIFEST="external/${SLUG}.json"
SCHEMA="schema/external.schema.json"

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

  printf 'validate-external: %s — %d error(s), %d warning(s)\n' "${SLUG}" "$(jq 'length' <<<"${errors_json}")" "$(jq 'length' <<<"${warnings_json}")"
  if [[ "${errors_json}" != "[]" ]]; then
    echo "Errors (block this registration — fixable in this PR):"
    jq -r '.[] | "  - " + .message' <<<"${errors_json}"
  fi
  if [[ "${warnings_json}" != "[]" ]]; then
    echo "Warnings (informational — do not block):"
    jq -r '.[] | "  - " + .message' <<<"${warnings_json}"
  fi

  [[ "${ok}" == "true" ]] && exit 0
  exit 1
}

if [[ ! -f "${MANIFEST}" ]]; then
  add_error "${MANIFEST} does not exist."
  output_and_exit
fi

if ! jq empty "${MANIFEST}" 2>/tmp/validate-external-jq-err.$$; then
  add_error "${MANIFEST} is not valid JSON: $(cat /tmp/validate-external-jq-err.$$ 2>/dev/null)"
  rm -f /tmp/validate-external-jq-err.$$
  output_and_exit
fi
rm -f /tmp/validate-external-jq-err.$$

schema_json="$(php "${SCRIPT_DIR}/schema-lint.php" "${SCHEMA}" "${MANIFEST}" --json)"
if [[ "$(jq -r '.ok' <<<"${schema_json}")" != "true" ]]; then
  while IFS= read -r e; do add_error "schema: ${e}"; done < <(jq -r '.errors[]' <<<"${schema_json}")
  output_and_exit
fi

data_slug="$(jq -r '.slug' "${MANIFEST}")"
if [[ "${data_slug}" != "${SLUG}" ]]; then
  add_error "slug \"${data_slug}\" does not match filename external/${SLUG}.json"
fi

repo="$(jq -r '.source.repo' "${MANIFEST}")"
if gh_api "https://api.github.com/repos/${repo}" >/dev/null; then
  :
else
  rc=$?
  case "${rc}" in
    44) add_error "source.repo \"${repo}\" does not exist or is not reachable (404)." ;;
    75) add_error "Could not reach the GitHub API to check \"${repo}\" after several retries — this may be transient (rate limit or outage), not a problem with the registration itself. Re-running this check often resolves it." ;;
    *)  add_error "Unexpected error (exit ${rc}) checking \"${repo}\" on GitHub." ;;
  esac
  output_and_exit
fi

pattern="$(jq -r '.asset_pattern' "${MANIFEST}")"
# shellcheck disable=SC2016 # single-quoted on purpose: this is PHP source, not shell
if ! php -r 'exit(@preg_match("#" . $argv[1] . "#", "") === false ? 1 : 0);' "${pattern}"; then
  add_error "asset_pattern \"${pattern}\" is not a valid regular expression."
  output_and_exit
fi

releases_json=""
if releases_json="$(gh_api "https://api.github.com/repos/${repo}/releases?per_page=20")"; then
  :
else
  rc=$?
  case "${rc}" in
    44) add_error "\"${repo}\" has no releases endpoint (unexpected 404)." ;;
    75) add_error "Could not list releases for \"${repo}\" after several retries — this looks transient, not a problem with the registration. Re-running this check often resolves it." ;;
    *)  add_error "Unexpected error (exit ${rc}) listing releases for \"${repo}\"." ;;
  esac
  output_and_exit
fi

newest_release="$(jq -c '[.[] | select(.draft == false)] | .[0] // empty' <<<"${releases_json}")"
if [[ -z "${newest_release}" ]]; then
  add_error "\"${repo}\" has no non-draft releases."
  output_and_exit
fi
tag_name="$(jq -r '.tag_name' <<<"${newest_release}")"

# shellcheck disable=SC2016 # single-quoted on purpose: this is PHP source, not shell
matches="$(jq -r '.assets[].name' <<<"${newest_release}" | php -r '
  $pattern = $argv[1];
  while (($line = fgets(STDIN)) !== false) {
      $line = rtrim($line, "\n");
      if (@preg_match("#" . $pattern . "#", $line)) {
          echo $line . "\n";
      }
  }
' "${pattern}" || true)"

if [[ -z "${matches}" ]]; then
  asset_names="$(jq -r '.assets[].name' <<<"${newest_release}" | paste -sd, - || echo '(no assets)')"
  add_error "asset_pattern \"${pattern}\" matched no asset on the newest release (${tag_name}). Assets on that release: ${asset_names}"
  output_and_exit
fi

match_count="$(printf '%s\n' "${matches}" | grep -c .)"
asset_name="$(printf '%s\n' "${matches}" | sort | head -n1)"
if [[ "${match_count}" -gt 1 ]]; then
  add_warning "asset_pattern matched ${match_count} assets on ${tag_name}; used \"${asset_name}\" (first, alphabetically). Consider a tighter pattern."
fi
asset_url="$(jq -r --arg name "${asset_name}" '.assets[] | select(.name == $name) | .browser_download_url' <<<"${newest_release}")"

# --- Registrant-controlled facts end here. Everything below inspects the
# artifact the upstream repo actually published, and can only ever warn. ---

mkdir -p "${OUT_DIR}/artifact"
if ! curl -fsSL --max-time 120 --retry 3 --retry-delay 2 -o "${OUT_DIR}/asset.zip" "${asset_url}"; then
  add_warning "Could not download ${asset_name} from ${tag_name} to verify it — network issue fetching the release artifact. The registration itself is otherwise valid."
  output_and_exit
fi

if ! unzip -q -o "${OUT_DIR}/asset.zip" -d "${OUT_DIR}/artifact" 2>"${OUT_DIR}/unzip.log"; then
  add_warning "${asset_name} (release ${tag_name}) is not a valid zip file. Registration is otherwise valid; the release itself needs attention upstream."
  output_and_exit
fi

mapfile -t top_entries < <(find "${OUT_DIR}/artifact" -mindepth 1 -maxdepth 1 -printf '%f\n')
if [[ ${#top_entries[@]} -ne 1 || ! -d "${OUT_DIR}/artifact/${top_entries[0]}" ]]; then
  add_warning "${asset_name} (release ${tag_name}) does not extract to a single top-level directory (PACKAGE-SPEC §2). Found: ${top_entries[*]:-<empty>}."
  output_and_exit
fi

top="${top_entries[0]}"
if [[ "${top}" != "${SLUG}" ]]; then
  add_warning "${asset_name}'s top-level directory is \"${top}\", expected \"${SLUG}\" (PACKAGE-SPEC §2)."
fi
PKG_DIR="${OUT_DIR}/artifact/${top}"

for required in index.php screenshot.png LICENSE; do
  if [[ ! -f "${PKG_DIR}/${required}" ]]; then
    add_warning "Release ${tag_name} is missing required file \"${required}\" (PACKAGE-SPEC §1/§2). This is the currently-published release, not something this PR can fix directly."
  fi
done

if [[ -f "${PACKAGE_CI_DIR}/package-lint.php" ]]; then
  core_version="$(cat "${PACKAGE_CI_DIR}/CORE_VERSION" 2>/dev/null || echo "0.0.0")"
  compat_flag=()
  [[ -f "${PACKAGE_CI_DIR}/Compatibility.php" ]] && compat_flag=(--compat="${PACKAGE_CI_DIR}/Compatibility.php")
  lint_json="$(php "${PACKAGE_CI_DIR}/package-lint.php" --type=theme --core="${core_version}" "${compat_flag[@]}" --json "${PKG_DIR}" 2>"${OUT_DIR}/lint-stderr.log" || true)"
  echo "${lint_json}" >"${OUT_DIR}/artifact-lint.json"
  if [[ -n "${lint_json}" ]] && jq empty <<<"${lint_json}" 2>/dev/null; then
    while IFS= read -r e; do
      add_warning "[package-lint, release ${tag_name}] ${e}"
    done < <(jq -r '.errors[].message' <<<"${lint_json}")
    while IFS= read -r w; do
      add_warning "[package-lint, release ${tag_name}] ${w}"
    done < <(jq -r '.warnings[].message' <<<"${lint_json}")
  else
    add_warning "package-lint.php did not produce usable output for ${tag_name} — see ${OUT_DIR}/lint-stderr.log."
  fi
else
  add_warning "package-lint.php was not available in ${PACKAGE_CI_DIR} this run — could not verify release ${tag_name} against PACKAGE-SPEC. See ${PACKAGE_CI_DIR}/MISSING.txt."
fi

if [[ -f "${PKG_DIR}/index.php" ]]; then
  header_version="$(php "${SCRIPT_DIR}/read-header-field.php" "Version" "${PKG_DIR}/index.php" || true)"
  tag_version="${tag_name#v}"
  if [[ -z "${header_version}" ]]; then
    add_warning "index.php in release ${tag_name} declares no Version header."
  elif [[ "${header_version}" != "${tag_version}" ]]; then
    add_warning "index.php Version \"${header_version}\" in release ${tag_name} does not match the release tag (expected \"${tag_version}\")."
  fi
fi

output_and_exit
