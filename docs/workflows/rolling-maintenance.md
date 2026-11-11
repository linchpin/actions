---
title: rolling-maintenance.yml
---

Keeps a site's permanent `maintenance` branch current. Each run brings the production branch into it, then squash-merges each Renovate PR into it once its checks are green: one labelled `automerge-safe` at once, any other once a person approves it. The same job merges green Linchpin Governing bumps into production and tags snapshots merged there, since they share its triggers and token. It never promotes anything; [snapshots.yml](snapshots.md) does, through a PR a person merges.

A site repository calls it from its own `maintenance.yml`, which Sisyphus dispatches by name before each nightly deploy to dev. [bin/convert-repo](../scripts/convert-repo.md) writes that caller, and [Rolling maintenance](../guides/rolling-maintenance.md) explains the model around it.

## Example

This is the caller `bin/convert-repo` writes from [`templates/rolling-maintenance/maintenance.yml`](https://github.com/linchpin/actions/blob/main/templates/rolling-maintenance/maintenance.yml). It fills in `@PRODUCTION_BRANCH@` and `@CI_WORKFLOW@` (the workflows that check PRs), and drops the `workflow_run` trigger when the repository has none.

<!-- wp:docspress/colorful-code {"language":"yaml","filename":".github/workflows/maintenance.yml","code":"# Rolling Maintenance (linchpin/actions v4)\n#\n# Keeps `maintenance` current: brings @PRODUCTION_BRANCH@ in and merges green Renovate PRs\n# into it. Sisyphus dispatches this file by name before each nightly deploy to\n# dev, so keep its name. Written by linchpin/actions bin/convert-repo.\n\nname: Rolling Maintenance\n\n# Sisyphus finds its dispatch by the correlation_id in the name; a blank name\n# keeps GitHub's own.\nrun-name: \u003e-\n  ${{ inputs.correlation_id\n  && format('Rolling Maintenance {0}', inputs.correlation_id)\n  || ' ' }}\n\non:\n  # Production changed: bring it in.\n  push:\n    branches: ['@PRODUCTION_BRANCH@']\n  # CI finishing on a PR into the branch or a Governing bump: merge what is green.\n  workflow_run:\n    workflows: ['@CI_WORKFLOW@']\n    types: [completed]\n    branches: ['renovate/**', 'governing/**']\n  # An approving review: an approved major can merge.\n  pull_request_review:\n    types: [submitted]\n  # In case an event was missed.\n  schedule:\n    - cron: '23 12 * * *'\n  workflow_dispatch:\n    inputs:\n      dry_run:\n        description: \"Log what would be merged without writing anything\"\n        type: boolean\n        default: false\n      correlation_id:\n        description: \"Set by Sisyphus to find this run; leave it empty\"\n        type: string\n        required: false\n\npermissions:\n  contents: read\n\n# Dispatches get their own queue: GitHub keeps one pending run per group, so an\n# event run could otherwise replace the dispatch Sisyphus is waiting for.\nconcurrency:\n  group: rolling-maintenance-${{ github.event_name == 'workflow_dispatch' && 'dispatch' || 'events' }}\n  cancel-in-progress: false\n\njobs:\n  roll:\n    uses: linchpin/actions/.github/workflows/rolling-maintenance.yml@v4\n    secrets: inherit\n    with:\n      dry_run: ${{ inputs.dry_run || false }}","highlightedLines":"47-49","showLineNumbers":true,"caption":"The template caller. The @…@ placeholders are filled in by bin/convert-repo."} /-->

The caller keeps the triggers, run name and concurrency. A dispatch returns no run id, so Sisyphus finds its run by the `correlation_id` in the name, and dispatches get their own concurrency group: GitHub keeps one pending run per group, so an event could otherwise replace the dispatch Sisyphus is waiting for.

Pass only the inputs that differ from the defaults, for example a check production requires that never runs on PRs into `maintenance`:

```yaml
jobs:
  roll:
    uses: linchpin/actions/.github/workflows/rolling-maintenance.yml@v4
    secrets: inherit
    with:
      dry_run: ${{ inputs.dry_run || false }}
      skip_checks: npm audit   # required on production, never run into maintenance
```

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Bring production in","content":"\u003cp\u003eFast-forwards \u003ccode\u003emaintenance\u003c/code\u003e to the production branch when it has nothing of its own, otherwise asks GitHub for a merge commit. A deleted \u003ccode\u003emaintenance\u003c/code\u003e is recreated from production, unless \u003ccode\u003emaintenance/YYYY-MM\u003c/code\u003e branches still exist.\u003c/p\u003e"},{"title":"Merge what is green","content":"\u003cp\u003eSquash-merges each open Renovate PR into \u003ccode\u003emaintenance\u003c/code\u003e once every check on its head has finished green, each check production's ruleset requires among them (less \u003ccode\u003eskip_checks\u003c/code\u003e). An \u003ccode\u003eautomerge-safe\u003c/code\u003e PR needs nothing more; any other waits for an approving review.\u003c/p\u003e"},{"title":"Resolve a refused merge","content":"\u003cp\u003eOnly when GitHub refused the first step: checks out \u003ccode\u003emaintenance\u003c/code\u003e and runs resolve-merge from the production branch. It settles manifests and lockfiles, and with \u003ccode\u003epublish_conflicts\u003c/code\u003e publishes any other conflicted file for Sisyphus to answer.\u003c/p\u003e"},{"title":"Try again, or ask a person","content":"\u003cp\u003eRuns the first two steps again knowing the resolver tried. Still refused, it opens one \u003ccode\u003emaintenance-conflict\u003c/code\u003e issue; the run that next brings production in closes it.\u003c/p\u003e"},{"title":"Merge Governing bumps","content":"\u003cp\u003eRuns even when a step above failed, so a release is never held up: governing-merge merges green Linchpin Governing bumps into the production branch.\u003c/p\u003e"},{"title":"Tidy snapshots","content":"\u003cp\u003eOn a push, which is how a merged snapshot arrives, tags the snapshot and deletes its branch.\u003c/p\u003e"}]} /-->

The steps are the composite actions [rolling-maintenance](../composite-actions/rolling-maintenance.md), [resolve-merge](../composite-actions/resolve-merge.md), [governing-merge](../composite-actions/governing-merge.md) and [snapshot](../composite-actions/snapshot.md). [Resolving merges](../guides/resolving-merges.md) covers what the resolver settles and how Sisyphus answers the rest.

## When the job runs

The caller decides which events start the workflow. The job then skips itself, billing nothing, unless the event can change something:

| Event | The job runs when |
| --- | --- |
| `workflow_run` | the run succeeded, was for a `pull_request`, and that PR goes into `maintenance` or comes from a `governing/` branch |
| `pull_request_review` | the review approves a PR into `maintenance` or from a `governing/` branch |
| Any other (the template uses `push`, `schedule` and `workflow_dispatch`) | always |

## Behaviour notes

- **`GH_BOT_TOKEN` is linchpin-bot's PAT.** Its pushes and PRs start other workflows, which `GITHUB_TOKEN`'s do not, and linchpin-bot is exempt from production's ruleset, which governing-merge relies on.
- **Required checks are read from production's ruleset at run time.** A check that runs only on PRs into production, such as linchpin.com's `npm audit`, goes in `skip_checks`, or no update into `maintenance` turns green. The snapshot PR runs it.
- **The job's own check run is never waited for.** GitHub names it `<caller's job> / Rolling maintenance`, and the actions skip any check ending that way when they judge a PR.
- **No checkout, no repository code.** The scripts ship with the actions, so nothing from the site repository, or from a PR whose CI started the run, runs with `GH_BOT_TOKEN`. A checkout happens only to resolve a refused merge.
- **`maintenance` cannot sit beside `maintenance/YYYY-MM`.** Git cannot hold both names, so while a monthly window's branch exists the job refuses to create `maintenance` and fails with ``Cannot create `maintenance` while these branches exist; merge or delete them first: …``. Close the window first; see [The monthly maintenance window](../guides/monthly-maintenance-window.md).
- **A dry run never reaches the resolver.** It logs the merge it would ask GitHub for instead of asking, so nothing conflicts. Snapshot tidying runs only on `push` and is not passed `dry_run`.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"branch","type":"string","required":false,"defaultValue":"maintenance","description":"The maintenance branch","values":"","deprecated":false},{"name":"production_branch","type":"string","required":false,"defaultValue":"","description":"The branch brought into it. Defaults to the repository's default branch","values":"","deprecated":false},{"name":"skip_checks","type":"string","required":false,"defaultValue":"","description":"Checks production requires that never run on PRs into the maintenance branch, one per line","values":"","deprecated":false},{"name":"resolve_conflicts","type":"boolean","required":false,"defaultValue":"true","description":"Hand a refused merge to resolve-merge before opening an issue","values":"","deprecated":false},{"name":"publish_conflicts","type":"boolean","required":false,"defaultValue":"true","description":"Publish files resolve-merge cannot settle for Sisyphus to answer","values":"","deprecated":false},{"name":"governing_merge","type":"boolean","required":false,"defaultValue":"true","description":"Also merge green Linchpin Governing bumps into the production branch","values":"","deprecated":false},{"name":"governing_commit_prefix","type":"string","required":false,"defaultValue":"build(composer):","description":"Type and scope of a merged Governing bump's commit, worded like the repository's Renovate updates","values":"","deprecated":false},{"name":"tidy_snapshots","type":"boolean","required":false,"defaultValue":"true","description":"Tag a snapshot merged into the production branch and delete its branch on the push that merges it","values":"","deprecated":false},{"name":"dry_run","type":"boolean","required":false,"defaultValue":"false","description":"Log what would be merged without writing anything","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"GH_BOT_TOKEN","type":"string","required":true,"defaultValue":"","description":"Bot token for the pushes and pull requests this workflow makes. Not \u003ccode\u003eGITHUB_TOKEN\u003c/code\u003e: a push or pull request made with it triggers no workflows, so required checks never run.","values":"","deprecated":false},{"name":"PACKAGIST_COMPOSER_AUTH_JSON","type":"string","required":false,"defaultValue":"","description":"COMPOSER_AUTH JSON for resolve-merge, for packagist.linchpin.com","values":"","deprecated":false},{"name":"NPM_READ_TOKEN","type":"string","required":false,"defaultValue":"","description":"npm read token for resolve-merge, for private @linchpinagency packages","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `roll` | `contents: read` |

## Source

[`.github/workflows/rolling-maintenance.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/rolling-maintenance.yml)
