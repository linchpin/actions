---
title: Resolving merge conflicts
---

GitHub's merge API refuses whenever both sides changed neighbouring lines. On a rolling `maintenance` branch that nearly always means manifests and lockfiles. Renovate bumps different packages on each side, the entries sit next to each other, and git calls that a conflict even when no package moved on both sides. linchpin.com's #1890 in October 2026 was exactly that: two `package.json` and eight `package-lock.json` files, and it stopped every nightly run for days. The [resolve-merge](../composite-actions/resolve-merge.md) action does what a person would do in a checkout. Whatever it cannot settle goes to Sisyphus, then to a person.

## Where it runs

| Caller | When | Turned on by |
| --- | --- | --- |
| [rolling-maintenance.yml](../workflows/rolling-maintenance.md) | Bringing the production branch into `maintenance` is refused | `resolve_conflicts` and `publish_conflicts`, both `true` by default |
| [snapshots.yml](../workflows/snapshots.md) with `mode: refresh` | A promotion's branch has fallen behind its target and GitHub's update-branch refuses | Always for a refresh. `publish_conflicts` is `false` by default |

You can also call the action from your own workflow. Its page has a complete example.

## What it resolves

Each conflicted file is resolved by what it is, and nothing cleverer.

| Conflicted file | Resolved by |
| --- | --- |
| `package.json`, `composer.json` | A three-way merge by key: each value comes from the side that changed it. When both sides raised the top-level `version` (release-please's) or the same dependency's range, the higher one wins. Renovate sends a major to `main` and a minor of the same package to `maintenance`, and the major supersedes it. |
| `package-lock.json` | A three-way merge by package entry, the same way, taking the higher version where both moved one. Then `npm install --package-lock-only` repairs the tree against the merged `package.json`, and `npm ls` checks it. |
| `composer.lock` | Keeps this side's lock and re-applies each package the other side moved, at exactly the version it locked (`composer update <name> --with <name>:<version>`). It then checks nothing else moved and runs `composer validate`. When only `composer.json` changed, `composer update --lock` refreshes the content-hash. |
| Anything else | Sisyphus's answer for this exact pair of commits, when one exists. Otherwise it gives up. |

npm's own lockfile conflict handling is not used, because it re-resolves freely. On #1890 it moved 74 untouched packages, one of them a major. npm and Composer run with scripts and plugins off, since the job holds a token that can push.

## When it gives up

It aborts the merge, pushes nothing, and sets `resolved` to `false`, `reason` to the sentence below, and `unresolved` to the files left over. The reason also appears in the step summary, prefixed `Not resolved:`. The action step itself still succeeds; the caller decides what giving up means.

| Reason | What to do |
| --- | --- |
| `more than manifests and lockfiles conflict: <files>` | Wait for Sisyphus's answer (with `publish-conflicts`), or merge by hand |
| `<file>: both sides changed <keys>.` | Both sides set some other key to different values. Pick one by hand |
| `<lock>: <name> moved on both sides, <version> in '<branch>' and <version> on '<from>'.` | Choose the version, then re-run `composer update <name>` by hand |
| `<lock>: <name> is a dev branch (<version>) on '<from>'; its lock entry is not a version to re-apply.` | A `dev-*` requirement has no version to pin. Resolve by hand |
| `npm moved packages neither side moved in <lock>: <name> <expected> became <actual>, …` | npm floated a package already in the tree that neither side moved and `package.json` does not name. Resolve by hand |
| `<lock> is lockfileVersion 1, which has no package entries to merge.` | Resolve by hand. Lockfiles from npm 7 or later have package entries |
| `npm could not repair <lock>: …` or `npm ls finds <lock>'s tree broken: …` | The merged manifest does not install. Read the npm error in the summary |
| `<lock> moved more than '<from>' did: …` | Composer moved packages beyond the ones the other side moved. Resolve by hand |
| `the push to '<branch>' was refused; it may have moved.` | The branch moved during the run. The next run starts from the new head |

In the real messages the branch and ref names are wrapped in backticks, not quotes. The script holds the full list of reasons ([`resolve-merge.sh`](https://github.com/linchpin/actions/blob/main/actions/resolve-merge/resolve-merge.sh)).

## Handing a conflict to Sisyphus

Any other conflicted file can go to Sisyphus, and Sisyphus does the asking, so no runner waits on a model. The two hand over on branches named for the exact pair of commits: the first 12 characters of this side's commit, then the other side's. If either branch moves, the pair changes, so an answer for an older pair never applies.

<!-- wp:docspress/diagram {"title":"The conflict hand-off","type":"sequence","source":"resolve-merge -\u003e GitHub: pushes sisyphus/conflicts/\u003cpair\u003e\nSisyphus -\u003e GitHub: reads the conflicts\nSisyphus -\u003e GitHub: pushes sisyphus/resolutions/\u003cpair\u003e\nresolve-merge -\u003e GitHub: next run applies the answers and pushes the merge\nresolve-merge -\u003e GitHub: deletes both branches","caption":"Only files other than manifests and lockfiles take this path."} /-->

| Branch | Written by | Holds |
| --- | --- | --- |
| `sisyphus/conflicts/<this side>-<other side>` | resolve-merge, with `publish-conflicts: true`, when it gives up | Each conflicted file with diff3 markers, so every hunk carries its base, plus `.sisyphus/conflicts.json` naming both commits, the branch, the source and the files |
| `sisyphus/resolutions/<the same pair>` | Sisyphus | Its answer for each file, plus `.sisyphus/resolutions.json` saying which model resolved what |

On the next run, when the resolutions branch exists for the pair being merged, each conflicted file takes its answer instead of giving up. An answer is refused when any of these hold:

- `.sisyphus/resolutions.json` is missing, or names a different pair of commits;
- there is no answer for one of the files;
- the answer still has a conflict marker (`<<<<<<<`, `|||||||` or `>>>>>>>` at the start of a line; a lone `=======` is allowed, since it is also a Markdown underline);
- a `.php` answer fails `php -l`, or a `.json` answer fails to parse.

The merge commit names every file resolved this way, as `<file>: resolved by Sisyphus with <model>. Review it.`, and the action's `model-resolved` output lists them. When the maintenance branch is later frozen into a snapshot, the snapshot pull request repeats those lines under a warning, so the person merging reviews them first. A merge that succeeds deletes both hand-off branches.

## When both give up

- **Rolling maintenance** opens one issue labelled `maintenance-conflict`, titled `Bring <production> into <maintenance> by hand`, and says resolve-merge tried first. Sisyphus reads that label. The resolver still runs on every run while the issue is open, and the issue closes once production is in again.
- **A snapshot refresh** fails its run with `Not refreshed: <reason> (files: <files>)`.

To resolve by hand, merge the production branch into the branch locally, resolve what the resolver could not, and push. For a lockfile, the issue's advice is to take the lock from production and re-run `composer update` (or `npm install`) for the packages the maintenance branch bumped.

## Run it locally

`resolve-merge.sh` runs in your own checkout. Run it from a checkout of the branch with full history and the other side fetched. You need `git`, `jq`, `npm`, `composer` and `php` on your path.

<!-- wp:docspress/terminal-session {"title":"Resolve without pushing","shell":"bash","prompt":"$","command":"MERGE_FROM=origin/main DRY_RUN=true bash ../actions/actions/resolve-merge/resolve-merge.sh","output":""} /-->

The path assumes a clone of linchpin/actions sits next to the site repository. With `DRY_RUN=true` it resolves and commits in your checkout and pushes nothing. The merge commit is left for you to inspect, and `git reset --hard ORIG_HEAD` drops it. `MERGE_BRANCH`, `PUBLISH_CONFLICTS`, `COMPOSER_AUTH` and `NPM_TOKEN` work as the action's inputs do. It exits `1` when it gives up.
