---
title: Composite actions
---

The steps the reusable workflows are built from, each usable on its own as `uses: linchpin/actions/actions/<name>@v4`. An action's scripts ship beside its `action.yml`, so the ref you pin is the code that runs. Most callers reach these through a workflow; the **Used by** column says which.

## Build

| Action | Does | Used by |
| --- | --- | --- |
| [setup-wp-php](setup-wp-php.md) | PHP through setup-php, a cached Composer install, and `COMPOSER_AUTH` from a secret with no `auth.json` on disk | `build.yml`, `lint.yml`, `php-checks.yml`, `plugin-check.yml` |
| [build-release](build-release.md) | Turns a built tree into a clean `release/` directory using the project's `.distignore` | `build.yml` |
| [strip-release-markers](strip-release-markers.md) | Removes release-please marker lines from `readme.txt` and similar files before they ship | Plugin release jobs |

## Deploy

| Action | Does | Used by |
| --- | --- | --- |
| [deploy-pressable](deploy-pressable.md) | Uploads a release to Pressable over SSH and syncs it around symlinks, with optional maintenance mode and a health check | `deploy.yml`, `deploy-continue.yml` |
| [deploy-wpengine](deploy-wpengine.md) | The same for WP Engine | `deploy.yml` |
| [deploy-cloudways](deploy-cloudways.md) | The same for Cloudways, with key or password SSH auth | `deploy.yml` |
| [remote-plugin-install](remote-plugin-install.md) | Reconciles third-party plugins and themes on the server against `composer.lock`, one WP-CLI call per package | `deploy.yml`, `deploy-continue.yml` |
| [unmanaged-plugins](unmanaged-plugins.md) | Warns about each plugin on the server that the repository doesn't manage, with what to do: add it to the repo, protect it, or remove it | `deploy.yml`, `deploy-continue.yml` |
| [safety-net](safety-net.md) | Development only: installs Safety Net as an mu-plugin and fails unless every site reports its data scrubbed | `deploy.yml` |
| [report-deployment](report-deployment.md) | Records a finished deploy, and the commits it shipped, in api.linchpin.com's deployment log | `deploy.yml`, `deploy-continue.yml` |

## Maintenance

| Action | Does | Used by |
| --- | --- | --- |
| [rolling-maintenance](rolling-maintenance.md) | Brings production into `maintenance`, then merges its green Renovate PRs, through the GitHub API alone | `rolling-maintenance.yml` |
| [governing-merge](governing-merge.md) | Merges Linchpin Governing's green single-package release bumps into production | `rolling-maintenance.yml` |
| [snapshot](snapshot.md) | Freezes a snapshot of `maintenance` and opens its PR, or tidies snapshots, through the GitHub API alone | `snapshots.yml`, `rolling-maintenance.yml` |
| [resolve-merge](resolve-merge.md) | Merges one branch into another when GitHub refuses, resolving manifest and lockfile conflicts deterministically | `rolling-maintenance.yml`, `snapshots.yml` |

## Repository upkeep

| Action | Does | Used by |
| --- | --- | --- |
| [update-readme](update-readme.md) | Regenerates the README plugin and theme table from `composer.lock` | `update-readme.yml` |
| [check-overrides](check-overrides.md) | Probes each npm `overrides` pin and reports the redundant or dangling ones | `check-overrides.yml` |
