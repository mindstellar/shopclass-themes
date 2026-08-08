# shopclass-themes

The theme registry for [Shopclass](https://github.com/mindstellar/shopclass) — the catalog
a Shopclass site browses, installs, and updates themes from, with GitHub itself as the
backend. No market server, no accounts, no database anywhere but the site's own.

> [!IMPORTANT]
> **This registry is not yet accepting submissions.** Pull-request validation runs, but there is no
> catalog and no release automation yet (`docs/MARKET.md` Phases 4 and 7 in the core repository), so
> a merged package still cannot be published or installed by anyone. Validation also expects a
> Shopclass release carrying the shared validator; until one exists, a run builds it from core's
> source instead. The most useful contribution today is an issue rather than a pull request — see
> `.github/ISSUE_TEMPLATE/`.

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
is unreachable. **Neither exists yet** — the `catalog` branch and its build are not built.

## What's real today and what's planned

| Piece | Status |
|---|---|
| Schemas (`schema/*.schema.json`), category vocabulary | Real — validated in this repo |
| `external/bender.json`, `external/storefront.json` | Real registrations |
| `CONTRIBUTING.md` walkthrough, `tools/package-lint.php` (in core) | Real — you can run it today |
| PR validation — external registrations (`.github/workflows/pr-validate.yml`): schema, reachability, release/asset resolution, package-lint against the downloaded artifact | Real |
| PR validation — in-repo themes: schema, package-lint, `php -l`, deprecated-API scan | Real, minus the smoke-install gate (not built) |
| Release build (`release.yml`) — zip, tag, GitHub Release per package | Not built |
| Catalog build (`catalog.yml`) and the `catalog` branch / Pages deploy | Not built |
| Core catalog client (`Catalog`, browse/install UI) | Not built |

The system design and full phasing live in `docs/MARKET.md` in the
[mindstellar/shopclass](https://github.com/mindstellar/shopclass) repository; the package
contract this registry validates against is `docs/PACKAGE-SPEC.md` there.

## License

[GPL-3.0-or-later](LICENSE). See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community
expectations.
