# Migrating from v3 to v4

v4 is a ground-up rework of the shared build/deploy workflows focused on three
things: **build once and deploy from the release asset**, **working caches**,
and **fewer billed jobs**. It also fixes several latent v3 bugs found while
auditing real runs on `linchpin/linchpin.com`.

Measured baseline that motivated v4 (linchpin.com production deploy, run
`27284587549`): ~8 minutes wall clock, ~14 billable minutes across 9 jobs —
*after* create-release had already spent another ~8–10 billable minutes
building the same code. Expected v4 cost for the same release: one build at
release-cut (~5 billable minutes) plus a 1-job asset deploy (~2–3 billable
minutes).

## Workflow mapping

| v3 | v4 | Notes |
| --- | --- | --- |
| `build.yml` (5 jobs) | `build.yml` (1 job) | Single `release` artifact; optional `release_tag` input attaches `release.zip` to a GitHub release |
| `create-release.yml` (4 jobs) | `create-release.yml` (thin wrapper around `build.yml`) | The attached `release.zip` is now actually deployable (see "v3 bugs fixed") |
| `deploy.yml` (up to 9 jobs) | `deploy.yml` (2 jobs; 1 when `release_tag` is set) | Preflight/Complete bookkeeping became `gh api` steps; deploy-time lint removed |
| `deploy-pressable.yml` + `deploy-pressable-continue.yml` + `deploy-pressable-webhook.yml` | `actions/deploy-pressable` composite action | Entrypoint script ships inside the action (no runtime wget); health check gates success |
| `phplint.yml` + `phpcs.yml` + `phpcbf.yml` | `lint.yml` (1 job) | One cached Composer install; phpcs annotates changed files via cs2pr; phpcbf is a local pre-commit concern now |
| `update-readme.yml` | `update-readme.yml` + `actions/update-readme` composite | Script bundled; callers should gate on composer.lock changes |
| `ymllint.yml` | `ci.yml` | Adds actionlint + zizmor, runs on PRs |
| `deploy-wpengine.yml`, `deploy-cloudways.yml` | **not ported yet** | Stay on `@v3` for those hosts until ported |
| n/a | `actions/setup-wp-php` composite | shivammathur/setup-php + cached Composer + `COMPOSER_AUTH` env (no auth.json on disk) |
| n/a | `actions/build-release` composite | Bundled cleanup.sh + default.distignore |
| n/a | Rollback support | Dispatch `deploy.yml` with a previous `release_tag` — pure transport, no rebuild |

## v3 bugs fixed by v4

These were found auditing v3 against real runs — documented here so the "why"
survives the rewrite:

1. **Inverted cache condition** — `build.yml` gated the Composer cache on
   `inputs.skip_cache == 'true'`; no caller ever set `skip_cache`, so the
   cache never restored. v4 caches unconditionally (keyed on composer.lock).
2. **Docker Composer with no effective cache** — `php-actions/composer@v6`
   pulled a Docker image every run and used its own internal cache dir, so the
   `/tmp/composer-cache` cache step (where it ran at all) cached an empty
   directory. v4 uses the runner's preinstalled PHP via shivammathur/setup-php.
3. **npm cache wired to nothing** — build jobs computed an `npm-cache-dir`
   output that no step consumed, and setup-node ran without `cache: npm`.
   v4 uses setup-node's built-in cache plus `npm ci`.
4. **PHP > 8.3 skipped lint silently** — `phplint.yml` hardcoded one step per
   PHP version (8.0–8.3); projects on 8.4+ (linchpin.com targets 8.5) ran *no*
   lint and reported green, including the "Lint Release" gate before every
   production deploy. v4 uses the project's version-agnostic
   php-parallel-lint.
5. **create-release's plugin builds never ran** — the plugin matrix job
   checked `hashFiles('plugins/${{ matrix.theme }}/package-lock.json')`
   (theme, not plugin), which is empty in the plugin matrix, so plugin npm
   builds skipped. Themes also installed with `composer update` instead of the
   lock file.
6. **The attached release.zip was not deployable** — v3 zipped a `build/`
   wrapper folder; the Pressable entrypoint expects `themes/` and `plugins/`
   at the zip root. Combined with (5), the release asset could never be used
   for deploys — which is why every deploy rebuilt from scratch.
7. **Secrets written to disk** — Packagist credentials were written to
   `auth.json` and excluded from artifacts by convention (one v3 artifact
   upload forgot the exclusion pattern entirely). v4 passes `COMPOSER_AUTH`
   as an environment variable.
8. **Runtime wget of scripts from a branch** — cleanup.sh, the Pressable
   entrypoint and update-readme.sh were fetched from the v3 *branch* at run
   time, so a pinned caller still executed unpinned code. v4 bundles all
   scripts inside composite actions (`github.action_path`).

## Behavioral changes (intentional)

- **Deploy-time lint is gone.** Code reaching a deploy already passed lint on
  the PR, and a published release tag is immutable. The `skip_lint` input no
  longer exists — remove it from callers. PR linting moves to `lint.yml`.
- **Maintenance mode is opt-in** (`maintenance_mode: false` by default). The
  per-theme/per-plugin rsync is brief; most deploys don't need a window.
  v3 always enabled it. Set `maintenance_mode: true` for risky releases.
- **`do_backup` no longer pauses the pipeline.** v3 set the deployment to
  `queued` and waited for an external system (Mantle) to re-trigger a
  "continue" workflow via `workflow_dispatch`. v4 fires the Pressable
  on-demand backup and proceeds. The webhook/continue workflows are removed.
  ⚠️ If any project still relies on the Mantle continue flow, it must stay on
  v3 until this is revisited.
- **Success means the site responds.** The deploy job now health-checks
  `vars.SITE_URL` (any HTTP status < 500 passes, so auth walls and redirects
  are fine) before marking the GitHub deployment successful. Disable with
  `health_check: false`.
- **Deployment statuses use `inputs.environment`** instead of
  `vars.ENVIRONMENT` (which several environments never defined — v3 sent
  empty strings on production status calls).
- **Concurrency replaces "Cancel Existing Deployment".** v3's preflight
  mutated older GitHub deployments via the API. v4 serializes deploys per
  environment with a job-level `concurrency` group instead. Callers should
  also add workflow-level groups (see below).
- **`create-release` no longer creates the GitHub release or changelog.**
  That is release-please's job; v4 only builds and attaches the asset.
- **phpcbf is no longer run in CI.** Run `composer fixcs` locally (ideally in
  a pre-commit hook via husky/lint-staged). The v3 flow — CI bot opening an
  "Auto Fix Formatting" PR that itself triggers more CI — was one of the most
  expensive per-PR items.

## Caller migration (example: linchpin/linchpin.com)

### PR checks — replace `phplint.yml` + `phpcs.yml` with one `ci.yml`

```yaml
name: CI
on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - "**.php"
      - "composer.lock"
      - "phpcs.xml"
      - "phpstan/**"

concurrency:
  group: ci-${{ github.head_ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  lint:
    if: ${{ !startsWith(github.head_ref, 'release-please--') && !endsWith(github.head_ref, '-phpcbf') }}
    uses: linchpin/actions/.github/workflows/lint.yml@v4
    secrets:
      PACKAGIST_COMPOSER_AUTH_JSON: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}
    with:
      run_phpstan: true
```

### Production deploy — deploy the release asset, don't rebuild

```yaml
name: Deploy to Production
on:
  release:
    types: [published]

concurrency:
  group: deploy-production
  cancel-in-progress: false

permissions:
  contents: read
  deployments: write

jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: production
      release_tag: ${{ github.event.release.tag_name }}
```

### release-please — pass the tag so the asset gets attached

```yaml
  create-release:
    needs: release-please
    if: ${{ needs.release-please.outputs.release_created }}
    uses: linchpin/actions/.github/workflows/create-release.yml@v4
    secrets: inherit
    with:
      release_tag: ${{ needs.release-please.outputs.tag_name }}
```

(The release-please job must expose `tag_name` in its outputs.)

### Rollback — new capability

```yaml
name: Rollback
on:
  workflow_dispatch:
    inputs:
      release_tag:
        description: "Release tag to redeploy (e.g. v0.1.54)"
        required: true
      environment:
        type: choice
        options: [staging, production]
        default: staging

jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: ${{ inputs.environment }}
      release_tag: ${{ inputs.release_tag }}
```

### Remove

- `deploy-production-continue.yml` (the Mantle continue flow is gone in v4)
- `skip_lint`, `do_backup: false` inputs from deploy callers (both are
  defaults now; `skip_lint` no longer exists)

## Secrets and variables contract

Unchanged from v3 — same names, same levels:

- Secrets: `PACKAGIST_COMPOSER_AUTH_JSON`, `PRESSABLE_API_CLIENT_ID`,
  `PRESSABLE_API_CLIENT_SECRET`, `SSH_HOST`, `SSH_USER`, `SSH_KEY`,
  `GH_BOT_TOKEN` (update-readme only)
- Repo vars: `HOST`, `PHP_VERSION`, `NODE_VERSION`, `THEMES`, `PLUGINS`,
  `THEME_USES_COMPOSER`, `PLUGIN_USES_COMPOSER`, `REMOTE_PLUGIN_INSTALL`
- Environment vars: `SITE_ID`, `SITE_URL`, `BRANCH`

v4 reusable workflows declare their secrets explicitly (documenting the
contract); `secrets: inherit` from callers still works. `vars.ENVIRONMENT`
is no longer read. `SATISPRESS_USER`/`SATISPRESS_PASSWORD` are only used by
the not-yet-ported remote-plugin-install path.

## Versioning plan for v4

v3 was a moving branch — the last real tag on this repo is `v1.0.2` (2022),
so every client absorbed v3 changes the moment they landed. For v4:

1. The `v4` branch is the development/testing line (callers reference `@v4`
   while linchpin.com validates it).
2. At GA, cut an immutable `v4.0.0` tag via release-please (the manifest
   already exists in this repo) and maintain a moving `v4` major tag, like
   GitHub's own actions.
3. Composite-action self-references inside the reusable workflows
   (`linchpin/actions/actions/*@v4`) are rewritten to the release tag as part
   of the release process.
4. Renovate pins third-party actions to SHAs from then on.

## Not yet ported / open items

- [ ] WP Engine and Cloudways deploy paths (`HOST=wpengine|cloudways` must stay on v3)
- [ ] `REMOTE_PLUGIN_INSTALL=true` flow (`.deployment/remote-plugin-install.sh`)
- [ ] Decide the long-term `do_backup` story (synchronous poll vs. fire-and-proceed vs. Mantle)
- [ ] Make actionlint/zizmor blocking in `ci.yml` and pin actionlint by digest
- [ ] Consider `ubuntu-24.04-arm` runners (~37% cheaper minutes) once v4 is stable
- [ ] Artifact attestations (`actions/attest-build-provenance`) on release.zip
- [ ] Optional per-PR WordPress Playground preview workflow
- [ ] Optional Slack deploy notifications
