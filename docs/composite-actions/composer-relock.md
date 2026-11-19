---
title: composer-relock
---

Repairs a branch whose `composer.lock` no longer agrees with its `composer.json`, then commits and pushes the lock. [rolling-maintenance.yml](../workflows/rolling-maintenance.md) runs it on `maintenance` on every run, and [resolve-merge](resolve-merge.md) runs its script after resolving a `composer.lock`.

A commit that changes `composer.json` without its lock breaks every build after it. `composer install` refuses with `Required package "linchpin/mantle" is in the lock file as "4.6.1" but that does not satisfy your constraint "4.6.2"`. Renovate makes one when its lock update fails, and a repository with `ignoreTests` merges it anyway. A merge GitHub makes cleanly then carries it to the other branch, because git sees no conflict in a lock nobody touched. On 2026-11-19 that stopped three sites, two at Deploy to Dev and one at Update.

## Example

```yaml
- uses: actions/checkout@v6
  with:
    ref: maintenance
    path: lock
    token: ${{ secrets.GH_BOT_TOKEN }}

- uses: linchpin/actions/actions/composer-relock@v4
  with:
    working-directory: lock
    branch: maintenance
    composer-auth: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}
    php-version: ${{ vars.PHP_VERSION }}
```

The token must be able to push to `branch`. History is not needed.

## How it works

1. **Ask Composer what is wrong.** `composer validate` lists each package the lock holds at a version `composer.json` refuses, or does not hold at all. A lock with none of those, and a current content-hash, is left alone.
2. **Re-lock exactly those packages.** It runs `composer update <names> --no-install`, with scripts and plugins off, because the job holds a token that can push. A lock that lacks only a fresh content-hash gets `composer update --lock` instead.
3. **Check nothing else moved.** It fails if any other package in the lock changed version, appeared or went, or if `composer validate` still finds the lock wrong. The lock is then put back as it was and nothing is pushed.
4. **Commit and push.** The commit names each package and the versions it moved between. The subject is `commit-message`.

`relock.sh` runs locally too. In a checkout, `bash actions/composer-relock/relock.sh .` re-locks in place and prints one `name old new` line per package.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"working-directory","type":"string","required":false,"defaultValue":".","description":"The checkout to repair","values":"","deprecated":false},{"name":"directories","type":"string","required":false,"defaultValue":".","description":"Directories inside the checkout holding a composer.json and composer.lock to check, one per line","values":"","deprecated":false},{"name":"branch","type":"string","required":false,"defaultValue":"","description":"The branch to push the repair to. Defaults to the checked-out branch","values":"","deprecated":false},{"name":"dry-run","type":"string","required":false,"defaultValue":"false","description":"Re-lock in the checkout, but commit and push nothing (true/false)","values":"","deprecated":false},{"name":"composer-auth","type":"string","required":false,"defaultValue":"","description":"COMPOSER_AUTH JSON, for private Composer repositories such as packagist.linchpin.com","values":"","deprecated":false},{"name":"php-version","type":"string","required":false,"defaultValue":"","description":"PHP version Composer runs on. Empty falls back to composer.json's config.platform.php, then the runner's own","values":"","deprecated":false},{"name":"commit-message","type":"string","required":false,"defaultValue":"build(composer): Re-lock composer.lock to match composer.json","description":"Subject of the repair commit","values":"","deprecated":false},{"name":"git-user-name","type":"string","required":false,"defaultValue":"linchpin-bot","description":"Author of the repair commit","values":"","deprecated":false},{"name":"git-user-email","type":"string","required":false,"defaultValue":"81971745+linchpin-bot@users.noreply.github.com","description":"Author email of the repair commit","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Outputs

| Output | Holds |
| --- | --- |
| `relocked` | `true` when a lock was repaired and pushed, or repaired in the checkout on a dry run |
| `packages` | What was re-locked, one `<lock>: name old new` per line |
| `sha` | The repair commit |

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/composer-relock/action.yml), [`relock.sh`](https://github.com/linchpin/actions/blob/main/actions/composer-relock/relock.sh)
