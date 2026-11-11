---
title: update-readme.yml
---

Regenerates the README's release date and plugin/theme table on release-please's PR branch, re-syncs `composer.lock` there, and commits both onto that branch, so they merge with the release PR and reach the default branch with the release itself.

## Example

Call it every time release-please writes its PR, from the action's `prs_created` output:

```yaml
jobs:
  release-please:
    runs-on: ubuntu-latest
    outputs:
      prs_created: ${{ steps.release.outputs.prs_created }}
    steps:
      - id: release
        uses: googleapis/release-please-action@v5
        with:
          token: ${{ secrets.GH_BOT_TOKEN }}

  update-readme:
    needs: [release-please]
    if: ${{ needs.release-please.outputs.prs_created == 'true' }}
    uses: linchpin/actions/.github/workflows/update-readme.yml@v4
    secrets: inherit
```

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Check out the release branch","content":"\u003cp\u003eA sparse checkout of \u003ccode\u003eREADME.md\u003c/code\u003e, \u003ccode\u003ecomposer.json\u003c/code\u003e and \u003ccode\u003ecomposer.lock\u003c/code\u003e on \u003ccode\u003ebase\u003c/code\u003e, with \u003ccode\u003eGH_BOT_TOKEN\u003c/code\u003e.\u003c/p\u003e"},{"title":"Re-sync composer.lock","content":"\u003cp\u003e\u003ccode\u003ecomposer update --lock --no-install --no-scripts --no-plugins --no-audit --no-interaction\u003c/code\u003e. Best effort: on failure the lock is restored and the run continues with a warning.\u003c/p\u003e"},{"title":"Regenerate the README","content":"\u003cp\u003eThe \u003ccode\u003eupdate-readme\u003c/code\u003e composite action rewrites the release date and the plugin table.\u003c/p\u003e"},{"title":"Commit onto the branch","content":"\u003cp\u003eOne commit, \u003ccode\u003eUpdate README.md plugin list and sync composer.lock\u003c/code\u003e, pushed to \u003ccode\u003ebase\u003c/code\u003e without force. Nothing changed means nothing is committed.\u003c/p\u003e"}]} /-->

## Behaviour notes

- **Gate on `prs_created`, nothing else.** release-please rebuilds its branch from the default branch whenever the release notes change, which drops anything committed on top, and `prs_created` is true exactly then. Gated on `composer.lock` changing, the README is dropped by the next rewrite; gated on `release_created`, it lands on a branch that has already merged. linchpin.com did both, and its README date stood still for 24 releases.
- **`GH_BOT_TOKEN`, not `GITHUB_TOKEN`.** A push made with `GITHUB_TOKEN` starts no workflow, so the release PR's new head would have no check runs and a required check would wait on it forever. The job's own token only reads.
- **Not a conventional commit, on purpose.** A release PR merged with a merge commit would otherwise list it in the next release's notes.
- **No force push.** If release-please rewrote the branch after the checkout, the push fails, and the run that rewrote it regenerates the README.
- **Why the lock is re-synced.** release-please bumps `version` in `composer.json`, which Composer's content-hash covers, so `composer validate` fails on the release branch until something re-locks it. A failed re-lock, for example `packagist.linchpin.com` answering 401 without `PACKAGIST_COMPOSER_AUTH_JSON`, logs `composer update --lock failed; leaving composer.lock unchanged` and the README update goes ahead.
- **`base` defaults to `release-please--branches--main`.** Set it when release-please's branch has another name, as it will on a repository whose default branch is not `main`.

See [README updates](../guides/readme-updates.md) for the markers the README needs.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"base","type":"string","required":false,"defaultValue":"release-please--branches--main","description":"The release PR's branch, which the README is committed onto","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"GH_BOT_TOKEN","type":"string","required":true,"defaultValue":"","description":"Token the README commit is pushed with","values":"","deprecated":false},{"name":"PACKAGIST_COMPOSER_AUTH_JSON","type":"string","required":false,"defaultValue":"","description":"auth.json contents for packagist.linchpin.com, which the composer.lock sync resolves against","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `update-readme` | `contents: read` |

## Source

[`.github/workflows/update-readme.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/update-readme.yml)
