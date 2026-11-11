---
title: auto-approve-maintenance.yml
---

Approves a dependency pull request with the bot's token when every file it changes is on the maintenance allow-list, and comments with the files it checked. A pull request that changes anything else is left for a person, and the comment names the files that stopped it. It approves and never merges. In the monthly window, [auto-merge-maintenance.yml](auto-merge-maintenance.md) does the merging.

## Example

```yaml
name: Auto Approve Maintenance PRs
on:
  pull_request:

jobs:
  auto-approve:
    uses: linchpin/actions/.github/workflows/auto-approve-maintenance.yml@v4
    secrets:
      GH_BOT_TOKEN: ${{ secrets.GH_BOT_TOKEN }}
```

The job decides from `github.head_ref` and `github.base_ref`, which GitHub sets only for pull request events. Trigger it on `pull_request`; on any other event the job is skipped.

## Which pull requests it considers

The job runs when any one of these holds, whoever authored the pull request:

- the head branch starts with `maintenance/`, which includes the window's own pull request into production;
- the base branch starts with `maintenance/`.

The rolling `maintenance` branch has no slash, so pull requests into it do not match.

Until v4.23.0 it also approved pull requests from `security-update/` branches. Those moved to [auto-approve-security-update.yml](auto-approve-security-update.md), which a repository has to call separately.

## How it works

1. Lists the files the pull request changes.
2. Matches each one against the allow-list. Any file that doesn't match is logged as `❌ Found non-allowed file: <path>`.
3. Writes one comment, or updates the earlier one (it carries the marker `<!-- maintenance-auto-approve -->`). The comment is headed `✅ Auto-approved: Maintenance PR` or `❌ Not auto-approved: Non-allowed files detected`, and tables the changed files and any non-allowed ones.
4. Approves with `GH_BOT_TOKEN`, only when every file is allowed.

## The allow-list

Each pattern is matched against the end of the file's path, with nothing anchoring its start. `composer.json` therefore also covers `plugins/example/composer.json`, and `README.md` covers a README in any directory.

| Pattern | Covers |
| --- | --- |
| `.github/workflows/*.yml`, `*.yaml` | Workflow files |
| `.release-please-manifest.json`, `release-please-config.json`, `CHANGELOG.md`, `README.md` | Release bookkeeping |
| `composer.json`, `composer.lock`, `package.json`, `package-lock.json`, `yarn.lock` | Manifests and lockfiles |
| `.gitignore`, `.distignore`, `.editorconfig` | Repository housekeeping |
| `.php-cs-fixer.dist.php`, `.phplint.yml`, `phpcs.xml`, `.vipgoci_lint_skip_folders`, `.vipgoci_phpcs_skip_folders` | Lint configuration |
| `commitlint.config.js`, `dependabot.yml`, `renovate.json`, `pantheon.yml` | Tool configuration |
| `themes/*/style.css`, `themes/*/functions.php` | Theme headers |
| `plugins/*-functionality/*-functionality.php` | A functionality plugin's main file |
| `.husky/*` | Git hooks. auto-merge-maintenance.yml's copy of the list does not allow them |

The exact expression, from the workflow:

```text
(\.github/workflows/.*\.ya?ml|\.release-please-manifest\.json|release-please-config\.json|CHANGELOG\.md|README\.md|\.gitignore|\.distignore|\.editorconfig|\.php-cs-fixer\.dist\.php|\.phplint\.yml|\.vipgoci_lint_skip_folders|\.vipgoci_phpcs_skip_folders|commitlint\.config\.js|dependabot\.yml|renovate\.json|pantheon\.yml|phpcs\.xml|composer\.json|composer\.lock|package\.json|package-lock\.json|yarn\.lock|themes/.*/style\.css|themes/.*/functions\.php|plugins/.+-functionality/.+-functionality\.php|\.husky/.+)$
```

This workflow, auto-merge-maintenance.yml and [auto-approve-security-update.yml](auto-approve-security-update.md) each keep their own copy of the list. Change one and you have to change the others by hand.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"GH_BOT_TOKEN","type":"string","required":true,"defaultValue":"","description":"Bot token the workflow comments and approves with.","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `auto-approve` | none declared — runs with the caller's `GITHUB_TOKEN` permissions |

## Source

[`.github/workflows/auto-approve-maintenance.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/auto-approve-maintenance.yml)
