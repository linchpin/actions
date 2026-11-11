---
title: Choosing a runner
---

Every job in a shared workflow runs on the same expression:

```yaml
runs-on: ${{ inputs.runner || vars.RUNNER || 'ubuntu-latest' }}
```

So each job takes the first of these that is set: the workflow's `runner` input, the `RUNNER` variable (repository, then organization), then `ubuntu-latest`. Set `RUNNER` on a repository to move all of its shared jobs at once. Use the input to override it for one caller.

## Size the build separately

`deploy.yml` also takes `build_runner` and forwards it to `build.yml`, so the build can run on a bigger machine than the deploy job, which mostly waits on SSH:

```yaml
jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: staging
      build_runner: blacksmith-4vcpu-ubuntu-2404
```

`build_runner` falls back to `runner`, and then to the same `RUNNER` → `ubuntu-latest` chain.

## Blacksmith and Depot

Blacksmith and Depot runners register as self-hosted, so `shivammathur/setup-php` installs any PHP the image lacks through apt instead of unpacking a prebuilt build. That takes a minute or more for PHP 8.5, and about two minutes a job on Blacksmith. [`setup-wp-php`](../composite-actions/setup-wp-php.md), `php-checks.yml` and `validate-composer.yml` turn on setup-php's experimental `use_builds_cache` when the runner's name starts with `blacksmith-` or `depot-`. That gets the prebuilt PHP back. The check is on the runner name because the option fails the step on any other self-hosted runner. On GitHub-hosted runners it changes nothing.

`plugin-check.yml` can skip PHP entirely. Pass it a prebuilt zip with `artifact` and it skips the checkout, PHP, Node and build steps. See [`plugin-check.yml`](../workflows/plugin-check.md).

## Workflows that ignore it

This repository's own `ci.yml`, `release.yml` and `sync-docs.yml`, and the `composer-bump.yml` workflow that Linchpin Governing dispatches, run on `ubuntu-latest`. None of them is called from a site repository.
