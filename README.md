# Linchpin Shared Project Configs

An open source collection of Linchpin's configs. Primarily used for [Renovate bot](https://github.com/marketplace/renovate) and shared workflows. While there are some aspects of this repo that are specific to [Linchpin](https://linchpin.com) and our build process, other organizations can take advantage of them if they want to use them.

![license](https://img.shields.io/github/license/linchpin/actions) ![version](https://img.shields.io/badge/version-v4-black)

## Major Differences in v4 of the GitHub Reusable Workflows

v4 is a ground-up rework of the build/deploy pipeline. The full
previous/next story — including the v3 bugs it fixes and the caller migration
steps — lives in **[docs/MIGRATION-v3-to-v4.md](docs/MIGRATION-v3-to-v4.md)**.
The headlines:

- **Release-please publishes; the deploy builds and archives.** release-please
  publishes each GitHub release directly (no draft step). The production deploy
  (`deploy.yml` with `build_for_release`) builds the project, deploys it, and
  attaches the deploy-ready `release.zip` to that release. `deploy.yml` also
  accepts a `release_tag` input that downloads an already-attached asset and
  deploys it without rebuilding — an instant **rollback**: dispatch a deploy
  with a previous tag.
- **One build job instead of five.** Composer, theme and plugin builds run
  serially in one job with working caches (Composer keyed on composer.lock,
  npm via setup-node). The v3 artifact-reshuffle job is gone.
- **Composite actions instead of runtime wget.** Scripts that v3 fetched from
  a branch at run time now ship inside [`actions/`](actions/) composite
  actions (`setup-wp-php`, `build-release`, `deploy-pressable`,
  `update-readme`) — the ref you pin is the code that runs.
- **One PR lint workflow.** `lint.yml` replaces phplint + phpcs + phpcbf with
  a single cached job: syntax lint (any PHP version), phpcs on changed files
  with inline annotations, optional PHPStan.
- **Deploys verify themselves.** A post-deploy health check gates the GitHub
  deployment status; maintenance mode is opt-in; bookkeeping jobs became
  steps.
- **Symlinked folders are left alone.** Plugins a managed host serves from its
  own storage (Pressable links `jetpack` and `woocommerce` into `wp-content`) are
  detected and skipped instead of being rsynced over, and a project can declare
  additional off-limits paths with `PROTECTED_PATHS`. See
  [Symlinked and host-managed folders](#symlinked-and-host-managed-folders).
- **Least-privilege permissions** declared in every workflow, and secrets are
  passed via env (no auth.json on disk).

### Versioning

v3 was a moving branch. v4 will GA as an immutable `v4.0.0` tag with a moving
`v4` major tag (see the migration doc for the plan). Until GA, `@v4`
references the development branch while `linchpin/linchpin.com` validates it.

## GitHub Secrets and Variables

Below is a list of standard secrets and variables used in Linchpin's shared workflows.

### Secrets

To learn more [about secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions) in your workflows please see GitHub's documentation.

| Key                          | Default | Description                                                                             |
| ---------------------------- | ------- | --------------------------------------------------------------------------------------- |
| SSH_KEY                      |         | The SSH key used to interact w/ the remote environment                                  |
| SSH_USER                     |         | The SSH user used to interact w/ the remote environment                                 |
| SSH_PASS                     |         | The SSH pass for environments that cannot support SSH Keys (Cloudways Autonomous)       |
| SSH_HOST                     |         | The SSH IP or Host Name                                                                 |
| PACKAGIST_COMPOSER_AUTH_JSON |         | auth.json contents for packagist.linchpin.com (v4 passes this via the COMPOSER_AUTH env) |
| PRESSABLE_API_CLIENT_ID      |         | Pressable API client (maintenance mode, backups)                                        |
| PRESSABLE_API_CLIENT_SECRET  |         | Pressable API secret                                                                    |
| MANTLE_API_BEARER            |         | Mantle API token used by the backup-and-continue deploy flow                            |
| GH_BOT_TOKEN                 |         | Bot token used by update-readme.yml to open PRs                                         |
| SATISPRESS_USER              |         | Private Packagist auth, used only by the `REMOTE_PLUGIN_INSTALL` reconcile               |
| SATISPRESS_PASSWORD          |         | Private Packagist auth, used only by the `REMOTE_PLUGIN_INSTALL` reconcile               |
| QA_SCHEMA_TOKEN              |         | Reads linchpin/automated-testing so qa-guard.yml can validate against the one QA schema  |
| QA_API_TOKEN                 |         | Per-project bearer token used by qa-run.yml to trigger and read runs on the QA platform   |

### Variables

To learn more [about variables](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables) in your workflows please see GitHub's documentation.

| Key                   | Default | Description                                                                              |
| --------------------- | ------- | ---------------------------------------------------------------------------------------- |
| HOST                  |         | The host of the project, one of `pressable`, `wpengine`, `cloudways`                     |
| SITE_URL              |         | The url of the site including https:// (also used by the v4 post-deploy health check)    |
| SITE_ID               |         | When using **Pressable** this is how we reference a site                                 |
| INSTALL_NAME          |         | Install name when project is hosted on WP Engine                                         |
| DEPLOYMENT_AUTH_TYPE  | key     | Cloudways SSH auth type: `key` or `pass` (Cloudways Autonomous)                          |
| REMOTE_PLUGIN_INSTALL | false   | Install third-party plugins/themes on the server from `composer.lock` via WP-CLI instead of shipping them — see [below](#remote-plugin-install-composer-on-the-server) |
| BRANCH                | staging | The default branch associated with the environment                                       |
| PHP_VERSION           |         | PHP version used for builds and linting (e.g. `8.5`)                                     |
| NODE_VERSION          |         | Node version used for builds (e.g. `24`)                                                 |
| THEMES                |         | A JSON formatted array of themes to build Ex `["linchpin"]`                              |
| PLUGINS               |         | A JSON formatted array of plugins to build Ex `["linchpin-functionality"]`               |
| THEME_USES_COMPOSER   | false   | Do the theme(s) use composer to load dependencies                                        |
| PLUGIN_USES_COMPOSER  | true    | Do the plugin(s) use composer to load dependencies                                       |
| PROTECTED_PATHS       |         | Paths a deploy must never overwrite, relative to `wp-content` — see [below](#symlinked-and-host-managed-folders) |

> v3's `ENVIRONMENT` and `DEPLOYMENT_PATH` variables are no longer read by
> v4 workflows (deployment paths are composite-action inputs with per-host
> defaults).

## Symlinked and host-managed folders

Managed hosts serve some plugins from platform-owned storage and link them into
the site — on Pressable, `jetpack` and `woocommerce` are usually symlinks inside
`wp-content/plugins` rather than real folders. Syncing a release copy onto such a
path is destructive either way: rsync follows the link and writes **through** it
(so `--delete` prunes files the platform owns), or the link is replaced by a real
directory and the site silently stops receiving platform updates.

**v4 deploys detect this and leave it alone.** Before syncing, the server-side
entrypoint scans `wp-content` and skips anything that is a symlink:

- `plugins/` and `themes/` are synced one folder at a time, so a symlinked child
  is skipped whole.
- `mu-plugins/` is synced as a tree, so symlinked entries become rsync
  `--exclude` rules — without that, `--delete` would remove the host's own
  mu-plugins.
- Every symlink found is printed at the top of the sync log with its target, and
  everything skipped is listed again in a closing summary. A path the release
  actually ships but that was not deployed is annotated as a warning, so it can't
  quietly go missing.

Nothing needs configuring for that — it is on by default. Set `PROTECTED_PATHS`
when a path is a **real folder today** but is still managed outside the repo
(a client installs it from WP admin, another pipeline owns it, a vendor ships it
directly):

```
# Repo or environment variable — any of these forms work
PROTECTED_PATHS = plugins/some-client-managed-plugin, plugins/woocommerce*
PROTECTED_PATHS = ["plugins/some-client-managed-plugin", "themes/legacy"]
PROTECTED_PATHS = plugins/some-client-managed-plugin
                  themes/legacy
```

Paths are relative to `wp-content`, globs are allowed, and a bare name (no
slash) matches that folder wherever it lives — `woocommerce` covers
`plugins/woocommerce`. `#` starts a comment.

A single deploy can override the variable with the `protected_paths` input, and
`preserve_symlinks: false` turns the automatic symlink detection off (only useful
when a deploy is *meant* to replace symlinks with real directories). On
Pressable, `plugins/jetpack` and `plugins/akismet` are always protected — v3
deleted them from the release; v4 keeps them out of the sync and says so in the
log.

## Remote plugin install (Composer on the server)

By default a deploy ships everything: the build resolves Composer, and the release
zip carries every third-party plugin and theme. `REMOTE_PLUGIN_INSTALL=true`
inverts that for the Composer-managed part — the release contains only the
project's own code plus `composer.json`/`composer.lock`, and after the sync the
deploy reconciles the server against the lock with one WP-CLI call per package.

**What actually gets faster.** Not the build — set expectations here. Composer was
never the slow part (its cache is keyed on `composer.lock`); npm theme/plugin
builds dominate, and those still run on the runner because Pressable has no Node.
What shrinks is everything downstream of the build: the release zip, the transfer,
the GitHub release asset kept for rollbacks, the two-zip retention on the server,
and the sync itself — a Renovate bump of one plugin becomes one `wp plugin install`
instead of re-rsyncing the whole tree.

**Why not `composer install` over SSH.** Pressable's Composer guide documents an
"SSH build" that runs `composer install` in the container. This repo deliberately
does not do that: managed containers cap a single exec at ~300s (Pressable's own
troubleshooting table lists *"CLI job killed around 300 s — container exec
timeout"*), which a cold Composer install for a WooCommerce-scale project does not
reliably fit inside — and it would die mid-write with maintenance mode already on.
One short WP-CLI call per package stays far inside the cap, keeps Composer and
registry credentials off the server entirely, and leaves resolution on the runner.

**The lock is the source of truth, in both directions.** A package whose installed
version differs from the lock is reinstalled *at the locked version*, so deploying
an older `release_tag` downgrades third-party plugins instead of leaving them ahead
of the code. (v3 compared with `version_compare` and only ever upgraded, which
silently made rollbacks a no-op for everything Composer managed.)

**It respects `PROTECTED_PATHS` and symlinks.** Composer's `installer-paths` would
happily delete a platform symlink and drop a real directory in its place, and
WP-CLI would too — so every package is checked against the server's symlinks and
your protected paths before anything is installed. Note the skeleton in Pressable's
guide lists `wpackagist-plugin/woocommerce` in `require`; on a site where Pressable
symlinks WooCommerce, that package is skipped and logged rather than fighting the
platform.

```
REMOTE_PLUGIN_INSTALL = true
SATISPRESS_USER / SATISPRESS_PASSWORD   # only if you pull from packagist.linchpin.com
```

Requirements and caveats:

- **Per-plugin autoloaders only.** This mode skips the root Composer install, so
  there is no root `vendor/` in the release and nothing creates one on the server.
  That matches the layout Pressable's guide recommends (each plugin requires its
  own `vendor/autoload.php`). A project that depends on a *root* autoloader should
  not enable it.
- **Packages need a dist archive.** A source-only requirement (typically a `dev-*`
  VCS branch) has no zip for WP-CLI to install, so `build-release` keeps those in
  the release and they arrive over rsync as before. This is automatic.
- **New packages install inactive.** Nothing is activated for you — the run logs a
  warning listing them; activate via `post_deploy_command: wp plugin activate <slug>`.
- **Consider `maintenance_mode: true`.** `wp plugin install --force` replaces a
  plugin directory in place, so an updated plugin is briefly absent.
- **Key auth only.** Cloudways Autonomous (`DEPLOYMENT_AUTH_TYPE=pass`) is not
  supported and the deploy fails loudly rather than skipping the reconcile.

## GitHub Reusable Workflows

Linchpin WordPress projects use [Release Please](https://github.com/googleapis/release-please-action) with [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) to create releases.

| File                                                        | Description                                                                                                  |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| [build.yml](.github/workflows/build.yml)                   | Single-job project build producing a deploy-ready `release` artifact; optionally archives it on a GitHub release as a rollback asset |
| [deploy.yml](.github/workflows/deploy.yml)                 | Deploys a fresh build (staging), builds + deploys + archives a release (production via `build_for_release`), or redeploys a prebuilt asset (rollback via `release_tag`) to Pressable, WP Engine, or Cloudways |
| [deploy-continue.yml](.github/workflows/deploy-continue.yml) | Second half of the backup-and-continue flow — dispatched (via the caller) by Mantle once the Pressable backup completes |
| [lint.yml](.github/workflows/lint.yml)                     | PR lint: PHP syntax (any version), phpcs on changed files via cs2pr, optional PHPStan                          |
| [update-readme.yml](.github/workflows/update-readme.yml)   | Update the project README plugin table from composer.lock                                                      |
| [qa-run.yml](.github/workflows/qa-run.yml)                 | Trigger a QA platform run on deploy, poll it to a terminal state, and fail the job on a red test — the Ghost Inspector replacement |
| [auto-approve-maintenance.yml](.github/workflows/auto-approve-maintenance.yml) | Auto-approve PRs into a `maintenance/*` branch (or from a `security-update/*` branch) when only allow-listed dependency/config files changed |
| [auto-merge-maintenance.yml](.github/workflows/auto-merge-maintenance.yml) | Cron-driven: auto-merges open Renovate PRs targeting a `maintenance/YYYY-MM` branch, excluding anything labeled `major`. Never touches main/master |
| [ci.yml](.github/workflows/ci.yml)                         | This repo's own CI: actionlint + yamllint + zizmor                                                             |
| [qa-guard.yml](.github/workflows/qa-guard.yml)             | PR gate for `qa/` browser tests: validates them against the QA platform's schema, and fails a platform-authored PR that touches anything outside `qa/` |

### Composite Actions

| Action                                          | Description                                                                       |
| ----------------------------------------------- | --------------------------------------------------------------------------------- |
| [setup-wp-php](actions/setup-wp-php)            | PHP via setup-php + cached Composer install + COMPOSER_AUTH (no auth.json on disk) |
| [build-release](actions/build-release)          | Turn a built tree into a clean release/ dir using the project .distignore          |
| [deploy-pressable](actions/deploy-pressable)    | Upload + symlink-aware sync of a release to Pressable over SSH, maintenance mode, health check |
| [deploy-wpengine](actions/deploy-wpengine)      | Upload + symlink-aware sync of a release to WP Engine over SSH, health check       |
| [deploy-cloudways](actions/deploy-cloudways)    | Upload + symlink-aware sync of a release to Cloudways (key or password SSH auth), health check |
| [remote-plugin-install](actions/remote-plugin-install) | Reconcile third-party plugins/themes against composer.lock with per-package WP-CLI calls over SSH |
| [update-readme](actions/update-readme)          | Regenerate the README plugin/theme table from composer.lock                        |

## Example Shared Workflow Usage

See [docs/MIGRATION-v3-to-v4.md](docs/MIGRATION-v3-to-v4.md) for complete
caller examples (CI, staging/production deploys, release-please wiring, and
rollback).

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
      # Build this release, deploy it, and archive the zip on the release.
      build_for_release: ${{ github.event.release.tag_name }}
```

To auto-merge non-major Renovate PRs into a monthly `maintenance/YYYY-MM`
branch, add a caller workflow with its own `schedule` trigger (schedules
only fire in the repo where they're defined, so this small wrapper has to
live in the client repo — `auto-merge-maintenance.yml` itself only reacts
to `workflow_call`):

```yaml
name: Auto-merge Maintenance PRs
on:
  schedule:
    - cron: "0 * * * *"
  workflow_dispatch:
    inputs:
      dry_run:
        type: boolean
        default: false

jobs:
  auto-merge:
    uses: linchpin/actions/.github/workflows/auto-merge-maintenance.yml@v4
    secrets: inherit
    with:
      dry_run: ${{ inputs.dry_run || false }}
```

To run the QA platform on deploy — the replacement for the old Ghost
Inspector job — add a job that runs after the deploy. It triggers a run,
polls it to a terminal state, and **fails the deploy when a test is red**
(the `--errorOnFail` behaviour). The only setup a client repo needs is a
per-project bearer token in the `QA_API_TOKEN` secret (minted from the QA
platform):

```yaml
jobs:
  # ... your build + deploy jobs ...

  qa:
    needs: [deploy]
    uses: linchpin/actions/.github/workflows/qa-run.yml@v4
    secrets:
      QA_API_TOKEN: ${{ secrets.QA_API_TOKEN }}
    with:
      project: linchpin-com
      environment: production
      # Optional: narrow to one suite, override the recorded ref, or tune waits.
      # suite: smoke
      # ref: ${{ github.sha }}
      # poll_interval_seconds: 10
      # timeout_minutes: 20
```

## QA Guard

For client repositories with a `qa/` directory of browser tests managed by the
[QA platform](https://github.com/linchpin/automated-testing).

```yaml
name: QA Guard
on:
  pull_request:

jobs:
  qa-guard:
    uses: linchpin/actions/.github/workflows/qa-guard.yml@v4
    secrets:
      QA_SCHEMA_TOKEN: ${{ secrets.QA_SCHEMA_TOKEN }}
```

Two independent jobs:

- **boundary** — fails when a PR authored by the QA platform's GitHub App changes
  anything outside `qa/`. The platform opens PRs into client production
  repositories, so this is the guardrail on our own tooling. It does not apply to
  PRs authored by people, who legitimately change application code and its tests
  together.
- **schema** — validates every `qa/` file against the Zod schema in
  `linchpin/automated-testing`, and reports targets a test references but
  `targets.yaml` never defines. That last one otherwise fails at run time with
  `Unknown target`, which is a slower and more confusing way to learn about a
  typo.

Set `schema_ref` to pin the schema version if you want the gate to be
reproducible rather than tracking `main`. `qa_path` must match the project's
`qa_path` in the platform, and defaults to `qa`.

## Renovate Bot Scanning Configurations

| File                             | description                                               |
| -------------------------------- | --------------------------------------------------------- |
| [global.json](global.json)       | Shared global config for renovatebot                      |
| [wordpress.json](wordpress.json) | Shared config for renovatebot for WordPress installs.     |
| [js.json](js.json)               | Shared config for javascript projects (gulp builds, etc ) |

## README.md Updates

When your local project uses [Release Please](https://github.com/googleapis/release-please-action) that action will handle bumping the version numbers of all files you define within the release-please-config.json. However it doesn't take into account replacing arbitrary strings such as release date or updating the list of plugins updated within this release. The [update-readme.yml](.github/workflows/update-readme.yml) workflow seeks to fix that by updating the readme.md of your project with relevant information.

### Current Tags

| Tag                                                                            | Description                                                                                       |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `<!-- x-linchpin-plugin-list-start -->.*<!-- x-linchpin-plugin-list-end -->`   | Update a table of the plugins that are currently installed within the projects composer.lock file |
| `<!-- x-linchpin-release-date-start -->.*<!-- x-linchpin-release-date-end -->` | Update the release date of your project                                                           |

## More Useful Configs

| File                                     | Description                                                                                                       |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| [default.distignore](default.distignore) | Default .distignore applied during the release build if no .distignore is provided within your project (a copy is bundled in [actions/build-release](actions/build-release)) |

![Linchpin](https://raw.githubusercontent.com/linchpin/brand-assets/master/github-banner@2x.jpg)
