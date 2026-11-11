---
title: Reusable workflows
---

Every workflow a site or plugin repository can call, as `uses: linchpin/actions/.github/workflows/<file>@v4`. A reusable workflow has no trigger of its own. The **Caller trigger** column is where callers usually hook it.

## Build and deploy

| Workflow | Does | Caller trigger |
| --- | --- | --- |
| [build.yml](build.md) | Builds Composer, themes and plugins in one job into a deploy-ready `release` artifact, and can attach `release.zip` to a GitHub release | Called by `deploy.yml`; rarely called directly |
| [deploy.yml](deploy.md) | Deploys a fresh build, builds and archives a release, or redeploys a release's zip to Pressable, WP Engine or Cloudways | `push` (staging), `release: published` (production), `workflow_dispatch` (rollback, Sisyphus) |
| [deploy-continue.yml](deploy-continue.md) | Finishes a `do_backup` deploy once the backup completes | `workflow_dispatch` from api.linchpin.com |

## Pull request checks

| Workflow | Does | Caller trigger |
| --- | --- | --- |
| [lint.yml](lint.md) | Site repositories: PHP syntax, PHPCS on changed files, optional PHPStan | `pull_request` |
| [php-checks.yml](php-checks.md) | Plugin repositories: parse lint, PHPStan, PHPUnit on two runtimes, branch-scoped PHPCS | `pull_request` |
| [plugin-check.yml](plugin-check.md) | Builds the distributable, or takes a prebuilt zip, and runs WordPress Plugin Check against it | `pull_request`, or a release job |
| [validate-composer.yml](validate-composer.md) | Fails when `composer.lock` can no longer be installed against `composer.json` | `pull_request` |
| [qa-guard.yml](qa-guard.md) | Validates `qa/` browser tests against the QA platform's schema, and fences the platform's own PRs to `qa/` | `pull_request` |

## After a deploy or release

| Workflow | Does | Caller trigger |
| --- | --- | --- |
| [qa-run.yml](qa-run.md) | Triggers a QA platform run, polls it, and fails the job on a red test | A job with `needs: [deploy]` |
| [update-readme.yml](update-readme.md) | Regenerates the README release date and plugin table and re-syncs `composer.lock` on the release PR's branch | release-please's `prs_created` output |

## Maintenance

| Workflow | Does | Caller trigger |
| --- | --- | --- |
| [rolling-maintenance.yml](rolling-maintenance.md) | Keeps the permanent `maintenance` branch current and merges what is green into it | `push`, `workflow_run`, `pull_request_review`, `schedule`, Sisyphus dispatch |
| [snapshots.yml](snapshots.md) | Freezes a tested commit of `maintenance` as a snapshot PR, refreshes a promotion branch, or tidies snapshots | Sisyphus dispatch, `schedule` |
| [maintenance.yml](maintenance.md) | Opens the monthly `maintenance/YYYY-MM` branch and its draft PR, and flags older windows | `schedule` (monthly) |
| [auto-approve-maintenance.yml](auto-approve-maintenance.md) | Approves PRs into or out of a `maintenance/*` branch that touch only allow-listed files | `pull_request` |
| [auto-approve-security-update.yml](auto-approve-security-update.md) | Approves PRs from a `security-update/*` branch that touch only allow-listed files | `pull_request` |
| [auto-merge-maintenance.yml](auto-merge-maintenance.md) | Merges green non-major Renovate PRs into a `maintenance/YYYY-MM` branch | `schedule` (hourly) |
| [check-overrides.yml](check-overrides.md) | Reports npm `overrides` pins that no longer do anything | `schedule` (monthly) |
| [wp-version-checker.yml](wp-version-checker.md) | Opens an issue when a plugin's `Tested up to` header falls behind WordPress | `schedule` |

## Dispatched by Linchpin Governing

| Workflow | Does | Trigger |
| --- | --- | --- |
| [composer-bump.yml](composer-bump.md) | Regenerates a site repository's `composer.lock` for one package and opens the PR | `workflow_dispatch` in this repository; nothing calls it from a site |

This repository's own `ci.yml`, `release.yml` and `sync-docs.yml` are covered in [Contributing](../contributing.md).
