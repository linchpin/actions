---
title: Renovate presets
---

This repository carries four Renovate configuration files. The presets the maintenance tooling actually adds to a site live in a different repository, [linchpin/renovatebot-config](https://github.com/linchpin/renovatebot-config).

## Presets the tooling adds

| Preset | Added by | Does |
| --- | --- | --- |
| `github>linchpin/renovatebot-config:rolling-maintenance` | [`bin/convert-repo`](scripts/convert-repo.md) | Routes non-major updates to the permanent `maintenance` branch for [rolling maintenance](guides/rolling-maintenance.md) |
| `github>linchpin/renovatebot-config:maintenance-window` | Added by hand. `bin/convert-repo` removes it when it converts a repository | Keeps majors out of a [monthly window](guides/monthly-maintenance-window.md), so each major gets its own PR against the default branch |

`bin/convert-repo` edits `renovate.json` or `.github/renovate.json`. A repository whose config is `renovate.json5`, `.renovaterc` or `.renovaterc.json` gets an instruction to add the preset by hand instead.

## Files in this repository

| File | Sets |
| --- | --- |
| [`global.json`](https://github.com/linchpin/actions/blob/main/global.json) | Extends `config:base`, `:preserveSemverRanges` and `:disableRateLimiting`; base branch `staging`; separate PRs for major, minor and patch; schedule after 6pm and before 6am on weekdays and all weekend (America/New_York); groups npm, Composer and GitHub Actions updates as "Managers"; labels majors `major` and vulnerability alerts `security` |
| [`wordpress.json`](https://github.com/linchpin/actions/blob/main/wordpress.json) | Labels WordPress updates; groups `wpackagist-plugin/`, `wpackagist-theme/` and `linchpin/` packages as "WordPress Plugins and Themes" |
| [`js.json`](https://github.com/linchpin/actions/blob/main/js.json) | Adds the `js` label to npm updates and enables npm minor updates |
| [`renovate.json`](https://github.com/linchpin/actions/blob/main/renovate.json) | The config Renovate reads for this repository. It is shaped like a site's: base branches matching `maintenance/*`, npm and Composer groups for the project root, `themes/**` and `plugins/**`, lockfile maintenance, `rangeStrategy: bump`, and `node`, `npm` and `php` updates disabled |

Renovate loads a named file from a GitHub repository as `github>owner/repo:name`. That would make the first three `github>linchpin/actions:global`, `:wordpress` and `:js`. Nothing in this repository adds them to a site, and its tooling names `linchpin/renovatebot-config` instead, so treat these files as legacy and check that repository before extending them.
