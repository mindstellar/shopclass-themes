# shopclass-themes

The theme registry for [Shopclass](https://github.com/mindstellar/shopclass) — the catalog
a Shopclass site browses, installs, and updates themes from, with GitHub itself as the
backend. No market server, no accounts, no database anywhere but the site's own.

> [!IMPORTANT]
> **This registry is not yet accepting submissions.** The catalog build (`catalog.yml`) exists and
> publishes for real once core ships `package-ci/build-catalog.php` (`docs/MARKET.md` §7 in the core
> repository) — until then, a catalog build run is a visible, deliberate no-op rather than a
> failure. This repo has no in-repo release workflow (nothing here needs one yet — see "Currently
> registered" below); a new release of `bender` or `storefront` in its own repository is picked up
> by the catalog's daily schedule. What's still missing is the other half: no core release yet reads
> the catalog (`docs/MARKET.md` Phase 5), so even a published catalog entry cannot be discovered or
> installed by a site today. The most useful contribution today is an issue rather than a pull
> request — see `.github/ISSUE_TEMPLATE/`.

## Two ways a theme gets here

Most Shopclass themes already live in their own repository with their own release cadence —
`bender` and `storefront` both do. For a theme like that, **registration is the normal
path**: one small JSON file here that points at the theme's real home, not a copy of its
source.

1. **External registration** (the default). The theme stays in the author's own repository.
   `external/<slug>.json` records where to find it — a GitHub repo and a pattern matching its
   release asset. A scheduled job resolves that into a catalog entry by reading the theme's
   real header block out of the released zip, so the catalog can never drift from what a site
   actually installs. See [CONTRIBUTING.md](CONTRIBUTING.md).

2. **In-repo hosting** (the exception). For a theme with no home of its own, the full package
   lives here under `themes/<slug>/` instead, and this repository is what builds and releases
   it. Reach for this only when option 1 genuinely isn't available.

Both paths produce an identical catalog entry — a Shopclass install cannot tell which one a
theme took.

## Currently registered

| Theme | Hosting | Latest | Role |
|---|---|---|---|
| [`bender`](external/bender.json) | External — [mindstellar/theme-bender](https://github.com/mindstellar/theme-bender) | v3.3.0 | Legacy default theme, superseded by Storefront in Shopclass 6.0.0. Still maintained for existing installs. |
| [`storefront`](external/storefront.json) | External — [mindstellar/theme-storefront](https://github.com/mindstellar/theme-storefront) | v1.0.2 | Bundled default theme since Shopclass 6.0.0. |

## The catalog

Once the release and catalog build pipeline lands, this registry publishes a static, versioned
catalog that core reads directly — no per-package API calls, one conditional GET per day:

| File | Purpose |
|---|---|
| `v1/updates.json` | Every registered theme, every released version, with its compatibility fields — what an install's update check polls |
| `v1/index.json` | Slim browse list — slug, name, short description, author, latest version, icon, categories, tags |
| `v1/packages/<slug>.json` | Full detail — rendered README, screenshots, per-version changelog, links |
| `v1/categories.json` | The category vocabulary in [`schema/categories.json`](schema/categories.json), with counts |

Published to GitHub Pages from a `catalog` branch, at
`https://mindstellar.github.io/shopclass-themes/v1/…`, mirrored at
`https://raw.githubusercontent.com/mindstellar/shopclass-themes/catalog/v1/…` for when Pages
is unreachable. `catalog.yml` runs (on release, daily, and on demand) but has nothing to build
against until core publishes `package-ci/build-catalog.php` — until then the `catalog` branch
does not exist, and a run skips visibly rather than publishing an empty or fabricated catalog.
Both URLs go live from the first run that actually builds something.

## What's real today and what's planned

| Piece | Status |
|---|---|
| Schemas (`schema/*.schema.json`), category vocabulary | Real — validated in this repo |
| `external/bender.json`, `external/storefront.json` | Real registrations |
| `CONTRIBUTING.md` walkthrough, `tools/package-lint.php` (in core) | Real — you can run it today |
| PR validation — external registrations (`.github/workflows/pr-validate.yml`): schema, reachability, release/asset resolution, package-lint against the downloaded artifact | Real |
| PR validation — in-repo themes: schema, package-lint, `php -l`, deprecated-API scan | Real, minus the smoke-install gate (not built) |
| Release build (`release.yml`) — zip, tag, GitHub Release per package | Not applicable yet — no in-repo theme exists to release; see below |
| Catalog build (`catalog.yml`) and the `catalog` branch / Pages deploy | Built. Runs on release, daily, and on demand; publishes once core ships `package-ci/build-catalog.php`, skips visibly until then |
| Core catalog client (`Catalog`, browse/install UI) | Not built |

### What happens when an in-repo theme is added

Every theme registered here today is external, so there is nothing for a release workflow to
build yet — `release.yml` does not exist in this repository. The moment a theme is hosted
in-repo under `themes/<slug>/` (Path 2 in [CONTRIBUTING.md](CONTRIBUTING.md)), it needs the
release workflow the plugin registry already runs: detect a `Version:` header change on push to
`main`, build `<slug>_<version>.zip` honouring `.distignore` with a single top-level directory
named for the slug, tag and publish a GitHub Release from it, then trigger `catalog.yml`. That
must be [shopclass-plugins' `release.yml`](https://github.com/mindstellar/shopclass-plugins/blob/main/.github/workflows/release.yml)
and its `tools/detect-version-changes.sh` / `tools/build-release-zip.sh` /
`tools/changelog-section.sh`, copied here unchanged rather than a second implementation of the
same job — the discipline `catalog.yml` already follows in both repos.

The system design and full phasing live in `docs/MARKET.md` in the
[mindstellar/shopclass](https://github.com/mindstellar/shopclass) repository; the package
contract this registry validates against is `docs/PACKAGE-SPEC.md` there.

## License

[GPL-3.0-or-later](LICENSE). See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community
expectations.
