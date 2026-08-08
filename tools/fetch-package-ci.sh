#!/usr/bin/env bash
# Obtains the shared package-validation toolkit core publishes (docs/MARKET.md
# §6.4 in mindstellar/shopclass: one implementation of the package contract,
# downloaded rather than reimplemented here). Preferred source is the newest
# `mindstellar/shopclass` release carrying a `shopclass-package-ci.tar.gz`
# asset; that asset does not exist in any release yet, so the fallback below
# — a shallow clone of core, assembled into the same layout — is what
# actually runs today. The same bundle also carries build-catalog.php
# (docs/MARKET.md §7), consumed by catalog.yml rather than pr-validate.yml;
# it isn't published yet either, so it follows the same missing-and-visible
# path as the four gates above it.
#
# Usage: tools/fetch-package-ci.sh [--out=DIR] [--core-repo=owner/name|path] [--ref=REF]
#
# The flags mirror the plugin registry's fetcher of the same name so the two
# registries are driven identically. Env overrides remain supported:
#   SHOPCLASS_CORE_REPO        owner/name (default mindstellar/shopclass)
#   SHOPCLASS_CORE_GIT_URL     git remote for the fallback clone
#   SHOPCLASS_CORE_REF         git ref for the fallback clone
#   SHOPCLASS_CORE_LOCAL_PATH  skip network, assemble from an existing checkout
#   GITHUB_TOKEN                raises the GitHub API rate limit; never required
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=tools/lib.sh
source "${SCRIPT_DIR}/lib.sh"

OUT_DIR="package-ci"
CORE_REPO="${SHOPCLASS_CORE_REPO:-mindstellar/shopclass}"
ASSET_NAME="shopclass-package-ci.tar.gz"

for arg in "$@"; do
  case "${arg}" in
    --out=*) OUT_DIR="${arg#--out=}" ;;
    --core-repo=*) CORE_REPO="${arg#--core-repo=}" ;;
    --ref=*) SHOPCLASS_CORE_REF="${arg#--ref=}" ;;
    -h | --help)
      sed -n '1,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: ${arg}" >&2
      echo "Usage: $0 [--out=DIR] [--core-repo=owner/name|path] [--ref=REF]" >&2
      exit 2
      ;;
  esac
done

# OUT_DIR is handed to `rm -rf`, so an unintended value is destructive. Keep it a
# plain relative path under the working tree — never absolute, never a traversal.
case "${OUT_DIR}" in
  '' | /* | *..*)
    echo "Refusing --out=${OUT_DIR}: must be a relative path inside the repository." >&2
    exit 2
    ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

resolve_latest_core_version() {
  local body rc=0
  body="$(gh_api "https://api.github.com/repos/${CORE_REPO}/releases?per_page=20")" || rc=$?
  if [[ ${rc} -ne 0 ]]; then
    return 1
  fi
  printf '%s' "${body}" | jq -r '[.[] | select(.draft == false)][0].tag_name // empty'
}

# Preferred path: a release asset. Returns 1 (not a hard error) on anything
# short of a clean download, so main() falls through to the clone.
try_release_asset() {
  log_info "Checking ${CORE_REPO} releases for a '${ASSET_NAME}' asset..."
  local body rc=0
  body="$(gh_api "https://api.github.com/repos/${CORE_REPO}/releases?per_page=20")" || rc=$?
  case "${rc}" in
    0) ;;
    44) log_warn "No releases found for ${CORE_REPO} — falling back to a source clone." ; return 1 ;;
    75) log_warn "GitHub API unreachable/rate-limited after retries — falling back to a source clone." ; return 1 ;;
    *) log_warn "Unexpected error listing ${CORE_REPO} releases (exit ${rc}) — falling back to a source clone." ; return 1 ;;
  esac

  local asset_url
  asset_url="$(printf '%s' "${body}" | jq -r --arg name "${ASSET_NAME}" '
    map(select(.draft == false))
    | map(select(((.assets // []) | map(.name) | index($name)) != null))
    | .[0].assets[]?
    | select(.name == $name)
    | .browser_download_url
  ')"

  if [[ -z "${asset_url}" || "${asset_url}" == "null" ]]; then
    log_info "No release of ${CORE_REPO} carries '${ASSET_NAME}' yet."
    return 1
  fi

  log_info "Found ${ASSET_NAME}: ${asset_url}"
  if ! curl -fsSL --max-time 60 --retry 4 --retry-delay 2 --retry-all-errors -o "${WORK}/package-ci.tar.gz" "${asset_url}"; then
    log_warn "Download of ${asset_url} failed — falling back to a source clone."
    return 1
  fi

  local extract="${WORK}/extract"
  mkdir -p "${extract}"
  tar -xzf "${WORK}/package-ci.tar.gz" -C "${extract}"

  rm -rf -- "${OUT_DIR}"
  if [[ -d "${extract}/package-ci" ]]; then
    mv "${extract}/package-ci" "${OUT_DIR}"
  else
    mv "${extract}" "${OUT_DIR}"
  fi
  log_info "package-ci/ assembled from the release asset."
  return 0
}

# Fallback: shallow-clone core (or use a local checkout) and assemble the
# same layout by hand from the pieces that exist today.
fallback_clone() {
  log_info "Assembling package-ci/ from a source checkout of ${CORE_REPO} (fallback path)."

  local src
  if [[ -n "${SHOPCLASS_CORE_LOCAL_PATH:-}" ]]; then
    src="${SHOPCLASS_CORE_LOCAL_PATH}"
    log_info "Using local core checkout at ${src} (SHOPCLASS_CORE_LOCAL_PATH set)."
  else
    src="${WORK}/core"
    local git_url="${SHOPCLASS_CORE_GIT_URL:-https://github.com/${CORE_REPO}.git}"
    local clone_args=(--quiet --depth 1)
    [[ -n "${SHOPCLASS_CORE_REF:-}" ]] && clone_args+=(--branch "${SHOPCLASS_CORE_REF}")
    log_info "Cloning ${git_url} (depth 1)..."
    if ! git clone "${clone_args[@]}" "${git_url}" "${src}"; then
      log_err "Could not clone ${git_url} — no path to core succeeded."
      return 1
    fi
  fi

  mkdir -p "${OUT_DIR}"
  local out_abs
  out_abs="$(cd "${OUT_DIR}" && pwd)"
  local missing=()

  if [[ -f "${src}/tools/package-lint.php" ]]; then
    cp "${src}/tools/package-lint.php" "${OUT_DIR}/"
  else
    missing+=("package-lint.php")
  fi

  if [[ -f "${src}/oc-includes/osclass/classes/market/Compatibility.php" ]]; then
    cp "${src}/oc-includes/osclass/classes/market/Compatibility.php" "${OUT_DIR}/"
  else
    missing+=("Compatibility.php")
  fi

  if [[ -f "${src}/scripts/gen-deprecated-api.mjs" ]]; then
    if command -v node >/dev/null 2>&1; then
      log_info "Generating deprecated-api.json..."
      if ! (cd "${src}" && node scripts/gen-deprecated-api.mjs --out="${out_abs}/deprecated-api.json"); then
        log_warn "gen-deprecated-api.mjs failed — deprecation warnings unavailable this run."
        missing+=("deprecated-api.json")
      fi
    else
      log_warn "node not found — cannot generate deprecated-api.json."
      missing+=("deprecated-api.json")
    fi
  else
    missing+=("scripts/gen-deprecated-api.mjs")
  fi

  # These are expected to live under core's tools/ci/ once that harness ships;
  # every consumer of package-ci/ must treat them as optional until it does.
  # build-catalog.php (docs/MARKET.md §7) is consumed by catalog.yml, not by
  # pr-validate.yml, but it ships in the same tools/ci/ and the same bundle,
  # so it is fetched here rather than by a second fetcher.
  for rel in tools/ci/deprecation-scan.php tools/ci/annotate.php tools/ci/smoke-install.sh tools/ci/build-catalog.php; do
    local base
    base="$(basename "${rel}")"
    if [[ -f "${src}/${rel}" ]]; then
      cp "${src}/${rel}" "${OUT_DIR}/${base}"
    else
      missing+=("${base}")
    fi
  done
  if [[ -d "${src}/tools/ci/deprecation-collector" ]]; then
    cp -r "${src}/tools/ci/deprecation-collector" "${OUT_DIR}/deprecation-collector"
  else
    missing+=("deprecation-collector/")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%s\n' "${missing[@]}" >"${OUT_DIR}/MISSING.txt"
    log_warn "package-ci/ assembled with gaps (not released by core yet): ${missing[*]}"
    log_warn "Anything missing is skipped downstream with a visible notice — it never fails a run."
  else
    log_info "package-ci/ assembled with the full fallback set."
  fi

  return 0
}

main() {
  rm -rf -- "${OUT_DIR}"

  if ! try_release_asset; then
    if ! fallback_clone; then
      log_err "fetch-package-ci.sh: both the release-asset path and the fallback clone failed."
      exit 1
    fi
  fi

  # The version findings are compared against is always the newest *released*
  # core, resolved fresh — a release asset predates its own successor, and a
  # fallback clone's HEAD can be ahead of the newest release (e.g. a beta).
  local core_version
  core_version="$(resolve_latest_core_version || true)"
  if [[ -z "${core_version}" && -n "${SHOPCLASS_CORE_LOCAL_PATH:-}" ]]; then
    core_version="$(grep -oP "(?<=define\('OSCLASS_VERSION', ')[^']+" \
      "${SHOPCLASS_CORE_LOCAL_PATH}/oc-includes/osclass/default-constants.php" 2>/dev/null || true)"
    [[ -n "${core_version}" ]] && log_warn "Could not resolve a released core version from the GitHub API; using the local checkout's OSCLASS_VERSION (${core_version}) instead."
  fi
  if [[ -z "${core_version}" ]]; then
    log_err "Could not determine a core version to validate against."
    exit 1
  fi
  printf '%s\n' "${core_version}" >"${OUT_DIR}/CORE_VERSION"

  log_info "package-ci/ ready:"
  ls -la "${OUT_DIR}" >&2
  log_info "Core version for compatibility checks: ${core_version}"
}

main
