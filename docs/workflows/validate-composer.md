---
title: validate-composer.yml
---

A pull-request gate that fails when a `composer.lock` can no longer be installed against its `composer.json`: someone changed a constraint without rebuilding the lock. Without it, that failure surfaces when the production deploy's build runs `composer install`, after release-please has already cut and published the tag.

## Example

```yaml
name: Validate Composer
on:
  pull_request:
    paths:
      - "composer.json"
      - "composer.lock"
      - "themes/*/composer.*"
      - "plugins/*/composer.*"

permissions:
  contents: read

jobs:
  composer:
    uses: linchpin/actions/.github/workflows/validate-composer.yml@v4
    secrets:
      PACKAGIST_COMPOSER_AUTH_JSON: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}
```

## How it works

1. Install PHP: `php_version`, else `vars.PHP_VERSION`, else 8.5.
2. For the repository root and every `themes/*` and `plugins/*` directory that has both a `composer.json` and a `composer.lock`, run `composer install --no-dev --dry-run --no-interaction --no-progress`. Nothing is written to `vendor/`.
3. Try every directory, report each one that fails, and fail the job if any did.

## Behaviour notes

- **Why not `composer validate`.** release-please bumps `version` in `composer.json` on every release without rebuilding the lock. `composer validate` treats that content-hash mismatch as an error and would fail every release PR; `composer install` warns and succeeds, and fails only on a lock that genuinely cannot be satisfied. The gate therefore mirrors the build.
- **`--no-dev` matches the release build.** Dev-only drift does not break a deploy.
- **Private packages need the secret.** `PACKAGIST_COMPOSER_AUTH_JSON` reaches Composer as `COMPOSER_AUTH`, so nothing is written to an `auth.json`.

## Errors

A failing directory is reported as:

```text
composer.lock in '<dir>' can no longer be installed against its composer.json (a locked version no longer satisfies a constraint). Run 'composer update' in <dir> and commit the lock.
```

See [Dependency checks](../guides/dependency-checks.md) for how this pairs with the npm overrides check.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"php_version","type":"string","required":false,"defaultValue":"","description":"PHP version. Defaults to vars.PHP_VERSION, then 8.5","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"PACKAGIST_COMPOSER_AUTH_JSON","type":"string","required":false,"defaultValue":"","description":"auth.json for packagist.linchpin.com (passed via COMPOSER_AUTH; needed to resolve private packages)","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `validate` | `contents: read` |

## Source

[`.github/workflows/validate-composer.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/validate-composer.yml)
