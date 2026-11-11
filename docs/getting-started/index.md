---
title: Call a shared workflow
---

A site or plugin repository uses linchpin/actions through short caller workflows: a few lines that set the trigger, the permissions and the concurrency, and hand the job to a reusable workflow here. This page covers what every caller needs.

## Pin the major tag

Reference workflows and actions at `@v4`:

```yaml
jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: staging
```

`v4` is a tag, not a branch. release-please cuts an immutable `vX.Y.Z` release from `main`, and when it publishes, [`release.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/release.yml) moves `v4` to that release. `@v4` therefore always runs the latest v4 release, the same contract GitHub's own actions use. To hold a repository still, pin an exact release such as `@v4.22.0`.

The composite actions reference each other at `@v4` too, so pinning the workflow pins everything it runs. No script is fetched from a branch at run time.

`v3` is a separate branch that receives only fixes. Moving a repository from `@v3`, `@v2` or `@main` is covered in [Migrating from v3 to v4](../MIGRATION-v3-to-v4.md).

## Pass secrets

Every reusable workflow declares the secrets it reads, which documents the contract. `secrets: inherit` passes all of the caller's secrets, organization secrets included, and is what most callers use. A caller that passes secrets one by one has to pass each one the workflow declares and the caller relies on. For example, `deploy.yml` declares `SATISPRESS_USER` and `SATISPRESS_PASSWORD` for the remote plugin install.

```yaml
jobs:
  lint:
    uses: linchpin/actions/.github/workflows/lint.yml@v4
    secrets:
      PACKAGIST_COMPOSER_AUTH_JSON: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}
```

[Secrets and variables](secrets-and-variables.md) lists every one.

## Grant permissions

A called workflow can only lower the permissions its caller grants, and GitHub checks the whole call tree before the run starts. A caller that grants too little fails at once:

```text
the nested job 'build' is requesting 'contents: write', but is only allowed 'contents: read'
```

That example is a production deploy: `deploy.yml` calls `build.yml`, which needs `contents: write` to attach `release.zip` to the release. Each workflow page has a **Permissions** table with what its jobs request.

## Serialize deploys

Add a workflow-level concurrency group to every deploy caller, and never cancel a deploy in progress:

```yaml
concurrency:
  group: deploy-production
  cancel-in-progress: false
```

The deploy job also serializes per environment. The caller's group stops a second run of the same caller from queueing behind the first one.

## Pick a runner

Every job runs on the `runner` input, else the `RUNNER` variable, else `ubuntu-latest`. See [Choosing a runner](choosing-a-runner.md).

## Wire up a site

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Set variables and secrets","content":"\u003cp\u003eOn each GitHub environment, set \u003ccode\u003eHOST\u003c/code\u003e, \u003ccode\u003eSITE_URL\u003c/code\u003e and the host's id variable, plus the SSH and Composer secrets.\u003c/p\u003e"},{"title":"Check pull requests","content":"\u003cp\u003eAdd a CI caller for \u003ccode\u003elint.yml\u003c/code\u003e on a site, or for \u003ccode\u003ephp-checks.yml\u003c/code\u003e and \u003ccode\u003eplugin-check.yml\u003c/code\u003e on a plugin.\u003c/p\u003e"},{"title":"Deploy","content":"\u003cp\u003eAdd a staging caller on push, a production caller on \u003ccode\u003erelease: published\u003c/code\u003e, and a rollback caller.\u003c/p\u003e"},{"title":"Maintain","content":"\u003cp\u003eMove the repository onto rolling maintenance with \u003ccode\u003ebin/onboard-site\u003c/code\u003e.\u003c/p\u003e"}]} /-->

Each step has its own page: [Secrets and variables](secrets-and-variables.md), [PR checks](../guides/pr-checks.md), [Deploy a site](../guides/deploy-a-site.md) and [Rolling maintenance](../guides/rolling-maintenance.md).

## Use a composite action directly

The actions under [`actions/`](https://github.com/linchpin/actions/tree/main/actions) are steps, not jobs. Use one in your own job when no workflow fits:

```yaml
steps:
  - uses: actions/checkout@v7
  - uses: linchpin/actions/actions/setup-wp-php@v4
    with:
      php-version: "8.4"
      composer-auth: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}
```

The [composite actions index](../composite-actions/index.md) lists them.
