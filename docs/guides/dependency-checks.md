---
title: Dependency checks
---

Two checks catch dependency drift that would otherwise surface later and somewhere worse. [validate-composer.yml](../workflows/validate-composer.md) fails a pull request whose `composer.lock` no longer installs; [check-overrides.yml](../workflows/check-overrides.md) reports, on a schedule, npm `overrides` pins that have stopped doing anything.

| Check | Run it | Fails | Finds |
| --- | --- | --- | --- |
| `validate-composer.yml` | On pull requests | Yes | A lock a constraint change has left unsatisfiable |
| `check-overrides.yml` | Monthly, on a schedule | No, unless `fail_on_redundant` | Overrides that are redundant or dangling |

## Composer locks on pull requests

Someone tightens a constraint in `composer.json` and forgets to rebuild the lock. Nothing notices until the production deploy runs `composer install` and exits non-zero, after release-please has already cut and published the tag. This gate runs the same install as a dry run on the PR:

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

It checks the root and every `themes/*` and `plugins/*` package with its own lock, because the build installs each of those too. It deliberately avoids `composer validate`, which fails every release PR on the content-hash change release-please's version bump causes. The fix for a failure is in its message: run `composer update` in the named directory and commit the lock.

## npm overrides on a schedule

Transitive advisories in build tooling get pinned with npm `overrides`, because the dependents keep declaring a vulnerable range long after a fix ships. Nothing then says when upstream catches up, so pins accumulate, and each one is a silent veto on a dependency the rest of the tree wants to move.

Point the check at every npm project in the repository, on a schedule:

```yaml
name: Check npm overrides
on:
  schedule:
    - cron: "0 9 1 * *" # 09:00 UTC on the 1st
  workflow_dispatch:

permissions:
  contents: read
  issues: write

jobs:
  overrides:
    uses: linchpin/actions/.github/workflows/check-overrides.yml@v4
    with:
      directories: |
        .
        themes/my-theme
        plugins/my-functionality
        plugins/my-functionality/blocks
      open_issue: true
```

Each override is removed from a scratch copy of the manifest on its own, the graph is re-resolved, and the result is compared with the pin:

| Finding | Meaning | Usually |
| --- | --- | --- |
| `STILL NEEDED` | Without it, the package drops below the pin somewhere in the tree | Keep it |
| `REDUNDANT` | The tree already resolves at or above the pin without it | Review, then remove unless it is a deliberate floor |
| `DANGLING` | The package has left the tree | Remove it |

With `open_issue: true`, one issue titled **Removable npm overrides** tracks the removable pins: updated while there are any, closed once there are none. The full table is in each run's summary and in the `npm-overrides-report` artifact.

<!-- wp:docspress/callout {"tone":"warning","title":"Redundant is not the same as safe to delete","content":"\u003cp\u003eAn override added to hold a security floor still guards against a future downgrade after the tree catches up. Treat a finding as a prompt to review the pin, not an instruction to remove it.\u003c/p\u003e","collapsible":false} /-->

The [check-overrides](../composite-actions/check-overrides.md) action does the probing, and runs locally too: `node actions/check-overrides/check-overrides.mjs <dir>` from a checkout of this repository.

Routine version updates are Renovate's job; see [Renovate presets](../renovate-presets.md).
