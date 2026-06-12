# Linchpin Shared Project Configs

An open source collection of Linchpin's configs. Primarily used for [Renovate bot](https://github.com/marketplace/renovate) and shared workflows. While there are some aspects of this repo that are specific to [Linchpin](https://linchpin.com) and our build process, other organizations can take advantage of them if they want to use them.

![license](https://img.shields.io/github/license/linchpin/actions) ![version](https://img.shields.io/badge/version-v4-black)

## Major Differences in v4 of the GitHub Reusable Workflows

v4 is a ground-up rework of the build/deploy pipeline. The full
previous/next story — including the v3 bugs it fixes and the caller migration
steps — lives in **[docs/MIGRATION-v3-to-v4.md](docs/MIGRATION-v3-to-v4.md)**.
The headlines:

- **Build once, deploy from the release asset.** `create-release.yml` attaches
  a deploy-ready `release.zip` to each GitHub release; `deploy.yml` accepts a
  `release_tag` input and deploys that asset in a single job instead of
  rebuilding. This also gives every project an instant **rollback**: dispatch
  a deploy with a previous tag.
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
| SATISPRESS_USER              |         | Private Packagist auth (remote-plugin-install path — not yet ported to v4)              |
| SATISPRESS_PASSWORD          |         | Private Packagist auth (remote-plugin-install path — not yet ported to v4)              |

### Variables

To learn more [about variables](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables) in your workflows please see GitHub's documentation.

| Key                   | Default | Description                                                                              |
| --------------------- | ------- | ---------------------------------------------------------------------------------------- |
| HOST                  |         | The host of the project, one of `pressable`, `wpengine`, `cloudways`                     |
| SITE_URL              |         | The url of the site including https:// (also used by the v4 post-deploy health check)    |
| SITE_ID               |         | When using **Pressable** this is how we reference a site                                 |
| INSTALL_NAME          |         | Install name when project is hosted on WP Engine                                         |
| DEPLOYMENT_AUTH_TYPE  | key     | Cloudways SSH auth type: `key` or `pass` (Cloudways Autonomous)                          |
| REMOTE_PLUGIN_INSTALL | false   | Install plugins on the server via WP CLI instead of shipping them (not yet ported to v4) |
| BRANCH                | staging | The default branch associated with the environment                                       |
| PHP_VERSION           |         | PHP version used for builds and linting (e.g. `8.5`)                                     |
| NODE_VERSION          |         | Node version used for builds (e.g. `24`)                                                 |
| THEMES                |         | A JSON formatted array of themes to build Ex `["linchpin"]`                              |
| PLUGINS               |         | A JSON formatted array of plugins to build Ex `["linchpin-functionality"]`               |
| THEME_USES_COMPOSER   | false   | Do the theme(s) use composer to load dependencies                                        |
| PLUGIN_USES_COMPOSER  | true    | Do the plugin(s) use composer to load dependencies                                       |

> v3's `ENVIRONMENT` and `DEPLOYMENT_PATH` variables are no longer read by
> v4 workflows (deployment paths are composite-action inputs with per-host
> defaults).

## GitHub Reusable Workflows

Linchpin WordPress projects use [Release Please](https://github.com/googleapis/release-please-action) with [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) to create releases.

| File                                                        | Description                                                                                                  |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| [build.yml](.github/workflows/build.yml)                   | Single-job project build producing a deploy-ready `release` artifact; optionally attaches it to a GitHub release |
| [create-release.yml](.github/workflows/create-release.yml) | Thin wrapper around build.yml used from release-please callers — builds once and attaches `release.zip`       |
| [deploy.yml](.github/workflows/deploy.yml)                 | Deploys a fresh build (staging) or a prebuilt release asset (production/rollback) to Pressable, WP Engine, or Cloudways |
| [deploy-continue.yml](.github/workflows/deploy-continue.yml) | Second half of the backup-and-continue flow — dispatched (via the caller) by Mantle once the Pressable backup completes |
| [lint.yml](.github/workflows/lint.yml)                     | PR lint: PHP syntax (any version), phpcs on changed files via cs2pr, optional PHPStan                          |
| [update-readme.yml](.github/workflows/update-readme.yml)   | Update the project README plugin table from composer.lock                                                      |
| [ci.yml](.github/workflows/ci.yml)                         | This repo's own CI: actionlint + yamllint + zizmor                                                             |

### Composite Actions

| Action                                          | Description                                                                       |
| ----------------------------------------------- | --------------------------------------------------------------------------------- |
| [setup-wp-php](actions/setup-wp-php)            | PHP via setup-php + cached Composer install + COMPOSER_AUTH (no auth.json on disk) |
| [build-release](actions/build-release)          | Turn a built tree into a clean release/ dir using the project .distignore          |
| [deploy-pressable](actions/deploy-pressable)    | Upload + sync a release to Pressable over SSH, maintenance mode, health check      |
| [deploy-wpengine](actions/deploy-wpengine)      | Upload + sync a release to WP Engine over SSH, health check                        |
| [deploy-cloudways](actions/deploy-cloudways)    | Upload + sync a release to Cloudways (key or password SSH auth), health check      |
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
      release_tag: ${{ github.event.release.tag_name }}
```

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
