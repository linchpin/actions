---
title: governing-merge
---

Merges Linchpin Governing's release bumps into the production branch once they are level with it and green. When one of Linchpin's own packages publishes a release, Linchpin Governing on packagist.linchpin.com opens a PR against production from `governing/bump-<slug>-<version>` that changes `composer.json` and `composer.lock`. Renovate does not raise those packages, so this is the only way they arrive, and no person reviews each one: the code was reviewed in its own repository, CI still runs here, and production still moves only when a person merges the release PR.

[rolling-maintenance.yml](../workflows/rolling-maintenance.md) runs it on every event its job handles, unless `governing_merge` is off.

## Example

```yaml
steps:
  - uses: linchpin/actions/actions/governing-merge@v4
    with:
      token: ${{ secrets.GH_BOT_TOKEN }}
      commit-prefix: 'build(composer):'
```

The token's user must be exempt from the production branch's ruleset, as linchpin-bot is. That exemption is why it can merge without a review, and why the script checks the ruleset's conditions itself first.

## What it merges

A PR merges only when all of these hold:

- `linchpin-packagist[bot]` opened it from a `governing/bump-*` branch, labelled `automated`, and it is not a draft.
- It changes `composer.json` and `composer.lock` and nothing else.
- It moves exactly one `require` or `require-dev` entry production already had (adding a package is a scope change), and its lock moves that package alone.
- It is not a major, where the leading version number changes, unless a person approved it. A 0.x minor such as 0.23 to 0.24 is not a major here.
- It is up to date with production, and every check on its head is green, each check production's ruleset requires among them.

Anything else is left for a person, and the run summary says which rule it failed.

## How it works

| The PR | What it does |
| --- | --- |
| GitHub has not worked out whether it merges | Looks again on the next run |
| Conflicts, usually because another bump merged first and moved `composer.lock`'s content-hash | Comments `@linchpin-packagist rebase` once per head commit, asking Governing to regenerate the lock against production. `recreate` when the only other commits are the token user's own updates from production; nothing when a person has committed. |
| Behind production | Updates the branch, so CI runs again |
| Checks pending or red | Waits |
| Green | Squash-merges it as `<commit-prefix> Update dependency <package> to v<version> (#N)` |

Governing reads those comments within about fifteen minutes. Either way a later run merges the PR. The squash commit is worded like the repository's Renovate updates (`commit-prefix`) so release-please files it in the same section.

## Run it locally

<!-- wp:docspress/terminal-session {"title":"Dry run against a live repository","shell":"bash","prompt":"$","command":"GH_REPO=linchpin/linchpin.com DRY_RUN=true actions/governing-merge/governing-merge.sh"} /-->

It reads `GH_REPO` (required), `GH_TOKEN` (`gh`'s own login otherwise), `DRY_RUN`, `PRODUCTION_BRANCH`, `COMMIT_PREFIX` and `SELF_CHECK`. Set `PRS` to space-separated PR numbers to judge those PRs whatever their state; it forces `DRY_RUN`.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"token","type":"string","required":true,"defaultValue":"","description":"Token for the GitHub API","values":"","deprecated":false},{"name":"repository","type":"string","required":false,"defaultValue":"${{ github.repository }}","description":"owner/name. Defaults to the repository the workflow runs in","values":"","deprecated":false},{"name":"production-branch","type":"string","required":false,"defaultValue":"","description":"The branch Governing's PRs go into. Defaults to the default branch","values":"","deprecated":false},{"name":"commit-prefix","type":"string","required":false,"defaultValue":"build(composer):","description":"The squash commit's type and scope, worded like the repository's Renovate updates so release-please files it with them","values":"","deprecated":false},{"name":"self-check","type":"string","required":false,"defaultValue":"Rolling maintenance","description":"The calling job's name, whose own check run is never waited for","values":"","deprecated":false},{"name":"dry-run","type":"string","required":false,"defaultValue":"false","description":"Log every write instead of making it (true/false)","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/governing-merge/action.yml), [`governing-merge.sh`](https://github.com/linchpin/actions/blob/main/actions/governing-merge/governing-merge.sh)
