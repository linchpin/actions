---
title: Rolling maintenance
---

One permanent `maintenance` branch, never closed and never dated. Renovate raises non-major updates against it; the rolling job brings production in and merges what is green; Sisyphus on packagist.linchpin.com copies production's data to dev each night, deploys `maintenance` there and tests it; and a passing night becomes a snapshot PR that a person merges. Nothing reaches production without that merge and a published release.

<!-- wp:docspress/diagram {"title":"Where each change goes","type":"flow","source":"Renovate -\u003e maintenance: non-major updates, merged when green\nproduction -\u003e maintenance: brought in on every push\nmaintenance -\u003e dev: deployed by Sisyphus each night\ndev -\u003e snapshot PR: a passing night is frozen\nsnapshot PR -\u003e production: merged by a person\nLinchpin Governing -\u003e production: release bumps, merged when green","caption":"Production also takes third-party majors and security fixes directly."} /-->

## What goes where

The site's Renovate config routes non-major updates, lock-file maintenance and the Linchpin packages Linchpin Governing does not watch to `maintenance`. Third-party majors, security fixes and Governing's bumps go to the production branch. [bin/convert-repo](../scripts/convert-repo.md) adds the `github>linchpin/renovatebot-config:rolling-maintenance` preset that does the routing; see [Renovate presets](../renovate-presets.md).

## The three callers

A site repository needs three thin callers, which Sisyphus dispatches by file name. `bin/convert-repo` writes them from [`templates/rolling-maintenance`](https://github.com/linchpin/actions/blob/main/templates/rolling-maintenance).

<!-- wp:docspress/file-tree {"root":".github/","tree":"workflows/\n  maintenance.yml\n  snapshots.yml\n  deploy-dev.yml","caption":"Keep these names: Sisyphus dispatches the files by name."} /-->

| Caller | Calls | Sisyphus dispatches it to | Its own triggers |
| --- | --- | --- | --- |
| `maintenance.yml` | [rolling-maintenance.yml](../workflows/rolling-maintenance.md) | bring production in and merge updates before each nightly deploy | a push to production, CI finishing on `renovate/**` and `governing/**` branches, approving reviews, daily at 12:23 UTC |
| `deploy-dev.yml` | [deploy.yml](../workflows/deploy.md) with dev's environment and `safety_net: true` | deploy `maintenance` to dev | none, so no deploy lands mid-sync |
| `snapshots.yml` | [snapshots.yml](../workflows/snapshots.md) | freeze a passing night, or refresh a promotion's branch | daily tidy at 12:41 UTC |

The callers keep the triggers and the run name, because a dispatch returns no run id: Sisyphus finds its run by the `correlation_id` it puts in the name. They also give a dispatch its own concurrency group. GitHub keeps one pending run per group, so in a single group a push or a finished CI run can replace the dispatch Sisyphus is waiting for, and the night fails as cancelled.

`deploy-dev.yml` is the only one whose template is not shown on its workflow's page:

<!-- wp:docspress/colorful-code {"language":"yaml","filename":".github/workflows/deploy-dev.yml","code":"# Deploy to Dev (linchpin/actions v4)\n#\n# Deploys `maintenance` to dev, where Sisyphus tests each night's copy of\n# production. Sisyphus dispatches this file by name, so keep its name. Never on\n# push, so no deploy lands mid-sync.\n#\n# The @DEV_ENVIRONMENT@ environment holds dev's SITE_ID, SITE_URL and SSH_USER and deploys\n# `maintenance` only. Dev has production's data, so Safety Net goes on first and\n# the deploy fails unless that data is scrubbed. Written by linchpin/actions\n# bin/convert-repo.\n\nname: Deploy to Dev\n\n# Sisyphus finds its dispatch by the correlation_id in the name, which the\n# deployment log also records.\nrun-name: Deploy ${{ github.ref_name }} to dev ${{ inputs.correlation_id }}\n\non:\n  workflow_dispatch:\n    inputs:\n      correlation_id:\n        description: \"Set by Sisyphus to find this run; leave it empty\"\n        type: string\n        required: false\n\nconcurrency:\n  group: deploy-dev\n  cancel-in-progress: false\n\n# The shared build job declares contents: write, and a called workflow cannot\n# exceed its caller's grant.\npermissions:\n  contents: write\n  deployments: write\n\njobs:\n  deploy:\n    name: Deploy to Dev\n    uses: linchpin/actions/.github/workflows/deploy.yml@v4\n    secrets: inherit\n    with:\n      environment: '@DEV_ENVIRONMENT@'\n      correlation_id: ${{ inputs.correlation_id }}\n      safety_net: true","highlightedLines":"32-34","showLineNumbers":true,"caption":"The template caller. bin/convert-repo fills in dev's GitHub environment."} /-->

It grants `contents: write` because the shared build job declares it, and a called workflow cannot exceed its caller's grant. Dev holds production's data, so [Safety Net](safety-net-on-development.md) goes on before the code ships and the deploy fails unless that data is scrubbed.

## A night

Sisyphus itself runs on packagist.linchpin.com, not here. These are the parts of its night the workflows serve:

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Check dev","content":"\u003cp\u003eSisyphus's preflight reads Safety Net's status route on dev over HTTPS. A dev it cannot read fails the night at Preflight.\u003c/p\u003e"},{"title":"Prepare","content":"\u003cp\u003eIt dispatches \u003ccode\u003emaintenance.yml\u003c/code\u003e, which brings production into \u003ccode\u003emaintenance\u003c/code\u003e and merges green updates, and copies production's database and uploads to dev.\u003c/p\u003e"},{"title":"Deploy","content":"\u003cp\u003eIt dispatches \u003ccode\u003edeploy-dev.yml\u003c/code\u003e, which deploys \u003ccode\u003emaintenance\u003c/code\u003e to dev and fails unless every site reports its data scrubbed.\u003c/p\u003e"},{"title":"Test","content":"\u003cp\u003eIt runs the Ghost Inspector suite mapped to dev.\u003c/p\u003e"},{"title":"Freeze","content":"\u003cp\u003eAfter a passing night it dispatches \u003ccode\u003esnapshots.yml\u003c/code\u003e, which freezes the tested commit and opens its PR into the promotion target.\u003c/p\u003e"}]} /-->

## Required checks

Production's required checks govern `maintenance` in two places:

- The rolling job reads production's ruleset at run time and waits for those checks on each Renovate PR, less `skip_checks`.
- `bin/convert-repo` adds a **Green checks into maintenance** ruleset to `maintenance` requiring the same checks, less `--skip-check`, with linchpin-bot exempt.

A check that runs only on PRs into production, such as linchpin.com's `npm audit`, never reports on a PR into `maintenance`, so it has to be left out of both. `--skip-check` shapes only the ruleset; add `skip_checks` to the `maintenance.yml` caller yourself. The snapshot PR still runs the check.

## Snapshots and promotion

- **Freeze.** After a passing night Sisyphus freezes the tested commit as `snapshot/YYYY-MM-DD` and opens its PR into the promotion target: production, or a staging branch that promotes to it. A person approves it and merges it as a **merge commit**, never a squash. Merged into staging, it deploys staging; into production, production moves when the release is published.
- **Supersede and expire.** A newer snapshot into the same target closes the older one, and a snapshot PR left open for 7 days is closed unmerged.
- **Tidy.** The daily run, and the rolling job on each push to production, tag merged snapshots and delete their branches.
- **Refresh.** When a promotion's PR falls behind its target and GitHub's update-branch refuses, typically staging's PR into production after a release moved `composer.json`'s `version` and `composer.lock`'s content-hash, Sisyphus dispatches `snapshots.yml` with `mode: refresh`. It brings the target into the branch with resolve-merge and pushes the branch, which deploys it like any other push. It never pushes to the production branch. A caller from before refresh is updated by running `bin/convert-repo` again.

## Governing bumps

When one of Linchpin's own packages releases, Linchpin Governing opens a bump PR against production. The rolling job merges it once it moves exactly one package production already requires, is not a major unless a person approved it, is level with production and is green. See [governing-merge](../composite-actions/governing-merge.md).

## Conflicts

GitHub's merge API refuses whenever both sides changed neighbouring lines, which on `maintenance` is nearly always a manifest or a lockfile.

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"resolve-merge","content":"\u003cp\u003eSettles \u003ccode\u003epackage.json\u003c/code\u003e, \u003ccode\u003ecomposer.json\u003c/code\u003e and their lockfiles deterministically, commits the merge and pushes it.\u003c/p\u003e"},{"title":"Sisyphus","content":"\u003cp\u003eAny other conflicted file is published to \u003ccode\u003esisyphus/conflicts/&lt;pair&gt;\u003c/code\u003e. Sisyphus answers on \u003ccode\u003esisyphus/resolutions/&lt;pair&gt;\u003c/code\u003e, and a later run applies the answer.\u003c/p\u003e"},{"title":"A person","content":"\u003cp\u003eOnly when both give up does one \u003ccode\u003emaintenance-conflict\u003c/code\u003e issue open. Sisyphus reads that label. The run that next brings production in closes the issue.\u003c/p\u003e"}]} /-->

[Resolving merges](resolving-merges.md) has the rules for each file. Files a model resolved are named in the merge commit and listed at the top of the next snapshot PR, for the person merging to review first.

## Setting a site up

[bin/onboard-site](../scripts/onboard-site.md) does the whole onboarding, with [bin/convert-repo](../scripts/convert-repo.md) as its step 4: dev and staging, the repository conversion, Sisyphus's enrollment, the first Deploy to Dev and the first run. Three things stay with a person: creating dev on Pressable when the client has none, its DNS records, and mapping a Ghost Inspector suite to dev in Sisyphus.

A repository on the monthly window has to leave it first, because Git cannot hold `maintenance` beside `maintenance/YYYY-MM` branches. `bin/convert-repo` closes windows that hold only Renovate's commits and removes the window's workflows; see [The monthly maintenance window](monthly-maintenance-window.md).

## Running the scripts locally

Every script behind these workflows runs locally against the live repository with `gh`'s own login. With `DRY_RUN=true` each logs its writes instead of making them:

<!-- wp:docspress/terminal-session {"title":"What would the rolling job do now?","shell":"bash","prompt":"$","command":"GH_REPO=linchpin/ctoec DRY_RUN=true actions/rolling-maintenance/rolling-maintenance.sh"} /-->

The same works for [snapshot](../composite-actions/snapshot.md) (`snapshot.sh freeze` or `tidy`) and [governing-merge](../composite-actions/governing-merge.md).
