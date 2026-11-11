---
title: resolve-merge
---

Brings one branch into the checked-out branch when GitHub's merge API refuses. It resolves the conflicts that dependency updates leave in `package.json`, `composer.json`, `package-lock.json` and `composer.lock` the way a person would, then commits and pushes the merge. Anything it cannot resolve by those rules is reported and left alone. With `publish-conflicts`, any other conflicted file goes to Sisyphus to answer. [rolling-maintenance.yml](../workflows/rolling-maintenance.md) runs it to bring production into `maintenance`, and [snapshots.yml](../workflows/snapshots.md) runs it in `refresh` mode. [Resolving merge conflicts](../guides/resolving-merges.md) has the rules, the reasons it gives up, and the Sisyphus hand-off.

## Example

```yaml
- uses: actions/checkout@v6
  with:
    ref: maintenance
    path: work
    fetch-depth: 0
    filter: blob:none
    token: ${{ secrets.GH_BOT_TOKEN }}

- id: resolve
  uses: linchpin/actions/actions/resolve-merge@v4
  with:
    working-directory: work
    from: origin/main
    branch: maintenance
    composer-auth: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}
    npm-token: ${{ secrets.NPM_READ_TOKEN }}

- if: steps.resolve.outputs.resolved != 'true'
  env:
    REASON: ${{ steps.resolve.outputs.reason }}
    UNRESOLVED: ${{ steps.resolve.outputs.unresolved }}
  run: echo "Left for a person: $REASON ($UNRESOLVED)"
```

The checkout needs full history (`fetch-depth: 0`) and a token that can push to `branch`. With `publish-conflicts: true` that token also pushes `sisyphus/conflicts/*`.

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Set up the tools","content":"\u003cp\u003eNode at \u003ccode\u003enode-version\u003c/code\u003e for npm, and PHP with Composer. An empty \u003ccode\u003ephp-version\u003c/code\u003e reuses the runner's own PHP version, read with \u003ccode\u003ephp -r\u003c/code\u003e.\u003c/p\u003e"},{"title":"Start the merge","content":"\u003cp\u003e\u003ccode\u003egit merge --no-ff --no-commit\u003c/code\u003e with the diff3 conflict style. When git merges cleanly, even though GitHub refused, there is nothing to resolve.\u003c/p\u003e"},{"title":"Settle other files first","content":"\u003cp\u003eA conflicted file that is not a manifest or lockfile takes Sisyphus's answer for this exact pair of commits. Without one, it gives up, publishing the conflicts first when \u003ccode\u003epublish-conflicts\u003c/code\u003e is \u003ccode\u003etrue\u003c/code\u003e.\u003c/p\u003e"},{"title":"Resolve manifests and lockfiles","content":"\u003cp\u003eManifests merge by key, then npm lockfiles by package entry, repaired and checked with npm. \u003ccode\u003ecomposer.lock\u003c/code\u003e keeps this side's lock and re-applies what the other side moved.\u003c/p\u003e"},{"title":"Commit and push","content":"\u003cp\u003eThe commit message is \u003ccode\u003eMerge branch '&lt;from&gt;' into &lt;branch&gt;\u003c/code\u003e, with one line per file it resolved. It is pushed unless \u003ccode\u003edry-run\u003c/code\u003e is set. A successful push deletes both Sisyphus hand-off branches.\u003c/p\u003e"}]} /-->

## Behaviour notes

- **Giving up is an answer, not a failure.** The step still succeeds, with the warning `The merge was not resolved; see the step summary for why.` and `resolved` set to `false`. Read `resolved` and decide what happens next. snapshots.yml fails its run. rolling-maintenance.yml opens a `maintenance-conflict` issue.
- **Nothing from either branch runs.** npm and Composer run with scripts and plugins off, since the job holds a token that can push.
- **`npm-token`** is written to a temporary npm config for `registry.npmjs.org` only. **`composer-auth`** is passed as `COMPOSER_AUTH`.
- **`dry-run: true`** resolves and commits in the checkout and pushes nothing. `resolved` is `true` when the push would have happened. `publish-conflicts` then only reports which branch it would publish.
- **`from`** defaults to `origin/` plus the event repository's default branch.
- **The merge commit** is authored and committed as `git-user-name` and `git-user-email`, which default to `linchpin-bot`.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"from","type":"string","required":false,"defaultValue":"","description":"The ref to bring in. Defaults to the repository's default branch on origin.","values":"","deprecated":false},{"name":"branch","type":"string","required":false,"defaultValue":"","description":"The branch to push the merge to. Defaults to the checked-out branch.","values":"","deprecated":false},{"name":"working-directory","type":"string","required":false,"defaultValue":".","description":"The checkout to resolve in","values":"","deprecated":false},{"name":"dry-run","type":"string","required":false,"defaultValue":"false","description":"Resolve and commit in the checkout, but push nothing (true/false)","values":"","deprecated":false},{"name":"publish-conflicts","type":"string","required":false,"defaultValue":"false","description":"When a file other than a manifest or lockfile conflicts, push the conflicted files to sisyphus/conflicts/&lt;pair&gt; for Sisyphus to answer (true/false)","values":"","deprecated":false},{"name":"composer-auth","type":"string","required":false,"defaultValue":"","description":"COMPOSER_AUTH JSON, for private Composer repositories such as packagist.linchpin.com","values":"","deprecated":false},{"name":"npm-token","type":"string","required":false,"defaultValue":"","description":"An npm read token, for private npm packages","values":"","deprecated":false},{"name":"node-version","type":"string","required":false,"defaultValue":"24","description":"Node version npm repairs lockfiles with","values":"","deprecated":false},{"name":"php-version","type":"string","required":false,"defaultValue":"","description":"PHP version Composer runs on. Defaults to the runner's own: Composer only resolves, and composer.json's config.platform pins what it resolves for.","values":"","deprecated":false},{"name":"git-user-name","type":"string","required":false,"defaultValue":"linchpin-bot","description":"Author of the merge commit","values":"","deprecated":false},{"name":"git-user-email","type":"string","required":false,"defaultValue":"81971745+linchpin-bot@users.noreply.github.com","description":"Author email of the merge commit","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Outputs

<!-- wp:docspress/fields {"title":"Outputs","fields":[{"name":"resolved","type":"string","required":false,"defaultValue":"","description":"true when the merge was resolved and pushed (or committed, on a dry run)","values":"","deprecated":false},{"name":"sha","type":"string","required":false,"defaultValue":"","description":"The merge commit","values":"","deprecated":false},{"name":"reason","type":"string","required":false,"defaultValue":"","description":"Why it gave up","values":"","deprecated":false},{"name":"unresolved","type":"string","required":false,"defaultValue":"","description":"Space-separated files it could not resolve, for a fallback or a person","values":"","deprecated":false},{"name":"conflicts-branch","type":"string","required":false,"defaultValue":"","description":"The branch it published the conflicts to, when it did","values":"","deprecated":false},{"name":"model-resolved","type":"string","required":false,"defaultValue":"","description":"Space-separated files it took Sisyphus's answer for, to review","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/resolve-merge/action.yml), [`resolve-merge.sh`](https://github.com/linchpin/actions/blob/main/actions/resolve-merge/resolve-merge.sh)
