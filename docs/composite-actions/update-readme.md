---
title: update-readme
---

Rewrites `README.md` in the working directory from `composer.lock`: today's date between the release-date markers, and a table of every WordPress plugin and theme between the plugin-list markers. It takes no inputs. [update-readme.yml](../workflows/update-readme.md) runs it on release-please's branch and commits the result.

## Example

```yaml
steps:
  - uses: actions/checkout@v6
  - uses: linchpin/actions/actions/update-readme@v4
```

## How it works

Given a README with both marker pairs:

<!-- wp:docspress/colorful-code {"language":"markdown","filename":"README.md","code":"Released \u003c!-- x-linchpin-release-date-start --\u003e01/01/2026\u003c!-- x-linchpin-release-date-end --\u003e\n\n## Plugins\n\n\u003c!-- x-linchpin-plugin-list-start --\u003e\n\u003c!-- x-linchpin-plugin-list-end --\u003e","highlightedLines":"1,5-6","showLineNumbers":false,"caption":"Each pair of markers is replaced on every release. Keep the date markers on one line."} /-->

and a `composer.lock` holding two plugins, a theme and a Composer plugin, running the script produced:

```markdown
Released <!-- x-linchpin-release-date-start -->11/05/2026<!-- x-linchpin-release-date-end -->

## Plugins

<!-- x-linchpin-plugin-list-start -->
| Plugin Name | Version |
|------|---------|
| mantle | 3.4.0 |
| twentytwentyfive | 1.3 |
| wordpress-seo | 26.3 |
<!-- x-linchpin-plugin-list-end -->
```

1. **Date.** The runner's current date, as `MM/DD/YYYY`, replaces whatever sits between the release-date markers. Both markers have to be on one line.
2. **Table.** Every package of type `wordpress-plugin` or `wordpress-theme`, whatever its vendor, sorted case-insensitively by the name after the vendor prefix. Themes share the table, under the `Plugin Name` heading, and other package types such as `composer-plugin` are left out.
3. **Splice.** Everything between the plugin-list markers is replaced; markers on one line get the table between them. Everything outside the markers is written back exactly as read, blank lines included.

## Behaviour notes

- **Nothing to list, nothing touched.** Without a `composer.lock`, the script prints `Note: composer.lock not found.` and only the date changes. A lock with no plugins or themes leaves the table as it was.
- **A start marker with no end marker** leaves the rest of the file as it was rather than dropping it.
- **It needs `jq` and `awk`** on the runner.
- It writes only `README.md`; committing is the caller's job.

See [README updates](../guides/readme-updates.md) for wiring it into a release.

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/update-readme/action.yml), [`update-readme.sh`](https://github.com/linchpin/actions/blob/main/actions/update-readme/update-readme.sh)
