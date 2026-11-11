---
title: check-overrides
---

Probes each entry in a `package.json` `overrides` block and reports whether it is still needed, redundant, or dangling. [check-overrides.yml](../workflows/check-overrides.md) wraps it with a tracking issue; use the action directly in any job that already has the repository checked out.

## Example

```yaml
steps:
  - uses: actions/checkout@v7

  - id: overrides
    uses: linchpin/actions/actions/check-overrides@v4
    with:
      # Whole-line comments and blank lines are dropped.
      directories: |
        .
        themes/my-theme

  - if: steps.overrides.outputs.removable-count != '0'
    run: echo "${{ steps.overrides.outputs.removable-count }} override(s) look removable"
```

## How it works

For each directory, the action skips it, and says why, when there is no `package.json`, no `package-lock.json`, or no `overrides` block. Otherwise it probes every override on its own, in a scratch directory:

1. Copy the manifest with that one override removed, and the lockfile beside it.
2. Re-resolve with `npm install --package-lock-only --ignore-scripts --no-audit --no-fund`. `--package-lock-only` resolves the graph without downloading `node_modules`; `--ignore-scripts` stops a `prepare` hook such as husky failing the install and masking every result as an error.
3. Find every resolved version of the package in the new lock, and compare each against the pin.

| Finding | Meaning |
| --- | --- |
| `STILL NEEDED` | Without the override, the package would drop below the pin at one or more tree positions. |
| `REDUNDANT` | Every position already resolves at or above the pin without it. |
| `DANGLING` | The package is no longer in the dependency tree at all. |
| `ERROR` | The re-resolve failed; the first lines of npm's error are reported. |

The project itself is never modified.

<!-- wp:docspress/terminal-session {"title":"Probe two directories from a checkout of linchpin/actions","shell":"bash","prompt":"$","command":"node actions/check-overrides/check-overrides.mjs proj empty","output":"proj  REDUNDANT     ansi-styles              already resolves to 4.1.0 without the override\nproj  STILL NEEDED  ms                       would drop to 2.1.2 at 1 tree position(s)\nproj  DANGLING      left-pad                 not in the dependency tree at all\n\n## npm overrides staleness\n\n**2 override(s) look removable** — 1 redundant, 1 dangling. 1 still doing work."} /-->

That run used a demo project depending on `chalk@4.1.2` and `debug@4.3.4`, with overrides for `ansi-styles`, `ms` and `left-pad`, beside an empty directory. The rest of the output is the Markdown table that also goes to the run summary, with `empty` listed as skipped for having no `package.json`.

<!-- wp:docspress/callout {"tone":"warning","title":"Redundant is not the same as safe to delete","content":"\u003cp\u003eAn override added to hold a security floor still guards against a future downgrade after the tree catches up. Treat a finding as a prompt to review the pin, not an instruction to remove it.\u003c/p\u003e","collapsible":false} /-->

## Behaviour notes

- **Outputs and annotations.** The four counts are written as step outputs. Each redundant or dangling override becomes a `Removable override` notice, and each probe error an `Override probe failed` warning. The report is appended to the job summary, and to `json-out` as JSON when that is set.
- **Reports, never fails, by default.** `fail-on-redundant: true` exits 1 with `<n> override(s) look removable.`; `fail-on-error: true` exits 1 with `<n> override probe(s) failed.`
- **Comparison is major.minor.patch.** Prerelease suffixes are ignored, and an override key such as `ajv@8` is matched by its bare package name.
- **Node is installed by the action**, at `node-version`.
- `directories` must name at least one directory, or the action fails with `No directories to check`.

The script also runs outside Actions: `node actions/check-overrides/check-overrides.mjs <dir> [<dir> ...]` from a checkout of this repository.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"directories","type":"string","required":false,"defaultValue":".","description":"Newline-separated list of directories to check, each containing a package.json and package-lock.json. Monorepo-shaped WordPress projects usually have several (root, theme, functionality plugin, blocks).","values":"","deprecated":false},{"name":"node-version","type":"string","required":false,"defaultValue":"24","description":"Node version used to resolve the dependency graphs","values":"","deprecated":false},{"name":"fail-on-redundant","type":"string","required":false,"defaultValue":"false","description":"Fail the job when any override is redundant or dangling (true/false). Off by default: this is a hygiene signal, not a gate.","values":"","deprecated":false},{"name":"fail-on-error","type":"string","required":false,"defaultValue":"false","description":"Fail the job when an override probe itself errors (true/false)","values":"","deprecated":false},{"name":"json-out","type":"string","required":false,"defaultValue":"","description":"Optional path to write the machine-readable results to","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Outputs

<!-- wp:docspress/fields {"title":"Outputs","fields":[{"name":"removable-count","type":"string","required":false,"defaultValue":"","description":"Number of overrides that are redundant or dangling","values":"","deprecated":false},{"name":"redundant-count","type":"string","required":false,"defaultValue":"","description":"Number of overrides the tree already satisfies","values":"","deprecated":false},{"name":"dangling-count","type":"string","required":false,"defaultValue":"","description":"Number of overrides whose package has left the tree","values":"","deprecated":false},{"name":"needed-count","type":"string","required":false,"defaultValue":"","description":"Number of overrides still holding a package above its pin","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/check-overrides/action.yml), [`check-overrides.mjs`](https://github.com/linchpin/actions/blob/main/actions/check-overrides/check-overrides.mjs)
