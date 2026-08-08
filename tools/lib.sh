#!/usr/bin/env bash
# Shared helpers for the tools/ scripts: logging, GitHub-annotation output, and a
# GitHub REST API fetcher with retry/backoff so a transient failure never reads
# the same as a real finding.
set -euo pipefail

log_info() { printf '[info] %s\n' "$*" >&2; }
log_warn() { printf '[warn] %s\n' "$*" >&2; }
log_err()  { printf '[error] %s\n' "$*" >&2; }

gh_annotate_error() {
  local file="$1" line="${2:-}" msg="$3"
  if [[ -n "$line" && "$line" != "null" ]]; then
    printf '::error file=%s,line=%s::%s\n' "$file" "$line" "$msg"
  else
    printf '::error file=%s::%s\n' "$file" "$msg"
  fi
}

gh_annotate_warning() {
  local file="$1" line="${2:-}" msg="$3"
  if [[ -n "$line" && "$line" != "null" ]]; then
    printf '::warning file=%s,line=%s::%s\n' "$file" "$line" "$msg"
  else
    printf '::warning file=%s::%s\n' "$file" "$msg"
  fi
}

# gh_api <url> [max_retries] — GET a GitHub API URL with exponential backoff.
# Prints the response body on success. Return codes distinguish *why* it
# failed, so callers can tell a real finding (404) from an infra hiccup:
#   0  success
#   44 definitive 404 (repo/release does not exist)
#   75 exhausted retries on a transient condition (network/5xx/rate limit)
#   1  other definitive client error (4xx other than 404)
gh_api() {
  local url="$1"
  local max_retries="${2:-4}"
  local attempt=0
  local delay=2
  local tmp_body
  tmp_body="$(mktemp)"

  while :; do
    attempt=$((attempt + 1))
    local http_code
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      http_code=$(curl -sS --max-time 30 -o "$tmp_body" -w '%{http_code}' \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        "$url" 2>/dev/null || echo "000")
    else
      http_code=$(curl -sS --max-time 30 -o "$tmp_body" -w '%{http_code}' \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url" 2>/dev/null || echo "000")
    fi

    if [[ "$http_code" == "200" ]]; then
      cat "$tmp_body"
      rm -f "$tmp_body"
      return 0
    fi

    if [[ "$http_code" == "404" ]]; then
      rm -f "$tmp_body"
      return 44
    fi

    if [[ "$http_code" == "403" ]] && grep -qi "rate limit" "$tmp_body" 2>/dev/null; then
      log_warn "GitHub API rate limit hit for $url (attempt ${attempt}/${max_retries})"
    elif [[ "$http_code" =~ ^5 || "$http_code" == "000" ]]; then
      log_warn "Transient error (${http_code}) fetching $url (attempt ${attempt}/${max_retries})"
    else
      log_err "GitHub API returned ${http_code} for $url"
      cat "$tmp_body" >&2
      rm -f "$tmp_body"
      return 1
    fi

    if (( attempt >= max_retries )); then
      log_err "Giving up on $url after ${attempt} attempts (last status ${http_code})." \
        "This looks like a transient GitHub API issue, not a problem with the pull request."
      rm -f "$tmp_body"
      return 75
    fi

    sleep "$delay"
    delay=$(( delay * 2 ))
    (( delay > 30 )) && delay=30
  done
}

# run_smoke_install <type> <slug> <pkg-dir> <out-json> <package-ci-dir>
# Runs package-ci/smoke-install.sh (docs/MARKET.md §6.5) against a real core
# container when both the tool and a working Docker daemon are available.
# Return codes: 0 = ran, clean; 1 = ran, found a problem (see <out-json>);
# 2 = could not run at all (missing tool or no Docker) — never a finding
# about the package itself, callers must not treat this as blocking.
run_smoke_install() {
  local type="$1" slug="$2" pkg_dir="$3" out_json="$4" package_ci_dir="$5"
  local script="${package_ci_dir}/smoke-install.sh"

  [[ -f "${script}" ]] || return 2
  command -v docker >/dev/null 2>&1 || return 2
  docker info >/dev/null 2>&1 || return 2

  local image="${SMOKE_IMAGE:-ghcr.io/mindstellar/shopclass:edge}"
  if timeout 280 bash "${script}" --type="${type}" --slug="${slug}" --path="${pkg_dir}" --image="${image}" --out="${out_json}"; then
    return 0
  fi
  [[ -f "${out_json}" ]] && return 1
  return 2
}
