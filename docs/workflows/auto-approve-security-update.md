---
title: auto-approve-security-update.yml
---

Approves a pull request from a `security-update/` branch with the bot's token when every file it changes is on the allow-list, and comments with the files it checked. A pull request that changes anything else is left for a person, and the comment names the files that stopped it. It approves and never merges.

It split from [auto-approve-maintenance.yml](auto-approve-maintenance.md) in v4.23.0. That workflow no longer approves `security-update/` branches, so a repository that relied on it for them has to call this one as well.

## Example

```yaml
name: Auto Approve Security Update PRs
on:
  pull_request:

jobs:
  auto-approve:
    uses: linchpin/actions/.github/workflows/auto-approve-security-update.yml@v4
    secrets:
      GH_BOT_TOKEN: ${{ secrets.GH_BOT_TOKEN }}
```

The job decides from `github.head_ref`, which GitHub sets only for pull request events. Trigger it on `pull_request`; on any other event the job is skipped.

## Which pull requests it considers

The job runs when the head branch starts with `security-update/`, whoever authored the pull request. The base branch doesn't matter.

## How it works

1. Lists the files the pull request changes.
2. Matches each one against the allow-list. Any file that doesn't match is logged as `❌ Found non-allowed file: <path>`.
3. Writes one comment, or updates the earlier one (it carries the marker `<!-- security-update-auto-approve -->`). The comment is headed `✅ Auto-approved: Security Update PR` or `❌ Not auto-approved: Non-allowed files detected`, and tables the changed files and any non-allowed ones.
4. Approves with `GH_BOT_TOKEN`, only when every file is allowed.

The marker differs from auto-approve-maintenance.yml's, so a pull request both workflows look at gets two comments, and neither overwrites the other.

## The allow-list

The list is the same as [auto-approve-maintenance.yml's](auto-approve-maintenance.md#the-allow-list), `.husky/` included, and the same rule applies: each pattern is matched against the end of the file's path, with nothing anchoring its start.

The exact expression, from the workflow:

```text
(\.github/workflows/.*\.ya?ml|\.release-please-manifest\.json|release-please-config\.json|CHANGELOG\.md|README\.md|\.gitignore|\.distignore|\.editorconfig|\.php-cs-fixer\.dist\.php|\.phplint\.yml|\.vipgoci_lint_skip_folders|\.vipgoci_phpcs_skip_folders|commitlint\.config\.js|dependabot\.yml|renovate\.json|pantheon\.yml|phpcs\.xml|composer\.json|composer\.lock|package\.json|package-lock\.json|yarn\.lock|themes/.*/style\.css|themes/.*/functions\.php|plugins/.+-functionality/.+-functionality\.php|\.husky/.+)$
```

This workflow, auto-approve-maintenance.yml and auto-merge-maintenance.yml each keep their own copy of the list. Change one and you have to change the others by hand.

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

[`.github/workflows/auto-approve-security-update.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/auto-approve-security-update.yml)
