---
title: README updates
---

release-please bumps the version in every file its config names, but not arbitrary strings such as a release date or the list of plugins the release ships. [update-readme.yml](../workflows/update-readme.md) fills those in on the release PR's branch, so the README that merges with a release describes that release.

## Add the markers

Put either or both marker pairs in the project's `README.md`. Whatever sits between them is replaced on every release.

<!-- wp:docspress/colorful-code {"language":"markdown","filename":"README.md","code":"Released \u003c!-- x-linchpin-release-date-start --\u003e01/01/2026\u003c!-- x-linchpin-release-date-end --\u003e\n\n## Plugins\n\n\u003c!-- x-linchpin-plugin-list-start --\u003e\n\u003c!-- x-linchpin-plugin-list-end --\u003e","highlightedLines":"1,5-6","showLineNumbers":false,"caption":"Each pair of markers is replaced on every release. Keep the date markers on one line."} /-->

| Markers | Replaced with |
| --- | --- |
| `<!-- x-linchpin-release-date-start -->` … `<!-- x-linchpin-release-date-end -->` | The date of the run, as `MM/DD/YYYY`. Both markers on one line. |
| `<!-- x-linchpin-plugin-list-start -->` … `<!-- x-linchpin-plugin-list-end -->` | A `Plugin Name` / `Version` table of every `wordpress-plugin` and `wordpress-theme` package in `composer.lock`, whatever its vendor. |

Everything outside the markers is left exactly as it was. The [update-readme](../composite-actions/update-readme.md) action page shows a real before and after.

## Call it from the release workflow

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

`secrets: inherit` passes `GH_BOT_TOKEN`, which is required, and `PACKAGIST_COMPOSER_AUTH_JSON`, which the lock re-sync needs when the project pulls from `packagist.linchpin.com`.

## Why `prs_created`

release-please rebuilds its branch from the default branch whenever the release notes change, which drops anything committed on top of it, and `prs_created` is true exactly then. Two other gates look reasonable and fail:

- **On `composer.lock` changing**: the README commit is dropped by release-please's next rewrite.
- **On `release_created`**: the commit lands on a branch that has already merged.

linchpin.com did both, and its README date stood still for 24 releases.

## What lands on the release branch

One commit, `Update README.md plugin list and sync composer.lock`, by Linchpin Bot, touching only `README.md` and `composer.lock`, pushed straight onto the release PR's branch. No pull request is opened. When neither file changed, nothing is committed.

- **The lock is re-synced** because release-please bumps `version` in `composer.json`, which Composer's content-hash covers, so `composer validate` would fail on the release branch. The re-sync is best effort: when it cannot resolve, it logs `composer update --lock failed; leaving composer.lock unchanged` and the README update still goes ahead.
- **The message is not a conventional commit**, so a release PR merged with a merge commit does not list it in the next release's notes.
- **The push is never forced.** If release-please rewrote the branch in the meantime, the push fails, and the run that rewrote it regenerates the README.

## Why `GH_BOT_TOKEN`

The branch is checked out and pushed with `GH_BOT_TOKEN`. A push made with `GITHUB_TOKEN` starts no workflow, so the release PR's new head would have no check runs and a required check would wait on it forever.
