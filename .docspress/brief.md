# Documentation brief — linchpin/actions

The contract `generate-docs-from-source` reads before regenerating `docs/`. The
repository decides the facts; this file decides the scope and the checks.

## Audience

1. Linchpin engineers wiring a client site or plugin repository to the shared
   workflows (`uses: linchpin/actions/.github/workflows/<name>.yml@v4`).
2. Whoever operates nightly maintenance (Sisyphus, rolling maintenance,
   snapshots) and needs to know what a run did and why it stopped.
3. Maintainers of this repository.

## Shape

**Catalog.** The units are the reusable workflows in `.github/workflows/` that
declare `on: workflow_call`, the composite actions in `actions/*/action.yml`,
and the scripts in `bin/`. Around them sit operator guides for the flows that
span several units: deploys, PR checks, rolling maintenance, the monthly
window, merge resolution, QA.

## Publication

`sync-docs.yml` publishes `docs/` to docs.linchpin.com under the `actions`
root, which this repository owns whole (`root-slug` and `managed-path` are both
`actions`). Pages therefore sit at the root of `docs/`, not under
`docs/actions/`.

- Pages carry a frontmatter `title:` and no H1; the theme renders the title.
- Source files outside `docs/` are linked by GitHub URL. DocsPress leaves a
  relative link it cannot map to a page untouched, so one to `../actions/…`
  breaks on the site.
- Composite actions live under `docs/composite-actions/`, so their routes do not
  read `/actions/actions/…`.

## Required pages

- `index.md` — what the repository is, and a route for each audience.
- `getting-started/` — calling a shared workflow at `@v4`; every secret and
  variable; choosing a runner.
- `guides/` — one page per flow named in **Shape**.
- `workflows/` — one page per `workflow_call` workflow, plus `composer-bump.yml`
  (dispatched by Linchpin Governing), and an index with a row for each.
- `composite-actions/` — one page per `actions/*/action.yml`, and an index.
- `scripts/` — `bin/convert-repo` and `bin/onboard-site`.
- `renovate-presets.md`, `troubleshooting.md`, `contributing.md`.
- `MIGRATION-v3-to-v4.md` and `REF-AUDIT-2026-06-12.md` stay at their paths;
  `README.md` links the first.

## Non-goals

- No versioned tree. `v4` is the documented contract; `v3` callers get the
  migration guide.
- `ci.yml`, `release.yml` and `sync-docs.yml` are this repository's own
  automation. `contributing.md` describes them; they get no unit page and are
  never shown as callable.
- No prose restating input descriptions the reference block already shows.

## Acceptance checks

1. Every `workflow_call` workflow has a page in `docs/workflows/` and a row in
   `docs/workflows/index.md`.
2. Every `actions/*/action.yml` has a page in `docs/composite-actions/` and a
   row in `docs/composite-actions/index.md`.
3. Every input, secret and output those files declare appears in its unit's
   reference with the source's default and required state.
4. Every `secrets.*` and `vars.*` a shared workflow or action reads is listed
   in `docs/getting-started/secrets-and-variables.md`.
5. Every flag the `bin/` scripts parse appears on that script's page.
6. Every page has a frontmatter `title:`, no H1, and a unique route and title.
7. Every relative link and anchor resolves; `README.md`'s links into `docs/`
   still resolve.
8. Every `wp:docspress/*` block parses, uses only allowed values, and
   round-trips through the converter `sync-docs.yml` pins.
