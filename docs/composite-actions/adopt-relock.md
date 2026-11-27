---
title: adopt-relock
---

Locks the `composer.lock` of every branch Sisyphus opened to adopt a plugin production runs outside the repository, then commits and pushes each lock. [rolling-maintenance.yml](../workflows/rolling-maintenance.md) runs it on every run, after [composer-relock](composer-relock.md).

Deploy to Dev fails `wp mantle health` with `Active but not on disk: <slug>` when production runs a plugin that was installed by hand. Sisyphus copies production's database to dev, so dev lists the plugin as active, but only the repository's plugins are deployed. When wp-packages.org serves the version production runs, Sisyphus opens the fix itself: a pull request from `sisyphus/adopt/<slug>` into the production branch, whose `composer.json` requires the plugin at that version. Sisyphus has no Composer, so the pull request's Composer check fails until this action locks the branch.

## Example

```yaml
- uses: actions/checkout@v6
  with:
    ref: maintenance
    path: lock
    token: ${{ secrets.GH_BOT_TOKEN }}

- uses: linchpin/actions/actions/adopt-relock@v4
  with:
    working-directory: lock
    composer-auth: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}
    php-version: ${{ vars.PHP_VERSION }}
```

Any checkout of the repository works, a shallow one included. The token must be able to push to the branches it locks. The checkout is put back on its own branch when the action is done.

## How it works

1. **Find the branches.** `git ls-remote` lists the branches matching `pattern`, `sisyphus/adopt/*` by default. With none, the action stops before setting up PHP.
2. **Lock each one.** It checks the branch out and runs composer-relock's `relock.sh`. That re-locks exactly the packages Composer names, the adopted plugin, with scripts and plugins off, and fails if anything else in the lock would move.
3. **Commit and push.** The subject names the package: `build(composer): Lock wp-plugin/example-plugin at 1.2.3`. A branch whose lock already agrees is left alone, so each branch is locked once.
4. **Keep going.** A branch Composer cannot lock gets a warning with Composer's reason, in the log and the step summary, and the next branch is tried. A person reads the failing check on the pull request.

Nothing here merges: a person reviews and merges the pull request, since the change reaches production too.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"working-directory","type":"string","required":false,"defaultValue":".","description":"A checkout of the repository, with push credentials. Its branch is put back when this is done","values":"","deprecated":false},{"name":"pattern","type":"string","required":false,"defaultValue":"sisyphus/adopt/*","description":"The branches to lock, as a git ref pattern under refs/heads/","values":"","deprecated":false},{"name":"dry-run","type":"string","required":false,"defaultValue":"false","description":"Lock in the checkout, but commit and push nothing (true/false)","values":"","deprecated":false},{"name":"composer-auth","type":"string","required":false,"defaultValue":"","description":"COMPOSER_AUTH JSON, for private Composer repositories such as packagist.linchpin.com","values":"","deprecated":false},{"name":"php-version","type":"string","required":false,"defaultValue":"","description":"PHP version Composer runs on. Empty falls back to composer.json's config.platform.php, then the runner's own","values":"","deprecated":false},{"name":"git-user-name","type":"string","required":false,"defaultValue":"linchpin-bot","description":"Author of the lock commits","values":"","deprecated":false},{"name":"git-user-email","type":"string","required":false,"defaultValue":"81971745+linchpin-bot@users.noreply.github.com","description":"Author email of the lock commits","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Outputs

<!-- wp:docspress/fields {"title":"Outputs","fields":[{"name":"branches","type":"string","required":false,"defaultValue":"","description":"The branches found, one per line","values":"","deprecated":false},{"name":"locked","type":"string","required":false,"defaultValue":"","description":"What was locked, one 'branch name old new' per line","values":"","deprecated":false}],"searchable":true,"compact":false} /-->
