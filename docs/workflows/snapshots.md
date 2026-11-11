---
title: snapshots.yml
---

How the `maintenance` branch reaches production or staging. `freeze` cuts `snapshot/YYYY-MM-DD` at one tested commit of `maintenance` and opens its PR into the target, which a person merges. `tidy` tags merged snapshots and closes stale ones. `refresh` brings a promotion's target back into its branch when GitHub's **Update branch** refuses. Nothing here merges a PR, and production still moves only when the release is published.

Sisyphus dispatches the site's own `snapshots.yml` by name, to freeze after a passing night and to refresh. Its daily schedule tidies. [Rolling maintenance](../guides/rolling-maintenance.md) explains the model around it.

## Example

This is the caller [bin/convert-repo](../scripts/convert-repo.md) writes from [`templates/rolling-maintenance/snapshots.yml`](https://github.com/linchpin/actions/blob/main/templates/rolling-maintenance/snapshots.yml). It fills in the production branch, the promotion target, and the targets the site uses.

<!-- wp:docspress/colorful-code {"language":"yaml","filename":".github/workflows/snapshots.yml","code":"# Snapshots (linchpin/actions v4)\n#\n# Freezes a tested commit of `maintenance` as snapshot/YYYY-MM-DD and opens its\n# PR into @PROMOTION_TARGET@ for a person to merge. Sisyphus dispatches this file by name\n# after a passing night, so keep its name; the daily run tidies merged and stale\n# snapshots. Sisyphus also dispatches it to refresh a promotion's branch (head)\n# from the branch it goes into (base) when GitHub cannot update it, which a\n# push to head then deploys like any other. Written by linchpin/actions\n# bin/convert-repo.\n\nname: Snapshots\n\nrun-name: \u003e-\n  ${{ github.event_name != 'workflow_dispatch' && 'Tidy snapshots'\n  || inputs.mode == 'refresh' && format('Refresh {0} from {1} {2}', inputs.head, inputs.base, inputs.correlation_id)\n  || inputs.mode == 'tidy' && format('Tidy snapshots {0}', inputs.correlation_id)\n  || format('Freeze a snapshot into {0} {1}', inputs.target, inputs.correlation_id) }}\n\non:\n  workflow_dispatch:\n    inputs:\n      mode:\n        description: \"freeze a snapshot, refresh head from base, or tidy\"\n        type: choice\n        options: ['freeze', 'refresh', 'tidy']\n        default: 'freeze'\n      target:\n        description: \"Branch the snapshot PR goes into\"\n        type: choice\n        options: ['@SNAPSHOT_TARGETS@']\n        default: '@PROMOTION_TARGET@'\n      sha:\n        description: \"Commit of maintenance to freeze (the head of maintenance when empty)\"\n        type: string\n        required: false\n      head:\n        description: \"refresh: the branch to bring base into, like staging (never @PRODUCTION_BRANCH@)\"\n        type: string\n        required: false\n      base:\n        description: \"refresh: the branch brought in (@PRODUCTION_BRANCH@ when empty)\"\n        type: string\n        required: false\n      dry_run:\n        description: \"Log what would be frozen, closed or pushed without writing anything\"\n        type: boolean\n        default: false\n      correlation_id:\n        description: \"Set by Sisyphus to find this run; leave it empty\"\n        type: string\n        required: false\n  schedule:\n    - cron: '41 12 * * *'\n\npermissions:\n  contents: read\n\n# A freeze and the daily tidy queue apart.\nconcurrency:\n  group: snapshots-${{ github.event_name }}\n  cancel-in-progress: false\n\njobs:\n  snapshot:\n    uses: linchpin/actions/.github/workflows/snapshots.yml@v4\n    secrets: inherit\n    with:\n      mode: ${{ inputs.mode }}\n      target: ${{ inputs.target }}\n      sha: ${{ inputs.sha }}\n      head: ${{ inputs.head }}\n      base: ${{ inputs.base }}\n      dry_run: ${{ inputs.dry_run || false }}","highlightedLines":"","showLineNumbers":true,"caption":"The template caller. The @…@ placeholders are filled in by bin/convert-repo."} /-->

## How it works

`mode` defaults to `tidy` on a schedule and `freeze` otherwise.

| `mode` | What it does |
| --- | --- |
| `freeze` | Runs [snapshot](../composite-actions/snapshot.md) `freeze`: a branch at `sha` (the head of `maintenance` when empty), a PR into `target` (production when empty), and the older open snapshot PR into the same target closed |
| `tidy` | Runs snapshot `tidy`: merged snapshots tagged, closed ones' branches deleted, PRs open longer than `max_age_days` closed |
| `refresh` | Brings `base` (production when empty) into `head` with [resolve-merge](../composite-actions/resolve-merge.md), and pushes `head` |

Merge a snapshot PR as a **merge commit**, never a squash, so each update keeps its own changelog line. A snapshot into staging deploys staging when merged; one into production waits for the release.

### Refresh

A promotion's PR falls behind its target and GitHub's update-branch refuses, typically staging's PR into production after a release moved `composer.json`'s `version` and `composer.lock`'s content-hash.

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Check the branches","content":"\u003cp\u003eThrough the API, before any checkout. Fails when \u003ccode\u003ehead\u003c/code\u003e is empty, is the production branch, or equals \u003ccode\u003ebase\u003c/code\u003e. A \u003ccode\u003ehead\u003c/code\u003e that already has every commit of \u003ccode\u003ebase\u003c/code\u003e is done, and \u003ccode\u003erefreshed\u003c/code\u003e is true.\u003c/p\u003e"},{"title":"Check out head","content":"\u003cp\u003eFull history, blobless, with \u003ccode\u003eGH_BOT_TOKEN\u003c/code\u003e, because the merge is pushed.\u003c/p\u003e"},{"title":"Bring base in","content":"\u003cp\u003eresolve-merge settles manifests and lockfiles, commits the merge and pushes \u003ccode\u003ehead\u003c/code\u003e. On a dry run it commits in the checkout and pushes nothing.\u003c/p\u003e"},{"title":"Fail when it could not","content":"\u003cp\u003eresolve-merge gives up without failing, so this step fails the run, naming the files it left.\u003c/p\u003e"}]} /-->

The push to `head` starts that branch's own workflows: a push to staging deploys staging. A refresh never pushes to the production branch, which moves only by a PR.

With `publish_conflicts`, a file other than a manifest or lockfile is published to `sisyphus/conflicts/<pair>` for Sisyphus to answer, and a later refresh applies the answer. It is off by default, and the template caller does not set it, so a refresh the template runs fails on any such file.

| Error | Meaning |
| --- | --- |
| `refresh needs head, the branch to bring <base> into.` | No `head` was given |
| `refresh never pushes to the production branch (<production>); it moves only by a PR.` | `head` is the production branch |
| `head and base are both <branch>.` | Nothing to bring in |
| `Not refreshed: <reason> (files: <files>)` | resolve-merge gave up; the step summary says why |

## Behaviour notes

- **`GH_BOT_TOKEN` is linchpin-bot's PAT**, so the PRs it opens run CI and its pushes start the head branch's workflows. `GITHUB_TOKEN` would do neither.
- **No checkout for freeze and tidy.** They run through the API alone, so no repository code runs with the token.
- **Snapshots can target any branch** other than `maintenance`: production, or a staging branch that promotes to it. The caller's `target` choice lists the ones the site uses.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"mode","type":"string","required":false,"defaultValue":"","description":"freeze, tidy or refresh. Defaults to tidy on a schedule and freeze otherwise","values":"","deprecated":false},{"name":"target","type":"string","required":false,"defaultValue":"","description":"freeze: the branch the snapshot PR goes into. Defaults to the production branch","values":"","deprecated":false},{"name":"sha","type":"string","required":false,"defaultValue":"","description":"freeze: the commit of the maintenance branch to freeze. Defaults to its head","values":"","deprecated":false},{"name":"head","type":"string","required":false,"defaultValue":"","description":"refresh: the branch to bring \u003ccode\u003ebase\u003c/code\u003e into, such as staging or a snapshot branch. Never the production branch","values":"","deprecated":false},{"name":"base","type":"string","required":false,"defaultValue":"","description":"refresh: the branch brought into \u003ccode\u003ehead\u003c/code\u003e. Defaults to the production branch","values":"","deprecated":false},{"name":"publish_conflicts","type":"boolean","required":false,"defaultValue":"false","description":"refresh: publish files resolve-merge cannot settle to sisyphus/conflicts/&lt;pair&gt; for Sisyphus to answer; a later refresh applies the answers","values":"","deprecated":false},{"name":"branch","type":"string","required":false,"defaultValue":"maintenance","description":"The maintenance branch","values":"","deprecated":false},{"name":"production_branch","type":"string","required":false,"defaultValue":"","description":"The branch production releases from. Defaults to the repository's default branch","values":"","deprecated":false},{"name":"max_age_days","type":"number","required":false,"defaultValue":"7","description":"tidy: close a snapshot PR left open longer than this","values":"","deprecated":false},{"name":"dry_run","type":"boolean","required":false,"defaultValue":"false","description":"Log what would be frozen, closed or pushed without writing anything","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"GH_BOT_TOKEN","type":"string","required":true,"defaultValue":"","description":"Bot token for the pushes and pull requests this workflow makes. Not \u003ccode\u003eGITHUB_TOKEN\u003c/code\u003e: a push or pull request made with it triggers no workflows, so required checks never run.","values":"","deprecated":false},{"name":"PACKAGIST_COMPOSER_AUTH_JSON","type":"string","required":false,"defaultValue":"","description":"refresh: COMPOSER_AUTH JSON for resolve-merge, for packagist.linchpin.com","values":"","deprecated":false},{"name":"NPM_READ_TOKEN","type":"string","required":false,"defaultValue":"","description":"refresh: npm read token for resolve-merge, for private @linchpinagency packages","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Outputs

<!-- wp:docspress/fields {"title":"Outputs","fields":[{"name":"branch","type":"string","required":false,"defaultValue":"","description":"freeze: the snapshot branch it cut","values":"","deprecated":false},{"name":"pr","type":"string","required":false,"defaultValue":"","description":"freeze: the number of the PR it opened","values":"","deprecated":false},{"name":"refreshed","type":"string","required":false,"defaultValue":"","description":"refresh: true when \u003ccode\u003ehead\u003c/code\u003e now contains \u003ccode\u003ebase\u003c/code\u003e, whether it was merged or already did","values":"","deprecated":false},{"name":"sha","type":"string","required":false,"defaultValue":"","description":"refresh: the merge commit it pushed, empty when there was nothing to bring in","values":"","deprecated":false},{"name":"unresolved","type":"string","required":false,"defaultValue":"","description":"refresh: space-separated files resolve-merge could not settle","values":"","deprecated":false},{"name":"conflicts_branch","type":"string","required":false,"defaultValue":"","description":"refresh: the branch the unsettled files were published to, with publish_conflicts","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `snapshot` | `contents: read` |
| `refresh` | `contents: read` |

## Source

[`.github/workflows/snapshots.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/snapshots.yml)
