---
title: deploy.yml
---

`deploy.yml` ships a WordPress project to Pressable, WP Engine or Cloudways, picked by the `HOST` variable. It takes one of three paths: build and deploy (the default, used for staging); build, deploy and archive `release.zip` on a published release (`build_for_release`, used for production); or deploy a zip already archived on a release without building (`release_tag`, used for rollbacks). [Deploy a site](../guides/deploy-a-site.md) has a caller for each.

## Example

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

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Build","content":"<p>Unless <code>release_tag</code> is set, <code>build.yml</code> builds <code>release.zip</code>. With <code>build_for_release</code> it also attaches the zip to that release.</p>"},{"title":"Record","content":"<p>The deploy job refuses <code>safety_net</code> outside development, then creates one GitHub Deployment whose payload carries <code>release_tag</code>, <code>branch</code> and <code>correlation_id</code>, and marks it <code>in_progress</code>.</p>"},{"title":"Fetch","content":"<p>It downloads this run's <code>release</code> artifact, or with <code>release_tag</code> the <code>release.zip</code> attached to that release, retrying for about two minutes.</p>"},{"title":"Prepare the server","content":"<p>With <code>safety_net</code>, Safety Net is installed first and every site must report its data scrubbed. Protected paths come from <code>protected_paths</code>, else <code>vars.PROTECTED_PATHS</code>.</p>"},{"title":"Ship","content":"<p>The host action for <code>vars.HOST</code> uploads the zip, syncs it into <code>wp-content</code> around symlinks and protected paths, runs <code>post_deploy_command</code>, and health-checks the site.</p>"},{"title":"Reconcile","content":"<p>With <code>REMOTE_PLUGIN_INSTALL=true</code>, third-party plugins and themes are installed on the server from the <code>composer.lock</code> inside <code>release.zip</code>.</p>"},{"title":"Finish","content":"<p>The deployment is marked <code>success</code> or <code>failure</code>, and the deploy is recorded in the deployment log.</p>"}]} /-->

With `do_backup: true` on Pressable the run stops after **Record**: it parks the deployment as `queued` and asks api.linchpin.com for a backup, and [`deploy-continue.yml`](deploy-continue.md) ships the release once the backup completes.

## Permissions bite every caller

`build.yml` declares `contents: write` so it can attach `release.zip` to a release, and GitHub validates the whole called-workflow tree when the run starts. Grant `contents: write` and `deployments: write` in every caller, rollbacks included, or the run fails at startup with:

```text
the nested job 'build' is requesting 'contents: write', but is only allowed 'contents: read'
```

## Hosts and environments

The deploy job binds the GitHub environment named by `environment`, so `SITE_ID`, `SITE_URL`, `BRANCH` and the `SSH_*` secrets can be environment-scoped, and the environment's protection rules apply. It binds with `deployment: false`: the job's own steps create the one GitHub Deployment. The build configuration is read by `build.yml`, which binds no environment — see [build.yml](build.md).

| `HOST` | Host action | Server variables |
| --- | --- | --- |
| `pressable` | [`deploy-pressable`](../composite-actions/deploy-pressable.md) | `SITE_ID`, `SITE_URL`; secrets `SSH_HOST`, `SSH_USER`, `SSH_KEY`, `PRESSABLE_API_CLIENT_ID`, `PRESSABLE_API_CLIENT_SECRET` |
| `wpengine` | [`deploy-wpengine`](../composite-actions/deploy-wpengine.md) | `INSTALL_NAME`, `SITE_URL`; secret `SSH_KEY` |
| `cloudways` | [`deploy-cloudways`](../composite-actions/deploy-cloudways.md) | `DEPLOYMENT_AUTH_TYPE` (`key` by default), `SITE_URL`; secrets `SSH_HOST`, `SSH_USER`, `SSH_KEY` or `SSH_PASS` |

Any other value fails the deploy with `HOST='<value>' is not supported by linchpin/actions v4 (expected pressable, wpengine, or cloudways)`.

## Behaviour to know

- **One deploy per environment at a time.** The deploy job's concurrency group is `deploy-<owner/repo>-<environment>` and never cancels a run in progress; `deploy-continue.yml` shares it. Callers should still add their own workflow-level group, as the example does.
- **`maintenance_mode` reaches Pressable only**, where the Pressable API turns maintenance mode on for the sync and off afterwards, even when the sync fails. The Cloudways entrypoint puts the site in maintenance for every sync, and the WP Engine entrypoint clears maintenance mode if it is active.
- **The health check.** On Pressable it first runs `wp mantle health` on the server, falling back to checking WordPress loads (with a warning) where Mantle lacks the command. Every host then requests `SITE_URL` up to ten times, six seconds apart; any status from 100 to 499 passes, so an auth wall or redirect is fine, while a 5xx or no connection fails the deploy. WP Engine and Cloudways skip it when `SITE_URL` is empty. `health_check: false` turns it off.
- **A missing release asset fails fast.** A `release_tag` deploy retries eight times, fifteen seconds apart, then fails with `release.zip never appeared on <tag> after ~2 min. Has this release been deployed yet? (a deploy with build_for_release attaches release.zip)`.
- **`correlation_id`** is set by Sisyphus so it can find the deploy it dispatched; it lands in the deployment payload and the deployment log.
- **The deployment log never fails a deploy.** [`report-deployment`](../composite-actions/report-deployment.md) runs last with `continue-on-error`, on success or failure. A deploy parked for a backup is reported by `deploy-continue.yml` instead.

The symlink and protected-path handling, the remote plugin install and Safety Net each have their own guide: [Host-managed folders](../guides/host-managed-folders.md), [Remote plugin install](../guides/remote-plugin-install.md) and [Safety Net on development](../guides/safety-net-on-development.md).

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"environment","type":"string","required":false,"defaultValue":"staging","description":"The environment to deploy to","values":"","deprecated":false},{"name":"release_tag","type":"string","required":false,"defaultValue":"","description":"Deploy the release.zip asset attached to this GitHub release instead of building (rollback / redeploy)","values":"","deprecated":false},{"name":"build_for_release","type":"string","required":false,"defaultValue":"","description":"Build fresh, deploy, and attach the built release.zip to this already-published GitHub release. Use for release-triggered production deploys.","values":"","deprecated":false},{"name":"do_backup","type":"boolean","required":false,"defaultValue":"false","description":"Pressable: have api.linchpin.com back the site up, then deploy through the caller's continue workflow","values":"","deprecated":false},{"name":"maintenance_mode","type":"boolean","required":false,"defaultValue":"false","description":"Enable maintenance mode during the sync (v3 always did; v4 defaults to zero-downtime)","values":"","deprecated":false},{"name":"build_commands","type":"string","required":false,"defaultValue":"","description":"Optional additional shell commands to run during the build (ignored when release_tag is set)","values":"","deprecated":false},{"name":"post_deploy_command","type":"string","required":false,"defaultValue":"","description":"Optional shell commands run on the server after deployment","values":"","deprecated":false},{"name":"health_check","type":"boolean","required":false,"defaultValue":"true","description":"Fail the deploy if the site does not respond after the sync","values":"","deprecated":false},{"name":"protected_paths","type":"string","required":false,"defaultValue":"","description":"Paths this deploy must never overwrite, relative to wp-content (one per line, comma separated, or a JSON array; globs allowed). Defaults to vars.PROTECTED_PATHS. Symlinks on the server are already skipped automatically — this is for paths that are still real folders but are managed outside the repo.","values":"","deprecated":false},{"name":"preserve_symlinks","type":"boolean","required":false,"defaultValue":"true","description":"Leave plugins/themes/mu-plugins that are symlinks on the server exactly as they are (managed hosts link platform-owned plugins such as jetpack and woocommerce into wp-content). Set false only to let a deploy replace symlinks with real directories.","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false},{"name":"build_runner","type":"string","required":false,"defaultValue":"","description":"Runner label for the build job only. Defaults to runner","values":"","deprecated":false},{"name":"correlation_id","type":"string","required":false,"defaultValue":"","description":"Set by Sisyphus to find the deploy it dispatched; kept in the deployment payload and the deployment log","values":"","deprecated":false},{"name":"safety_net","type":"boolean","required":false,"defaultValue":"false","description":"Development only: before the code deploys, install Linchpin's Safety Net release as an mu-plugin, load every site so it scrubs the production data a sync copied there, and fail unless every site reports it done. Refused for any other environment, with do_backup, and on a server whose WP_ENVIRONMENT_TYPE is not development.","values":"","deprecated":false},{"name":"safety_net_version","type":"string","required":false,"defaultValue":"1.12.0","description":"The linchpin/safety-net release that safety_net installs","values":"","deprecated":false},{"name":"continue_workflow","type":"string","required":false,"defaultValue":"deploy-production-continue.yml","description":"With do_backup: the caller's workflow file that api.linchpin.com dispatches when the backup completes","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"PACKAGIST_COMPOSER_AUTH_JSON","type":"string","required":false,"defaultValue":"","description":"auth.json contents for packagist.linchpin.com (v4 passes this via the COMPOSER_AUTH env)","values":"","deprecated":false},{"name":"NPM_READ_TOKEN","type":"string","required":false,"defaultValue":"","description":"Read-only npmjs.com token, forwarded to the build for private @linchpinagency packages","values":"","deprecated":false},{"name":"PRESSABLE_API_CLIENT_ID","type":"string","required":false,"defaultValue":"","description":"Pressable API client (maintenance mode, backups)","values":"","deprecated":false},{"name":"PRESSABLE_API_CLIENT_SECRET","type":"string","required":false,"defaultValue":"","description":"Pressable API secret","values":"","deprecated":false},{"name":"SSH_HOST","type":"string","required":false,"defaultValue":"","description":"The SSH IP or Host Name","values":"","deprecated":false},{"name":"SSH_USER","type":"string","required":false,"defaultValue":"","description":"The SSH user used to interact w/ the remote environment","values":"","deprecated":false},{"name":"SSH_KEY","type":"string","required":false,"defaultValue":"","description":"The SSH key used to interact w/ the remote environment","values":"","deprecated":false},{"name":"SSH_PASS","type":"string","required":false,"defaultValue":"","description":"The SSH pass for environments that cannot support SSH Keys (Cloudways Autonomous)","values":"","deprecated":false},{"name":"MANTLE_API_BEARER","type":"string","required":false,"defaultValue":"","description":"Mantle API token used by the backup-and-continue deploy flow","values":"","deprecated":false},{"name":"DEPLOYMENTS_API_CLIENT_ID","type":"string","required":false,"defaultValue":"","description":"api.linchpin.com application client with deployments:write, for the deployment log","values":"","deprecated":false},{"name":"DEPLOYMENTS_API_CLIENT_SECRET","type":"string","required":false,"defaultValue":"","description":"That client's secret","values":"","deprecated":false},{"name":"SATISPRESS_USER","type":"string","required":false,"defaultValue":"","description":"Private Packagist username, used only by the REMOTE_PLUGIN_INSTALL reconcile","values":"","deprecated":false},{"name":"SATISPRESS_PASSWORD","type":"string","required":false,"defaultValue":"","description":"Private Packagist password, used only by the REMOTE_PLUGIN_INSTALL reconcile","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `build` (calls `build.yml`) | `contents: write` |
| `deploy` | `contents: read`, `deployments: write` |

## Source

[`.github/workflows/deploy.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/deploy.yml)
