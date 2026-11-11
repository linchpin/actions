---
title: snapshot
---

The freeze and tidy halves of [snapshots.yml](../workflows/snapshots.md). It works through the GitHub API alone, with no checkout, using a token whose PRs run CI: a PAT such as `GH_BOT_TOKEN`, not `GITHUB_TOKEN`. It never merges anything. `refresh` is not part of the action; it is a job in the workflow.

## Example

```yaml
steps:
  - id: freeze
    uses: linchpin/actions/actions/snapshot@v4
    with:
      token: ${{ secrets.GH_BOT_TOKEN }}
      mode: freeze
      target: staging

  - if: steps.freeze.outputs.pr != ''
    run: echo "Opened #${{ steps.freeze.outputs.pr }} from ${{ steps.freeze.outputs.branch }}"
```

## Freeze

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Check the target","content":"\u003cp\u003eIt must be an existing branch other than the maintenance branch.\u003c/p\u003e"},{"title":"Check the commit","content":"\u003cp\u003e\u003ccode\u003esha\u003c/code\u003e, or the head of the maintenance branch when empty, must be on the maintenance branch. Only a commit of it can be promoted.\u003c/p\u003e"},{"title":"List the updates","content":"\u003cp\u003eThe commits the target lacks, leaving out merge commits such as production coming in. When there are none, it stops: nothing to promote, and no outputs.\u003c/p\u003e"},{"title":"Cut the snapshot","content":"\u003cp\u003eNames it \u003ccode\u003esnapshot/YYYY-MM-DD\u003c/code\u003e in UTC, or \u003ccode\u003e-2\u003c/code\u003e, \u003ccode\u003e-3\u003c/code\u003e when a branch or tag already holds the name. Creates the branch and opens its PR into the target, labelled \u003ccode\u003emaintenance\u003c/code\u003e.\u003c/p\u003e"},{"title":"Close the older one","content":"\u003cp\u003eEvery older open snapshot PR into the same target gets a comment, \u003ccode\u003eSuperseded by #N.\u003c/code\u003e, and is closed with its branch deleted.\u003c/p\u003e"}]} /-->

The PR is titled `chore(NO-TASK): Promote the YYYY-MM-DD maintenance snapshot into <target>`. Its body lists the updates, says to merge it as a merge commit, and carries the frozen commit as a hidden `snapshot-commit: <sha>` marker, which Sisyphus reads and tidy tags. The marker is why **Update branch** is safe: the tag still marks the frozen commit. When files were resolved by a model while production was brought into `maintenance`, the body opens with a warning listing them, for the person merging to review first.

It is `snapshot/…` and not `maintenance/YYYY-MM-DD` because Git cannot hold that name beside `maintenance`.

| Error | Meaning |
| --- | --- |
| ``SNAPSHOT_TARGET must be a branch other than `maintenance`; `<target>` is not.`` | The target is the maintenance branch or does not exist |
| `` `<sha>` (<commit>) is not on `maintenance`; nothing frozen. `` | The commit is not on the maintenance branch |

## Tidy

Each `snapshot/` branch is handled by the state of its PR:

| State | Tidy |
| --- | --- |
| Merged | Deletes the branch, then tags the frozen commit with the branch's name. A tag beside a branch of the same name would make the name ambiguous, so the branch goes first. |
| Closed unmerged | Deletes the branch |
| Open longer than `max-age-days` | Comments `Closed unmerged after N days. Freeze a newer passing night when it is ready.`, closes it, deletes the branch |
| Open, younger | Reports it with its age |
| No PR (a freeze that stopped before opening it) | Deletes the branch once its date is older than `max-age-days` |

A merged snapshot whose branch someone deleted by hand still gets its tag. Only `snapshot/` branches are ever deleted.

## Run it locally

`snapshot.sh` takes the mode as its argument and logs every write instead of making it when `DRY_RUN=true`. Any other argument prints `Usage: snapshot.sh freeze|tidy` and exits 2.

<!-- wp:docspress/terminal-session {"title":"Freeze, as a dry run","shell":"bash","prompt":"$","command":"GH_REPO=linchpin/linchpin.com DRY_RUN=true actions/snapshot/snapshot.sh freeze"} /-->

<!-- wp:docspress/terminal-session {"title":"Tidy, as a dry run","shell":"bash","prompt":"$","command":"GH_REPO=linchpin/linchpin.com DRY_RUN=true actions/snapshot/snapshot.sh tidy"} /-->

It reads `GH_REPO` (required), `GH_TOKEN` (`gh`'s own login otherwise), `DRY_RUN`, `SNAPSHOT_TARGET`, `SNAPSHOT_SHA`, `SNAPSHOT_MAX_AGE_DAYS`, `MAINTENANCE_BRANCH` and `PRODUCTION_BRANCH`.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"token","type":"string","required":true,"defaultValue":"","description":"Token for the GitHub API","values":"","deprecated":false},{"name":"mode","type":"string","required":true,"defaultValue":"","description":"freeze or tidy","values":"","deprecated":false},{"name":"repository","type":"string","required":false,"defaultValue":"${{ github.repository }}","description":"owner/name. Defaults to the repository the workflow runs in","values":"","deprecated":false},{"name":"target","type":"string","required":false,"defaultValue":"","description":"freeze: the branch the snapshot PR goes into. Defaults to the production branch","values":"","deprecated":false},{"name":"sha","type":"string","required":false,"defaultValue":"","description":"freeze: the commit of the maintenance branch to freeze. Defaults to its head","values":"","deprecated":false},{"name":"branch","type":"string","required":false,"defaultValue":"maintenance","description":"The maintenance branch","values":"","deprecated":false},{"name":"production-branch","type":"string","required":false,"defaultValue":"","description":"The branch production releases from. Defaults to the default branch","values":"","deprecated":false},{"name":"max-age-days","type":"string","required":false,"defaultValue":"7","description":"tidy: close a snapshot PR left open longer than this","values":"","deprecated":false},{"name":"dry-run","type":"string","required":false,"defaultValue":"false","description":"Log every write instead of making it (true/false)","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Outputs

<!-- wp:docspress/fields {"title":"Outputs","fields":[{"name":"branch","type":"string","required":false,"defaultValue":"","description":"freeze: the snapshot branch it cut","values":"","deprecated":false},{"name":"pr","type":"string","required":false,"defaultValue":"","description":"freeze: the number of the PR it opened","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/snapshot/action.yml), [`snapshot.sh`](https://github.com/linchpin/actions/blob/main/actions/snapshot/snapshot.sh)
