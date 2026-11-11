---
title: Contributing
---

How this repository is laid out, checked and released. It is for changes to linchpin/actions itself. To use it from another repository, start at [Call a shared workflow](getting-started/index.md).

## Layout

<!-- wp:docspress/file-tree {"root":"linchpin/actions/","tree":".github/\n  workflows/\n.docspress/\n  brief.md\nactions/\nbin/\n  convert-repo\n  onboard-site\ndocs/\ntemplates/\n  rolling-maintenance/\nCHANGELOG.md\nrelease-please-config.json\nversion.txt","caption":"Top-level layout."} /-->

- `.github/workflows/` holds the reusable workflows (`on: workflow_call`), `composer-bump.yml`, which Linchpin Governing dispatches, and this repository's own `ci.yml`, `release.yml` and `sync-docs.yml`.
- `actions/` holds the composite actions. An action's scripts ship beside its `action.yml` and run from `github.action_path`, so the ref a caller pins is the code that runs.
- `bin/` holds the operator scripts, and `templates/rolling-maintenance/` the caller workflows `bin/convert-repo` installs.
- `docs/` is these pages. `.docspress/brief.md` says what they must contain.

## Checks on every pull request

[`ci.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/ci.yml) runs on pull requests and on pushes to `main`:

| Check | Blocking |
| --- | --- |
| yamllint over `.github/workflows/` with [`.ymllint.yml`](https://github.com/linchpin/actions/blob/main/.ymllint.yml) (line length 125, no document-start marker) | Yes |
| actionlint | No (`continue-on-error`) |
| zizmor over `.github/workflows/` and `actions/` | No (`continue-on-error`) |

Run the same tools locally before pushing. Most scripts also run locally with `DRY_RUN=true`, which writes nothing. For example:

```bash
GH_REPO=linchpin/ctoec DRY_RUN=true actions/rolling-maintenance/rolling-maintenance.sh
MERGE_FROM=origin/main DRY_RUN=true bash actions/resolve-merge/resolve-merge.sh
```

## Testing a change from a branch

The workflows reference their composite actions at `@v4`, not by relative path. For example, `deploy.yml` runs `linchpin/actions/actions/deploy-pressable@v4`. Calling a workflow from a branch therefore runs the branch's workflow with the **released** actions. To try a changed action before release, point a test caller's step at the branch (`linchpin/actions/actions/<name>@<branch>`), or change the `@v4` references on the branch for the test and change them back before merging.

`deploy.yml` calls `build.yml` by relative path (`./.github/workflows/build.yml`), so those two always move together.

## Releasing

Releases are cut by release-please from `main` ([`release-please-config.json`](https://github.com/linchpin/actions/blob/main/release-please-config.json): the `simple` release type, `CHANGELOG.md`, `version.txt`, tags without a component).

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Merge to main","content":"<p>A push to <code>main</code> runs release-please, which opens or updates the release PR. It runs with <code>GH_BOT_TOKEN</code>, falling back to the job token.</p>"},{"title":"Merge the release PR","content":"<p>release-please tags <code>vX.Y.Z</code> and publishes the GitHub release.</p>"},{"title":"The major tag moves","content":"<p>The <code>release: published</code> event runs <code>update-major-tag</code>, which force-moves <code>v4</code> to the new release. Every <code>@v4</code> caller picks it up on its next run.</p>"}]} /-->

The commit type decides whether callers get a change. release-please releases on `feat`, `fix` and `perf` commits, and `CHANGELOG.md` has sections for those three. A change to a shared workflow or action is therefore a `feat` or a `fix`. A `ci` or `docs` commit does not cut a release and never moves `@v4`. A `!` marks a breaking change and starts the next major. Keep it for changes that break callers.

`update-major-tag` refuses a tag that is not `vX.Y.Z`. It also skips moving the tag, with a warning, while a branch with the major's name exists, because a branch and a tag both called `v4` make `@v4` ambiguous. To repair a tag that did not move, run the Release workflow by hand with `tag` set to the release, for example `v4.22.0`.

## Publishing these docs

[`sync-docs.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/sync-docs.yml) publishes `docs/` to docs.linchpin.com with [DocsPress](https://github.com/linchpin/docspress), under the `actions` root, which this repository owns whole. It runs only when dispatched by hand, and its defaults are a dry run with draft status. Removed pages go to the trash, never a hard delete.

- Give every page a frontmatter `title:` and start its sections at `##`. The theme renders the title.
- Link pages to each other with relative `.md` links. Link files outside `docs/` by their GitHub URL, because DocsPress leaves a relative link it cannot map to a page untouched.
- Keep relative links out of block attributes. DocsPress rewrites Markdown links only.
- When you add, rename or change the default of an input, secret or output, update the reference block on that unit's page in the same pull request.
