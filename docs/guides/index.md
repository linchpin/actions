---
title: Guides
---

Flows that span several workflows and actions, written for the person wiring them up or reading a run that stopped.

## Deploying

| Guide | Covers |
| --- | --- |
| [Deploy a site](deploy-a-site.md) | Staging, release-triggered production, rollback, backup-and-continue, maintenance mode, the health check and the deployment log |
| [Host-managed folders](host-managed-folders.md) | How deploys skip symlinked plugins and themes, and `PROTECTED_PATHS` for folders managed outside the repository |
| [Remote plugin install](remote-plugin-install.md) | `REMOTE_PLUGIN_INSTALL`: shipping only your own code and installing third-party packages on the server from `composer.lock` |
| [Safety Net on development](safety-net-on-development.md) | Scrubbing the production copy on a development site before code deploys |

## Checking

| Guide | Covers |
| --- | --- |
| [PR checks](pr-checks.md) | `lint.yml` for sites; `php-checks.yml`, `plugin-check.yml` and `wp-version-checker.yml` for plugins |
| [Browser QA](qa.md) | `qa-guard.yml` on pull requests and `qa-run.yml` after a deploy |
| [Dependency checks](dependency-checks.md) | `check-overrides.yml` and `validate-composer.yml` |
| [README updates](readme-updates.md) | Keeping the README's release date and plugin table current on the release PR |

## Maintaining

| Guide | Covers |
| --- | --- |
| [Rolling maintenance](rolling-maintenance.md) | The permanent `maintenance` branch, Sisyphus's nightly run, snapshots and Governing merges |
| [The monthly maintenance window](monthly-maintenance-window.md) | The older `maintenance/YYYY-MM` model, which rolling maintenance replaces |
| [Resolving merge conflicts](resolving-merges.md) | What `resolve-merge` settles by itself, and the hand-off to Sisyphus and then a person |
