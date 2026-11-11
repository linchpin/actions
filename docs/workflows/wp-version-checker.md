---
title: wp-version-checker.yml
---

Opens an issue when a plugin's `Tested up to` header falls behind the current WordPress release. It wraps [`skaut/wordpress-version-checker`](https://github.com/skaut/wordpress-version-checker), SHA-pinned at v2.2.3 because it receives a token with `issues: write`, so the pin lives in one place.

## Example

Schedule it. A push trigger re-checked the same header about 46 times in 8 days.

```yaml
name: WordPress version check
on:
  schedule:
    - cron: "0 9 * * 1"   # any schedule; this is Mondays 09:00 UTC
  workflow_dispatch:

permissions:
  contents: read
  issues: write

jobs:
  wp-version-checker:
    uses: linchpin/actions/.github/workflows/wp-version-checker.yml@v4
```

## How it works

One step: the checker runs with the job's `GITHUB_TOKEN`, compares the plugin's `Tested up to` with the latest WordPress release, and opens an issue when it is behind.

The workflow takes no input besides `runner`. The checker reads its configuration from `wordpress-version-checker.json` in the calling repository, or the same key in `composer.json` or `package.json`; see the action's own documentation for the format.

See [PR checks](../guides/pr-checks.md) for the rest of the plugin set.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `check` | `contents: read`, `issues: write` |

## Source

[`.github/workflows/wp-version-checker.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/wp-version-checker.yml)
