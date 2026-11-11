---
title: The monthly maintenance window
---

Each month gets a `maintenance/YYYY-MM` branch with a draft pull request into production. Renovate raises its updates against that branch, green updates are approved and merged into it automatically, and a person reviews the month's batch and merges it. Three shared workflows make up the model, and they only work together. Repositories Sisyphus maintains every night use [rolling maintenance](rolling-maintenance.md) instead.

## The three workflows

| Workflow | Caller's trigger | Does |
| --- | --- | --- |
| [maintenance.yml](../workflows/maintenance.md) | `schedule` on the first of the month, plus `workflow_dispatch` | **Opens** `maintenance/YYYY-MM` and its draft pull request, and flags any older window still open |
| [auto-approve-maintenance.yml](../workflows/auto-approve-maintenance.md) | `pull_request` | **Approves** pull requests into the window that change only allow-listed files |
| [auto-merge-maintenance.yml](../workflows/auto-merge-maintenance.md) | `schedule`, hourly | **Merges** Renovate's non-major pull requests into the window once GitHub reports them `CLEAN` |

<!-- wp:docspress/diagram {"title":"One month's window","type":"flow","source":"maintenance.yml -\u003e Window branch: opens it and its draft PR\nRenovate -\u003e Window branch: raises update PRs\nauto-approve-maintenance.yml -\u003e Update PRs: approves allow-listed files\nauto-merge-maintenance.yml -\u003e Window branch: squash-merges CLEAN PRs\nReviewer -\u003e Production branch: merges the window","caption":"Only the last step needs a person."} /-->

Only the last two workflows were shared at first. The first was copied into 43 repositories, and 42 of those copies pushed a bare branch and opened no pull request, so auto-approve had nothing to approve. The shared `maintenance.yml` replaces those copies.

## Set it up

<!-- wp:docspress/file-tree {"root":"client-repo/","tree":".github/\n  workflows/\n    maintenance.yml\n    auto-approve-maintenance.yml\n    auto-merge-maintenance.yml\nrenovate.json","caption":"The three callers, named after the shared workflows they call."} /-->

1. Add the three callers. Each workflow's page has a complete one: [maintenance.yml](../workflows/maintenance.md), [auto-approve-maintenance.yml](../workflows/auto-approve-maintenance.md), [auto-merge-maintenance.yml](../workflows/auto-merge-maintenance.md).
2. Make `GH_BOT_TOKEN` available to the repository. It must be a personal access token, not `GITHUB_TOKEN`, because a pull request `GITHUB_TOKEN` opens triggers no required checks. See [secrets and variables](../getting-started/secrets-and-variables.md).
3. Add the Renovate preset `github>linchpin/renovatebot-config:maintenance-window` to `renovate.json`'s `extends`. It keeps majors out of the window, so each one gets its own pull request against the default branch.
4. Dispatch the window caller with `dry_run: true` and read the step summary. It shows the base, the branch, any open pull request, and the windows it would flag, and writes nothing.

`base` defaults to the repository's own default branch. Don't hardcode `main`: eight of the repositories that copied the old workflow use `master`.

## What gets approved and what gets merged

The two workflows apply different rules on purpose:

- **Approval** covers any pull request into, or out of, a `maintenance/` branch, whoever opened it, as long as every file is on the allow-list. Pull requests from `security-update/` branches have their own workflow, [auto-approve-security-update.yml](../workflows/auto-approve-security-update.md).
- **Merging** covers only pull requests into a `maintenance/YYYY-MM` branch, opened by `renovate[bot]`, not labelled `major`, with every file on the allow-list (minus `.husky/`), and reported `CLEAN` by GitHub.

Anything outside those rules waits for a person. The approval comment names the files that kept a pull request off the allow-list, and the merge run logs the reason for every skip.

## Overdue windows

When a new month's window opens while an older one is still open into the same base, the older pull request gets the `maintenance-overdue` label and one comment. It is never closed. Renovate raises each update against every open window, so an overdue window collects duplicates. It can also hold work or security fixes the base branch lacks, so a person decides whether to merge it or salvage it and retire it. The `maintenance-window` skill in [linchpin/skills](https://github.com/linchpin/skills) owns that procedure. Older window branches that have no pull request get no label, but the run summary lists them.

## Merging the window

The window's pull request opens titled `chore(NO-TASK): Merge the YYYY-MM maintenance window`, a conventional commit, so PR-title and commitlint checks accept it. Retitle it with the maintenance task's key before merging if the repository tracks one. Its body tells the reviewer to check the collected updates and mark it ready for review to merge the batch.

<!-- wp:docspress/callout {"tone":"warning","title":"Merge commit or rebase merge, never a squash","content":"\u003cp\u003eEach Renovate group lands on the window as its own conventional commit. A squash collapses the month into one commit release-please cannot read, and a bad group can no longer be reverted on its own.\u003c/p\u003e","collapsible":false} /-->

## Moving to rolling maintenance

Git cannot hold a branch named `maintenance` beside branches named `maintenance/YYYY-MM`, so every monthly window has to close before rolling maintenance can start. [bin/convert-repo](../scripts/convert-repo.md) does the move:

- With `--close-windows`, it closes windows that hold only Renovate's commits. A window holding a person's commits is left for a person.
- It replaces the `maintenance.yml` caller with the rolling-maintenance caller of the same name.
- It removes the `auto-approve-maintenance.yml`, `auto-merge-maintenance.yml`, `combine-dependency-prs.yml` and `combine-dependency-prs-schedule.yml` callers.
- It swaps the `maintenance-window` Renovate preset for the rolling-maintenance one.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| A Renovate pull request into the window never merges, and the run logs `skip: mergeStateStatus is 'BLOCKED', not CLEAN yet — will retry next run` | A required review or check has not passed | Check the approval comment. If it says `❌ Not auto-approved`, a file is off the allow-list and a person has to review it |
| `skip: labeled 'major'` | Majors are excluded on purpose | Review and merge it by hand, or let the `maintenance-window` preset send it to the default branch |
| `skip: changed file '.husky/…' is outside the allow-list` | auto-merge's allow-list lacks `.husky/`, although auto-approve's has it | Merge it by hand |
| The window opens with no label, and the run warns `Could not create the 'maintenance' label, so the pull request is opened without it.` | The token could not create the label | Create the label by hand. The next window picks it up |
| Nothing is auto-merged into a branch named `maintenance` | auto-merge only acts on `maintenance/YYYY-MM` | That branch is rolling maintenance, which [rolling-maintenance.yml](../workflows/rolling-maintenance.md) merges into |
