<!--
Automated validation runs on this PR and checks whether the registration/theme works. A
maintainer separately reviews whether it belongs in the registry (scope, duplication,
maintenance, accuracy) — see CONTRIBUTING.md.
-->

### What is this?

- [ ] External registration (`external/<slug>.json`, pointing at my own repository)
- [ ] In-repo theme (`themes/<slug>/`)

---

## External registration checklist

- [ ] My theme has a real GitHub release, tagged, with a distribution zip attached — **not**
      GitHub's auto-generated "Download ZIP" source archive.
- [ ] The release asset's single top-level directory is my theme's slug (PACKAGE-SPEC §2).
- [ ] `external/<slug>.json` validates against `schema/external.schema.json`; `slug` matches
      the filename.
- [ ] `asset_pattern` matches my actual asset name and will keep matching future releases
      (not pinned to the current version).
- [ ] `categories` are drawn from `schema/categories.json` and actually describe the theme.
- [ ] My `index.php` header block declares `Theme Name`, `Description`, `Version`, `Author`
      (PACKAGE-SPEC §3.3).

## In-repo theme checklist

- [ ] `themes/<slug>/` — directory name matches `^[a-z0-9][a-z0-9-]{1,40}$`.
- [ ] `index.php`, `LICENSE`, `screenshot.png` (at the package root, ≥ 1200×900) are present.
- [ ] `shopclass.json` validates against `schema/theme.schema.json`; `slug` matches the
      directory name.
- [ ] I ran `tools/package-lint.php` locally (see CONTRIBUTING.md) and it reports no errors.
- [ ] No `.git`, `node_modules`, symlinks, or binaries outside images/fonts.

---

### Summary

<!-- What the theme is, and a link to its repository if externally registered. -->
