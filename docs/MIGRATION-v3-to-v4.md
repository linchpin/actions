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
| `deploy.yml` (up to 9 jobs) | `deploy.yml` (2 jobs; 1 when `release_tag` is set) | Preflight/Complete bookkeeping became `gh api` steps; deploy-time lint removed; fans out to pressable/wpengine/cloudways composites by `vars.HOST` |
| `deploy-pressable.yml` | `actions/deploy-pressable` composite action | Entrypoint script ships inside the action (no runtime wget); health check gates success |
| `deploy-pressable-continue.yml` + `deploy-pressable-webhook.yml` | `deploy-continue.yml` | Backup-and-continue flow preserved and actually wired (see below); Mantle contract unchanged |
| `deploy-wpengine.yml` | `actions/deploy-wpengine` composite action | SSH config inlined (drops the `actions-wpengine-ssh@main` moving ref); endpoint.sh folded into the entrypoint |
| `deploy-cloudways.yml` | `actions/deploy-cloudways` composite action | Key and password auth in one code path; maintenance.php ships with the action |
| `phplint.yml` + `phpcs.yml` + `phpcbf.yml` | `lint.yml` (1 job) | One cached Composer install; phpcs annotates changed files via cs2pr; phpcbf is a local pre-commit concern now |
| `update-readme.yml` | `update-readme.yml` + `actions/update-readme` composite | Script bundled; callers should gate on composer.lock changes |
| `ymllint.yml` | `ci.yml` | Adds actionlint + zizmor, runs on PRs |
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
- **The backup-and-continue flow is preserved — and now actually plumbed.**
  With `do_backup: true` (Pressable), `deploy.yml` triggers the on-demand
  backup, registers the deployment with Mantle
  (`POST mantle.linchpin.com/api/v1/deployments/start` with `deployment_id` +
  `workflow_run_id`, same contract as v3), parks the GitHub deployment as
  `queued`, and ends. Mantle dispatches the caller's continue workflow, which
  calls `deploy-continue.yml` to finish from the already-built artifact.
  v4 fixes the v3 gaps that kept this aspirational: the caller's dispatch
  workflow now declares explicit inputs (v3 read `github.event.deployment.id`,
  which a `workflow_dispatch` payload does not carry), and the cross-run
  artifact download now passes `run-id` + `github-token` (plus the
  `actions: read` permission), which v3 omitted — so the continue run can
  genuinely fetch the release built by the original run.
  ⚠️ Mantle must dispatch with
  `{"inputs": {"deployment_id": "...", "workflow_run_id": "..."}}`.
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

# contents: write (NOT read) — even though the asset path skips the build
# job, GitHub validates the whole called-workflow call tree at startup, and
# deploy.yml -> build.yml declares contents: write. A caller granting only
# read fails immediately with "the nested job 'build' is requesting
# 'contents: write', but is only allowed 'contents: read'".
permissions:
  contents: write
  deployments: write

jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: production
      release_tag: ${{ github.event.release.tag_name }}
```

> **Asset/deploy race:** `release: published` fires this deploy at the same
> moment release-please's `create-release` job starts *building* the asset.
> The deploy's download step waits (polls up to ~10 min) for `release.zip` to
> be attached, so the ordering resolves itself — but it does mean the first
> few minutes of a production deploy may show "release.zip not attached yet…"
> while the build runs. That is expected, not an error.

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

### Continue workflow — declare the dispatch inputs

The caller-side continue workflow stays (Mantle dispatches it), but it must
declare its inputs explicitly:

```yaml
name: Continue Deploy to Production
on:
  workflow_dispatch: # Dispatched by Mantle when the Pressable backup completes
    inputs:
      deployment_id:
        description: "GitHub deployment ID from the original deploy run"
        required: true
      workflow_run_id:
        description: "Run ID of the original deploy (source of the release artifact)"
        required: true
      release_tag:
        description: "Set when the original deploy used a release asset"
        required: false
        default: ""

permissions:
  contents: read
  deployments: write
  actions: read

jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy-continue.yml@v4
    secrets: inherit
    with:
      environment: production
      deployment_id: ${{ inputs.deployment_id }}
      workflow_run_id: ${{ inputs.workflow_run_id }}
      release_tag: ${{ inputs.release_tag }}
```

### Remove

- `skip_lint`, `do_backup: false` inputs from deploy callers (both are
  defaults now; `skip_lint` no longer exists)

## Secrets and variables contract

Unchanged from v3 — same names, same levels:

- Secrets: `PACKAGIST_COMPOSER_AUTH_JSON`, `PRESSABLE_API_CLIENT_ID`,
  `PRESSABLE_API_CLIENT_SECRET`, `SSH_HOST`, `SSH_USER`, `SSH_KEY`,
  `SSH_PASS` (Cloudways Autonomous), `MANTLE_API_BEARER` (backup/continue),
  `GH_BOT_TOKEN` (update-readme only)
- Repo vars: `HOST` (pressable|wpengine|cloudways), `PHP_VERSION`,
  `NODE_VERSION`, `THEMES`, `PLUGINS`, `THEME_USES_COMPOSER`,
  `PLUGIN_USES_COMPOSER`, `REMOTE_PLUGIN_INSTALL`,
  `DEPLOYMENT_AUTH_TYPE` (cloudways: key|pass), `INSTALL_NAME` (wpengine)
- Environment vars: `SITE_ID`, `SITE_URL`, `BRANCH`

v4 reusable workflows declare their secrets explicitly (documenting the
contract); `secrets: inherit` from callers still works. `vars.ENVIRONMENT`
is no longer read. `SATISPRESS_USER`/`SATISPRESS_PASSWORD` are only used by
the not-yet-ported remote-plugin-install path.

## Versioning plan for v4

v3 was a moving branch — before this rework the last real tag on this repo
was `v1.0.2` (2022), so every client absorbed v3 changes the moment they
landed. Current state:

- **`v3.0.0` exists** — an immutable snapshot of the `v3` branch tip
  (49d2a98, cut 2026-06-12). The `v3` branch is frozen (bug fixes only);
  teams that want reproducibility today can pin `@v3.0.0`.
- **`release.yml` + release-please are wired** (config bootstrapped at the
  v3/v4 branch point, manifest seeded at 3.0.0). The breaking `feat(v4)!`
  commits make the first release from main `v4.0.0`.
- **Floating major tags** — on every release publish, `release.yml` moves
  the `vN` major tag to the new release, so `@v4` always resolves to the
  latest v4 release, exactly like GitHub's own actions. The composite-action
  self-references (`linchpin/actions/actions/*@v4`) therefore stay correct
  with no rewrite step.

GA sequence after this PR merges into main:

1. Merge the release-please PR it opens → `v4.0.0` is tagged and released.
2. Delete the `v4` development branch (a floating tag cannot coexist with a
   branch of the same name — `release.yml` guards against the ambiguity).
3. Run the Release workflow via workflow_dispatch with `tag=v4.0.0` to create
   the floating `v4` tag. Callers already referencing `@v4` switch from
   branch-resolution to tag-resolution transparently.
4. Renovate pins third-party actions to SHAs from then on.

## Not yet ported / open items

- [ ] Validate the WP Engine and Cloudways composites against a live client
      site before any client repo moves to v4 (ported from v3 logic, with its
      shell bugs fixed, but untested against real installs)
- [ ] Update Mantle to dispatch the continue workflow with explicit
      `inputs: {deployment_id, workflow_run_id}` (v3 dispatched without
      inputs, which could never work)
- [ ] `REMOTE_PLUGIN_INSTALL=true` flow (`.deployment/remote-plugin-install.sh`)
- [ ] WP Engine / Cloudways equivalents for `do_backup` (was already a TODO in v3)
- [ ] Make actionlint/zizmor blocking in `ci.yml` and pin actionlint by digest
- [ ] Consider `ubuntu-24.04-arm` runners (~37% cheaper minutes) once v4 is stable
- [ ] Artifact attestations (`actions/attest-build-provenance`) on release.zip
- [ ] Optional per-PR WordPress Playground preview workflow
- [ ] Optional Slack deploy notifications
