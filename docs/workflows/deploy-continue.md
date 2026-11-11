---
title: deploy-continue.yml
---

`deploy-continue.yml` is the second half of a `do_backup` deploy on Pressable. [`deploy.yml`](deploy.md) creates the GitHub Deployment, parks it as `queued` and asks api.linchpin.com to back the site up; when the backup completes, api.linchpin.com dispatches the caller's continue workflow, which calls this one to ship the original run's `release.zip` and settle that same deployment.

## Example

The caller's continue workflow. Its file name must match `deploy.yml`'s `continue_workflow` input, `deploy-production-continue.yml` by default, and it must declare the dispatch inputs, because api.linchpin.com sends `deployment_id` and `workflow_run_id` as string inputs.

```yaml
name: Continue Deploy to Production
on:
  workflow_dispatch: # dispatched by api.linchpin.com when the backup completes
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

`environment` defaults to `staging`, so a production continue workflow has to say `production`.

## How it works

1. Marks the original deployment `in_progress`.
2. Downloads the `release` artifact from run `workflow_run_id`, which is why the caller grants `actions: read`. With `release_tag` it downloads that release's `release.zip` instead, retrying for about ten minutes.
3. Syncs it with [`deploy-pressable`](../composite-actions/deploy-pressable.md), with the same maintenance mode, post-deploy command, health check, protected paths and symlink handling as `deploy.yml`.
4. With `REMOTE_PLUGIN_INSTALL=true`, reconciles third-party plugins and themes from the `composer.lock` inside the zip, as `deploy.yml` does.
5. Marks the deployment `success` or `failure` and records it in the deployment log with [`report-deployment`](../composite-actions/report-deployment.md).

## Behaviour to know

- **Pressable only.** The backup is a Pressable feature, so any other `HOST` fails with `The backup-and-continue flow currently supports HOST=pressable only (the backup is a Pressable API feature)`.
- **The run artifact lasts one day.** `build.yml` keeps the `release` artifact for one day, so the continue run has to start within that window.
- **Pair `do_backup` with a build.** `deploy.yml`'s request to api.linchpin.com carries no `release_tag`, and a `release_tag` deploy builds no run artifact, so use `do_backup` on a plain deploy or with `build_for_release`.
- **No Safety Net.** `deploy.yml` refuses `safety_net` together with `do_backup`.
- **Queued behind other deploys.** The job shares `deploy.yml`'s concurrency group, `deploy-<owner/repo>-<environment>`.

The whole flow, from the caller's side, is in [Deploy a site](../guides/deploy-a-site.md).

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"deployment_id","type":"string","required":true,"defaultValue":"","description":"GitHub deployment ID created by the original deploy run","values":"","deprecated":false},{"name":"workflow_run_id","type":"string","required":true,"defaultValue":"","description":"Run ID of the original deploy (source of the release artifact)","values":"","deprecated":false},{"name":"release_tag","type":"string","required":false,"defaultValue":"","description":"When the original deploy used a release asset, re-download it by tag instead of the run artifact","values":"","deprecated":false},{"name":"environment","type":"string","required":false,"defaultValue":"staging","description":"The environment to deploy to","values":"","deprecated":false},{"name":"maintenance_mode","type":"boolean","required":false,"defaultValue":"false","description":"Enable maintenance mode during the sync","values":"","deprecated":false},{"name":"post_deploy_command","type":"string","required":false,"defaultValue":"","description":"Optional shell commands run on the server after deployment","values":"","deprecated":false},{"name":"health_check","type":"boolean","required":false,"defaultValue":"true","description":"Fail the deploy if the site does not respond after the sync","values":"","deprecated":false},{"name":"protected_paths","type":"string","required":false,"defaultValue":"","description":"Paths this deploy must never overwrite, relative to wp-content (one per line, comma separated, or a JSON array; globs allowed). Defaults to vars.PROTECTED_PATHS.","values":"","deprecated":false},{"name":"preserve_symlinks","type":"boolean","required":false,"defaultValue":"true","description":"Leave plugins/themes/mu-plugins that are symlinks on the server exactly as they are (Pressable links platform-owned plugins such as jetpack and woocommerce into wp-content).","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"PRESSABLE_API_CLIENT_ID","type":"string","required":false,"defaultValue":"","description":"Pressable API client (maintenance mode, backups)","values":"","deprecated":false},{"name":"PRESSABLE_API_CLIENT_SECRET","type":"string","required":false,"defaultValue":"","description":"Pressable API secret","values":"","deprecated":false},{"name":"SSH_HOST","type":"string","required":false,"defaultValue":"","description":"The SSH IP or Host Name","values":"","deprecated":false},{"name":"SSH_USER","type":"string","required":false,"defaultValue":"","description":"The SSH user used to interact w/ the remote environment","values":"","deprecated":false},{"name":"SSH_KEY","type":"string","required":false,"defaultValue":"","description":"The SSH key used to interact w/ the remote environment","values":"","deprecated":false},{"name":"SATISPRESS_USER","type":"string","required":false,"defaultValue":"","description":"Private Packagist username, used only by the REMOTE_PLUGIN_INSTALL reconcile","values":"","deprecated":false},{"name":"SATISPRESS_PASSWORD","type":"string","required":false,"defaultValue":"","description":"Private Packagist password, used only by the REMOTE_PLUGIN_INSTALL reconcile","values":"","deprecated":false},{"name":"DEPLOYMENTS_API_CLIENT_ID","type":"string","required":false,"defaultValue":"","description":"api.linchpin.com application client with deployments:write, for the deployment log","values":"","deprecated":false},{"name":"DEPLOYMENTS_API_CLIENT_SECRET","type":"string","required":false,"defaultValue":"","description":"That client's secret","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `deploy` | `contents: read`, `deployments: write`, `actions: read` |

## Source

[`.github/workflows/deploy-continue.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/deploy-continue.yml)
