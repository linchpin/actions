---
title: auto-merge-maintenance.yml
---

Merges Renovate's pull requests into the monthly window once GitHub reports them ready to merge. Majors are excluded, and so is anything that changes a file outside the maintenance allow-list. It is cron-driven and reacts only to `workflow_call`. Schedules fire only in the repository that defines them, so each client repository needs a small caller with its own `schedule`. It never touches `main` or `master`.

## Example

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

## How it works

Each run lists up to 100 open pull requests and merges each one that passes every check below, with `gh pr merge --squash`. A pull request that fails a check is skipped with a log line saying which check stopped it, and the next run tries it again.

| Check | Log line when it fails |
| --- | --- |
| The base branch matches `^maintenance/[0-9]{4}-[0-9]{2}$` | `skip: base branch '<base>' is not a maintenance/YYYY-MM branch` |
| The author is `renovate[bot]` | `skip: author '<login>' is not renovate[bot]` |
| It is not labelled `major` | `skip: labeled 'major'` |
| Every changed file is on the allow-list | `skip: changed file '<path>' is outside the allow-list` |
| GitHub's `mergeStateStatus` is `CLEAN` | `skip: mergeStateStatus is '<state>', not CLEAN yet — will retry next run` |

`CLEAN` is GitHub's own verdict. A pull request still waiting on a required review or check is not `CLEAN`, so in a repository that requires an approval, pair this with [auto-approve-maintenance.yml](auto-approve-maintenance.md).

With `dry_run: true` each eligible pull request logs `dry-run: would merge PR #<number>` instead of merging.

## Behaviour notes

- **The base-branch pattern is the guard** that keeps this workflow off production branches. It also means it does nothing on [rolling maintenance](../guides/rolling-maintenance.md): the undated `maintenance` branch never matches, and rolling-maintenance.yml does its own merging.
- **Squashing each Renovate pull request is deliberate.** Each group lands on the window as one conventional commit. The window itself is merged into production with a merge commit, never a squash. See [the monthly maintenance window](../guides/monthly-maintenance-window.md).
- **The allow-list is the one in [auto-approve-maintenance.yml](auto-approve-maintenance.md), minus `.husky/`.** A Renovate pull request that touches `.husky/` is approved but never auto-merged.
- **All writes use `GH_BOT_TOKEN`.** The merge is attributed to that account.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"dry_run","type":"boolean","required":false,"defaultValue":"false","description":"Log what would be merged without merging anything","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"GH_BOT_TOKEN","type":"string","required":true,"defaultValue":"","description":"Bot token for the pushes and pull requests this workflow makes. Not \u003ccode\u003eGITHUB_TOKEN\u003c/code\u003e: a push or pull request made with it triggers no workflows, so required checks never run.","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `auto-merge` | `contents: write`, `pull-requests: write` |

## Source

[`.github/workflows/auto-merge-maintenance.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/auto-merge-maintenance.yml)
