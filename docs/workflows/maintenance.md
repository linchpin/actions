---
title: maintenance.yml
---

Opens this month's maintenance window: the `maintenance/YYYY-MM` branch and the draft pull request that Renovate stacks its dependency updates onto. Call it on a monthly schedule in a repository that still uses the monthly window. A repository on [rolling maintenance](../guides/rolling-maintenance.md) does not use it. [The monthly maintenance window](../guides/monthly-maintenance-window.md) shows how it fits with the approve and merge workflows.

## Example

```yaml
name: Monthly Maintenance Branch
on:
  schedule:
    - cron: '0 0 1 * *'  # 00:00 on the first of the month
  workflow_dispatch:
    inputs:
      dry_run:
        description: "Report what would be created and write nothing"
        type: boolean
        default: false

jobs:
  open-window:
    uses: linchpin/actions/.github/workflows/maintenance.yml@v4
    with:
      dry_run: ${{ inputs.dry_run || false }}
    secrets:
      GH_BOT_TOKEN: ${{ secrets.GH_BOT_TOKEN }}
```

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Name the window","content":"\u003cp\u003eThe month is read in UTC. The branch is \u003ccode\u003emaintenance/YYYY-MM\u003c/code\u003e and the pull request title is \u003ccode\u003echore(NO-TASK): Merge the YYYY-MM maintenance window\u003c/code\u003e. The base is the \u003ccode\u003ebase\u003c/code\u003e input, or the repository's default branch.\u003c/p\u003e"},{"title":"Create the branch","content":"\u003cp\u003eWhen the branch is missing, it is pushed with one empty commit, \u003ccode\u003echore(NO-TASK): Open the YYYY-MM maintenance window\u003c/code\u003e, because GitHub rejects a pull request with an empty diff. An existing branch is left alone.\u003c/p\u003e"},{"title":"Open the pull request","content":"\u003cp\u003eWhen no pull request is open for the branch, the label is created if the repository lacks it, then the draft pull request is opened. If the label cannot be created, the pull request opens without it. An open pull request is left alone.\u003c/p\u003e"},{"title":"Flag overdue windows","content":"\u003cp\u003eAny older \u003ccode\u003emaintenance/YYYY-MM\u003c/code\u003e pull request still open into the same base gets \u003ccode\u003eoverdue_label\u003c/code\u003e and one comment. Older window branches with no pull request are listed in the run summary.\u003c/p\u003e"}]} /-->

With `dry_run: true` the run writes the plan to the step summary and changes nothing.

## Behaviour notes

- **Idempotent.** Every step checks before it writes, so a `workflow_dispatch` re-run after a partial failure is safe. Runs share the concurrency group `maintenance-window-<owner>/<repo>` without cancelling, so a dispatch that races the cron waits instead of opening a second window.
- **The branch starts from the commit the run checked out.** That is the ref that triggered the run: the default branch for a schedule, or the branch picked for a dispatch. When `base` names another branch, dispatch from that branch.
- **`GH_BOT_TOKEN`, never `GITHUB_TOKEN`.** A pull request that `GITHUB_TOKEN` opens triggers no required checks.
- **The branch name is fixed.** [auto-merge-maintenance.yml](auto-merge-maintenance.md) only merges into branches matching `^maintenance/[0-9]{4}-[0-9]{2}$`, so a renamed window would silently stop auto-merging.
- **The title is a conventional commit**, so PR-title and commitlint checks accept it. Retitle it with the maintenance task's key before merging if the repository tracks one.
- **An overdue window is flagged, never closed.** Renovate raises each update against every open window, so an overdue one collects duplicates. It can also hold work or security fixes the base branch lacks, so closing it is a person's decision. The comment is posted once; later runs only re-apply the label.

<!-- wp:docspress/callout {"tone":"warning","title":"Merge the window with a merge commit or a rebase merge","content":"\u003cp\u003eNever squash it. Each Renovate group lands on the window as its own conventional commit. A squash collapses the month into one commit release-please cannot read, and a bad group can no longer be reverted on its own.\u003c/p\u003e","collapsible":false} /-->

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"base","type":"string","required":false,"defaultValue":"","description":"Branch the PR targets. Defaults to the repository's own default branch, which is not \u003ccode\u003emain\u003c/code\u003e everywhere.","values":"","deprecated":false},{"name":"label","type":"string","required":false,"defaultValue":"maintenance","description":"Label for the PR, created if the repository lacks it. Empty applies none.","values":"","deprecated":false},{"name":"draft","type":"boolean","required":false,"defaultValue":"true","description":"Open the PR as a draft; marking it ready merges the batch","values":"","deprecated":false},{"name":"overdue_label","type":"string","required":false,"defaultValue":"maintenance-overdue","description":"Label added to an older window's PR that is still open when this month's window opens. Created if missing. Empty skips flagging.","values":"","deprecated":false},{"name":"dry_run","type":"boolean","required":false,"defaultValue":"false","description":"Report what would be created and write nothing","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"GH_BOT_TOKEN","type":"string","required":true,"defaultValue":"","description":"PAT used to push the branch and open the PR. Not GITHUB_TOKEN — a PR it authors triggers no required checks.","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Outputs

<!-- wp:docspress/fields {"title":"Outputs","fields":[{"name":"branch","type":"string","required":false,"defaultValue":"","description":"The maintenance branch name for this month","values":"","deprecated":false},{"name":"pr","type":"string","required":false,"defaultValue":"","description":"Number of the maintenance pull request, new or already open","values":"","deprecated":false},{"name":"overdue","type":"string","required":false,"defaultValue":"","description":"Space-separated numbers of older window PRs flagged as overdue","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `open-window` | `contents: write`, `pull-requests: write` |

## Source

[`.github/workflows/maintenance.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/maintenance.yml)
