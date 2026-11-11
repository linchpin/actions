---
title: rolling-maintenance
---

The two hops behind [rolling-maintenance.yml](../workflows/rolling-maintenance.md): bring the production branch into the maintenance branch, then squash-merge green Renovate PRs into it. It needs no checkout. It works through the GitHub API with a token that can push to the branch, merge PRs and open issues, and whose writes start other workflows: a PAT such as `GH_BOT_TOKEN`, not `GITHUB_TOKEN`.

Use the reusable workflow. Call the action directly only to build a different job around it.

## Example

The reusable workflow runs it twice when GitHub refuses the merge: once to find the conflict, and again after [resolve-merge](resolve-merge.md) has tried.

```yaml
steps:
  - id: roll
    uses: linchpin/actions/actions/rolling-maintenance@v4
    with:
      token: ${{ secrets.GH_BOT_TOKEN }}
      resolver: true

  - if: steps.roll.outputs.conflict == 'true'
    uses: actions/checkout@v6
    with:
      ref: maintenance
      path: work
      fetch-depth: 0
      filter: blob:none
      token: ${{ secrets.GH_BOT_TOKEN }}

  - if: steps.roll.outputs.conflict == 'true'
    uses: linchpin/actions/actions/resolve-merge@v4
    with:
      working-directory: work
      from: origin/main
      branch: maintenance

  - if: steps.roll.outputs.conflict == 'true'
    uses: linchpin/actions/actions/rolling-maintenance@v4
    with:
      token: ${{ secrets.GH_BOT_TOKEN }}
      resolver: tried
```

## Hop 1: production into the branch

| State | What happens |
| --- | --- |
| The branch does not exist | Created from production, and the run ends there. It fails instead while any `maintenance/…` branch exists, since Git cannot hold both names. |
| Not behind production | Nothing to bring in |
| Behind, with nothing of its own | Fast-forwarded to production |
| Behind and ahead | GitHub makes a merge commit, `Merge branch '<production>' into maintenance` |
| GitHub refuses (HTTP 409) | `resolver: true` sets the `conflict` output. `tried` or `false` opens one issue labelled `maintenance-conflict`, titled `Bring <production> into maintenance by hand`, unless one is already open. |
| Any other merge error | The step fails with GitHub's answer |

Once production is in again, the open `maintenance-conflict` issue is closed. Sisyphus reads that label, so it is not an input.

## Hop 2: green Renovate PRs into the branch

Each open, non-draft PR from `renovate[bot]` into the branch is judged in turn:

1. **Its checks.** Green means every check run on its head finished as success, skipped or neutral, and every check production's ruleset requires, less `skip-checks`, is among them. The calling job's own check (`self-check`) is ignored.
2. **A stale red.** When the checks are red and the branch has since moved under the PR by anything but another Renovate update (production coming in, a person's fix, a merge resolve-merge pushed), it ticks the PR's Renovate rebase box so Renovate rebases it and CI runs again. It never pushes to the PR, since Renovate abandons a PR with a commit it does not recognise, and it leaves alone a PR someone else pushed to.
3. **Approval.** A PR not labelled `automerge-safe` waits until a person has approved it and nobody's latest review asks for changes.
4. **The merge.** A green PR is squash-merged at the head it was judged on. A merge that fails, because the PR conflicts or was pushed since, is left for Renovate to rebase.

There are no other rules. A PR need not be up to date with the branch, because the snapshot PR checks the combination.

## Run it locally

`rolling-maintenance.sh` runs against the live repository with `gh`'s own login, and logs every write instead of making it when `DRY_RUN=true`:

<!-- wp:docspress/terminal-session {"title":"Dry run against a live repository","shell":"bash","prompt":"$","command":"GH_REPO=linchpin/ctoec DRY_RUN=true actions/rolling-maintenance/rolling-maintenance.sh"} /-->

It reads `GH_REPO` (required), `GH_TOKEN`, `DRY_RUN`, `MAINTENANCE_BRANCH`, `PRODUCTION_BRANCH`, `BRANCH_SKIPS_CHECKS`, `SELF_CHECK` and `LOCK_RESOLVER`, which are the inputs below under the names the action passes them as.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"token","type":"string","required":true,"defaultValue":"","description":"Token for the GitHub API","values":"","deprecated":false},{"name":"repository","type":"string","required":false,"defaultValue":"${{ github.repository }}","description":"owner/name. Defaults to the repository the workflow runs in","values":"","deprecated":false},{"name":"branch","type":"string","required":false,"defaultValue":"maintenance","description":"The maintenance branch","values":"","deprecated":false},{"name":"production-branch","type":"string","required":false,"defaultValue":"","description":"The branch brought into it, whose ruleset names the required checks. Defaults to the default branch","values":"","deprecated":false},{"name":"skip-checks","type":"string","required":false,"defaultValue":"","description":"Checks the production branch requires that never run on a PR into the maintenance branch, one per line","values":"","deprecated":false},{"name":"self-check","type":"string","required":false,"defaultValue":"Rolling maintenance","description":"The calling job's name, whose own check run is never waited for","values":"","deprecated":false},{"name":"resolver","type":"string","required":false,"defaultValue":"false","description":"true hands a refused merge to resolve-merge through the conflict output; tried says resolve-merge already gave up, so the issue opens; false opens the issue at once","values":"","deprecated":false},{"name":"dry-run","type":"string","required":false,"defaultValue":"false","description":"Log every write instead of making it (true/false)","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Outputs

<!-- wp:docspress/fields {"title":"Outputs","fields":[{"name":"conflict","type":"string","required":false,"defaultValue":"","description":"true when GitHub refused to bring the production branch in and resolver was true","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/rolling-maintenance/action.yml), [`rolling-maintenance.sh`](https://github.com/linchpin/actions/blob/main/actions/rolling-maintenance/rolling-maintenance.sh)
