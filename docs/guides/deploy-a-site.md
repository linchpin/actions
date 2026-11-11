---
title: Deploy a site
---

A site repository deploys through one shared workflow, [`deploy.yml`](../workflows/deploy.md), called from a few thin workflows of its own: one per environment, one for rollbacks, and on Pressable optionally one that finishes a deploy after a backup. This page gives each caller and explains what the deploy does on the way.

## Before the first deploy

| Set | Where | Used by |
| --- | --- | --- |
| `HOST` — `pressable`, `wpengine` or `cloudways` | Repository variable | The deploy job, to pick the host action |
| `THEMES`, `PLUGINS`, `PHP_VERSION`, `NODE_VERSION`, `THEME_USES_COMPOSER`, `PLUGIN_USES_COMPOSER` | Repository variables | The build, which binds no environment and cannot see environment-scoped values |
| `SITE_URL`; `SITE_ID` on Pressable | Environment variables | The deploy job and the health check |
| `INSTALL_NAME` on WP Engine; `DEPLOYMENT_AUTH_TYPE` on Cloudways | Variables | The deploy job |
| `SSH_HOST`, `SSH_USER`, `SSH_KEY`; `SSH_PASS` for Cloudways password auth | Secrets | The host action |
| `PRESSABLE_API_CLIENT_ID`, `PRESSABLE_API_CLIENT_SECRET` | Secrets | Every Pressable deploy authenticates with the Pressable API first |
| `PACKAGIST_COMPOSER_AUTH_JSON`, `NPM_READ_TOKEN` | Secrets | The build, for private Composer and npm packages |

Each one is described in [Secrets and variables](../getting-started/secrets-and-variables.md). Pass secrets with `secrets: inherit`.

<!-- wp:docspress/callout {"tone":"warning","title":"Grant contents: write in every caller","content":"<p>The build job declares <code>contents: write</code> so it can attach <code>release.zip</code> to a release, and GitHub checks the whole called-workflow tree when a run starts. A caller that grants only <code>contents: read</code> fails before any job runs, rollbacks included.</p>","collapsible":false} /-->

## Staging

A plain deploy builds the branch it runs on and ships it.

```yaml
name: Deploy to Staging
on:
  push:
    branches: [staging]
  workflow_dispatch:

concurrency:
  group: deploy-staging
  cancel-in-progress: false

permissions:
  contents: write
  deployments: write

jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: staging
```

## Production

release-please publishes each release; the production deploy builds it, ships it, and archives the deployable `release.zip` on the release so it can be rolled back to later.

```yaml
name: Deploy to Production
on:
  release:
    types: [published]

concurrency:
  group: deploy-production
  cancel-in-progress: false

permissions:
  contents: write
  deployments: write

jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: production
      build_for_release: ${{ github.event.release.tag_name }}
```

Configure release-please with `GH_BOT_TOKEN` and without `draft: true`. A release published with the default `GITHUB_TOKEN` fires no `release: published` event, so this workflow would never run. There is nothing to wait for: the deploy builds its own zip rather than downloading one attached earlier.

## Roll back

`release_tag` skips the build and deploys the `release.zip` a production deploy archived on that release.

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

permissions:
  contents: write
  deployments: write

jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: ${{ inputs.environment }}
      release_tag: ${{ inputs.release_tag }}
```

A release that was never deployed with `build_for_release` has no zip. The deploy retries for about two minutes, then fails with `release.zip never appeared on <tag> after ~2 min.` With [remote plugin install](remote-plugin-install.md), a rollback also returns third-party plugins to the versions that release locked.

## Back up first, on Pressable

`do_backup: true` has api.linchpin.com back the site up before anything ships. The run that starts the deploy only parks it; a second workflow in the site repository finishes it.

<!-- wp:docspress/diagram {"title":"Backup and continue","type":"sequence","source":"deploy.yml -> GitHub: create the deployment, mark it queued\ndeploy.yml -> api.linchpin.com: POST /api/v1/deployments/start\napi.linchpin.com -> Pressable: back the site up\napi.linchpin.com -> Continue workflow: dispatch with deployment_id and workflow_run_id\nContinue workflow -> deploy-continue.yml: call\ndeploy-continue.yml -> Pressable: sync the original run's release.zip\ndeploy-continue.yml -> GitHub: mark the deployment success or failure","caption":"The two runs share one GitHub Deployment."} /-->

1. Add the `MANTLE_API_BEARER` secret. Without it the run fails with `do_backup needs the MANTLE_API_BEARER secret to ask api.linchpin.com for the backup.`
2. Add the continue workflow from [`deploy-continue.yml`](../workflows/deploy-continue.md) as `.github/workflows/deploy-production-continue.yml`, or pass its file name as `continue_workflow`. api.linchpin.com dispatches it on the environment's `BRANCH` variable (`main` when unset).
3. Pass `do_backup: true` to the production deploy.

If api.linchpin.com refuses the request, the run fails with `api.linchpin.com would not take the backup, so nothing was deployed` and marks the deployment failed. The continue run downloads the original run's artifact, which is kept for one day, and `do_backup` works on Pressable only.

## Maintenance mode

Deploys run without a maintenance window by default: each theme and plugin syncs on its own and briefly. On Pressable, `maintenance_mode: true` turns maintenance mode on through the Pressable API for the sync and off again afterwards, even when the sync fails. The input does not reach the other hosts: the Cloudways entrypoint enables maintenance mode for every sync, and the WP Engine entrypoint clears it if it is active.

## The health check

A deploy succeeds only once the site answers. On Pressable, the deploy first runs `wp mantle health` on the server, or only checks WordPress loads (with a warning) where the site's Mantle predates that command. Every host then requests `SITE_URL` up to ten times, six seconds apart. Any status from 100 to 499 passes, so an auth wall or a redirect is fine; a 5xx or no connection fails the deploy. Turn it off with `health_check: false`.

## One deploy at a time

The deploy job queues behind any other deploy to the same environment of the same repository (group `deploy-<owner/repo>-<environment>`) and never cancels one in progress. Give each caller its own workflow-level group with `cancel-in-progress: false`, as the examples do.

## The deployment log

Every finished deploy, successful or not, is recorded in api.linchpin.com's deployment log with the commits since the environment's last successful deploy and, for a release, its notes. It needs the `DEPLOYMENTS_API_CLIENT_ID` and `DEPLOYMENTS_API_CLIENT_SECRET` organization secrets, which `secrets: inherit` passes through, and it never fails the deploy. See [`report-deployment`](../composite-actions/report-deployment.md).

## Related

- [Host-managed folders](host-managed-folders.md) — what the sync leaves alone, and `PROTECTED_PATHS`.
- [Remote plugin install](remote-plugin-install.md) — installing third-party plugins on the server from `composer.lock`.
- [Safety Net on development](safety-net-on-development.md) — scrubbing a dev copy of production before deploying to it.
- [Choosing a runner](../getting-started/choosing-a-runner.md) — `runner` and `build_runner`.
