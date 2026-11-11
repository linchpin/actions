---
title: check-overrides.yml
---

Reports npm `overrides` pins that no longer do anything, across every npm project in a repository, and optionally keeps one tracking issue in sync. Pins added to dodge a transitive advisory are never removed on their own, because nothing says when upstream catches up; this does. It reports and, by default, never fails.

## Example

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
      # A wp-content-shaped repo usually has several npm projects.
      directories: |
        .
        themes/my-theme
        plugins/my-functionality
        plugins/my-functionality/blocks
      open_issue: true
```

## How it works

1. Check out the repository.
2. Probe every override with the [check-overrides](../composite-actions/check-overrides.md) action, on Node `node_version`, else `vars.NODE_VERSION`, else 24. Removable pins become notice annotations, and the full table goes to the run summary.
3. Upload `overrides-report.json` as the `npm-overrides-report` artifact, kept for 30 days, whatever the outcome.
4. With `open_issue: true`, sync one issue titled **Removable npm overrides** carrying `issue_label`: update it, or create it, while anything is removable; comment and close it once nothing is.

<!-- wp:docspress/callout {"tone":"warning","title":"Redundant is not the same as safe to delete","content":"\u003cp\u003eAn override added to hold a security floor still guards against a future downgrade after the tree catches up. Treat a finding as a prompt to review the pin, not an instruction to remove it.\u003c/p\u003e","collapsible":false} /-->

## Behaviour notes

- **One issue, not one a month.** The issue is found by its exact title and label and edited in place, so a scheduled run over an unchanged set of pins changes nothing.
- **The label is not created.** It is passed to `gh issue create --label`, so use one the repository has; `dependencies` is the default.
- **`issues: write` is declared even when `open_issue` is false,** so the calling job must grant it.
- **A probe that errors never fails the job.** It becomes a warning annotation. The composite action's `fail-on-error` is not exposed here.
- `fail_on_redundant: true` turns the report into a gate. It is off by default because a redundant override can still be wanted as a security floor.

See [Dependency checks](../guides/dependency-checks.md) for what each finding means and when to act on it.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"directories","type":"string","required":false,"defaultValue":".","description":"Newline-separated list of directories to check, each with a package.json and package-lock.json. Defaults to the repository root.","values":"","deprecated":false},{"name":"node_version","type":"string","required":false,"defaultValue":"","description":"Node version. Defaults to vars.NODE_VERSION, then 24","values":"","deprecated":false},{"name":"fail_on_redundant","type":"boolean","required":false,"defaultValue":"false","description":"Fail the job when an override is redundant or dangling","values":"","deprecated":false},{"name":"open_issue","type":"boolean","required":false,"defaultValue":"false","description":"Open (or update) a single tracking issue listing removable overrides, and close it once there are none. Intended for scheduled runs.","values":"","deprecated":false},{"name":"issue_label","type":"string","required":false,"defaultValue":"dependencies","description":"Label used to find and mark the tracking issue","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `check-overrides` | `contents: read`, `issues: write` |

## Source

[`.github/workflows/check-overrides.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/check-overrides.yml)
