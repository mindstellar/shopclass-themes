# Contributing a theme

> [!IMPORTANT]
> **This registry is not yet accepting submissions.** Everything below describes the
> intended workflow. The piece that actually gates a submission — automated PR
> validation — is not built, so a PR opened today has no CI to check it and will not be
> merged. This document will drop the notice once validation ships.

The full package contract — header fields, versioning, artwork, security requirements — is
specified in `docs/PACKAGE-SPEC.md` in the
[mindstellar/shopclass](https://github.com/mindstellar/shopclass) repository. That document is
authoritative; nothing here restates its rules, only how to act on them in this registry.

## Which path is yours?

**If your theme has its own repository — use external registration.** This is the normal
path. `bender` and `storefront` both work this way; see `external/bender.json` and
`external/storefront.json` for real examples.

**If it doesn't — host it in this repository instead**, under `themes/<slug>/`. Reach for
this only when your theme genuinely has no home of its own; see
[`themes/README.md`](themes/README.md).

---

## Path 1: External registration

Your theme keeps living, and releasing, in your own repository. This registry holds one file
that points at it.

### 1. Cut a real GitHub release

Tag a release and attach a zip **built for distribution**, not GitHub's auto-generated
"Download ZIP" / source-archive asset — that produces a directory named
`<repo>-<ref>/`, which is the wrong shape. Build and attach your own zip whose single
top-level directory is your theme's slug (PACKAGE-SPEC §2), named `<slug>_<version>.zip`,
e.g. `storefront_1.0.2.zip`.

### 2. Add `external/<slug>.json`

Open a pull request adding one file. Shape and required fields are in
[`schema/external.schema.json`](schema/external.schema.json); `slug` must match the filename.
The `source.repo` is your `owner/name`, and `asset_pattern` is a regex matched against your
release asset names — write it to keep matching future releases, not just your current one
(`^storefront_.*\.zip$`, not a pattern pinned to `1.0.2`).

```jsonc
{
  "$schema": "../schema/external.schema.json",
  "slug": "your-theme",
  "type": "theme",
  "source": { "kind": "github-release", "repo": "you/your-theme" },
  "asset_pattern": "^your-theme_.*\\.zip$",
  "categories": ["general"],
  "short_description": "One line, from schema/categories.json's vocabulary."
}
```

### 3. What happens after that

The catalog builder (once it exists — see the root README's status table) resolves your
registration by fetching your repository's releases, picking the asset matching
`asset_pattern`, downloading it, and reading the theme's real `index.php` header **out of
that zip** — never from anything you type into the JSON file. Name, version, and
compatibility come from the artifact a site would actually install, so the catalog cannot
drift from reality. It runs on a schedule, so a new release of your theme needs no further
action here once you're registered.

---

## Path 2: In-repo hosting

Fork this repository and add `themes/<slug>/` with the files PACKAGE-SPEC §1 and §6 require —
`index.php`, `shopclass.json` (validating against
[`schema/theme.schema.json`](schema/theme.schema.json)), `screenshot.png` at the package
root, `LICENSE`, and a `README.md`/`CHANGELOG.md`. Open a pull request. Once PR validation
exists, it runs the structure/manifest/header/compatibility/security/smoke-install gates
described in `docs/MARKET.md` §6 against your package directory; until then, see the notice
at the top of this document.

---

## Running the validator locally

`package-lint.php` is the same validator the registry's CI will run — it lives in core, not here,
so there is exactly one implementation of the contract. From Shopclass 6.1.0 onward it is attached
to each release along with the one companion file it needs, `Compatibility.php`; download both into
one directory and it finds them itself:

```bash
CORE_VERSION=6.1.0
BASE="https://github.com/mindstellar/shopclass/releases/download/${CORE_VERSION}"

curl -fsSL -O "${BASE}/package-lint.php"
curl -fsSL -O "${BASE}/Compatibility.php"

php package-lint.php --type=theme --core=${CORE_VERSION} /path/to/your/theme
```

Against an earlier core, clone the repository and run `tools/package-lint.php` from inside the
checkout instead. Add `--json` for machine-readable output. Exit code `0`
means no errors; warnings never fail the build.

## Code of conduct

Participation in this repository is governed by [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
