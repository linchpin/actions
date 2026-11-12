---
title: Troubleshooting
---

Failures the workflows and actions report, by the text they print. Every message below is quoted from the source, with the cause and the fix. Text in angle brackets stands for the value in your run.

<!-- wp:docspress/troubleshooter {"title":"Where did it fail?","intro":"Answer from the failed run's summary page.","startId":"start","questions":[{"id":"start","question":"Did the run fail before any job started?","yesLabel":"Yes","yesNext":"perms","noLabel":"No","noNext":"deploy"},{"id":"deploy","question":"Did it fail in a build or deploy job?","yesLabel":"Yes","yesNext":"deployout","noLabel":"No","noNext":"maint"},{"id":"maint","question":"Was it a maintenance run: rolling maintenance, a snapshot, or the monthly window?","yesLabel":"Yes","yesNext":"maintout","noLabel":"No","noNext":"checks"}],"outcomes":[{"id":"perms","status":"error","title":"Permissions","content":"\u003cp\u003eThe caller grants less than a nested job requests. See \u003cstrong\u003eBefore the run starts\u003c/strong\u003e below.\u003c/p\u003e"},{"id":"deployout","status":"warning","title":"Build or deploy","content":"\u003cp\u003eFind the annotation in \u003cstrong\u003eBuild\u003c/strong\u003e, \u003cstrong\u003eDeploy\u003c/strong\u003e, \u003cstrong\u003eBackup and continue\u003c/strong\u003e, \u003cstrong\u003eRemote plugin install\u003c/strong\u003e or \u003cstrong\u003eSafety Net\u003c/strong\u003e below.\u003c/p\u003e"},{"id":"maintout","status":"neutral","title":"Maintenance","content":"\u003cp\u003eMost maintenance runs skip rather than fail. See \u003cstrong\u003eMonthly window\u003c/strong\u003e and \u003cstrong\u003eMerges and rolling maintenance\u003c/strong\u003e below.\u003c/p\u003e"},{"id":"checks","status":"neutral","title":"Pull request checks","content":"\u003cp\u003eSee \u003cstrong\u003ePR checks\u003c/strong\u003e and \u003cstrong\u003eBrowser QA\u003c/strong\u003e below.\u003c/p\u003e"}],"showProgress":true} /-->

## Before the run starts

**`the nested job 'build' is requesting 'contents: write', but is only allowed 'contents: read'`**
The caller grants less than a job inside the called workflow asks for, and GitHub checks the whole call tree before anything runs. `deploy.yml` calls `build.yml`, which needs `contents: write` to attach `release.zip` to a release. Grant `contents: write` and `deployments: write` in every `deploy.yml` caller, rollbacks included. Each workflow page has a **Permissions** table.

## Build

| Message | Cause | Fix |
| --- | --- | --- |
| `Theme directory <dir> not found`, `Plugin directory <dir> not found` | A name in `THEMES` or `PLUGINS` has no folder | Correct the variable |
| `<n> buildable package(s) missing from THEMES/PLUGINS` (a warning, or an error ending `Refusing to build an incomplete release.`) | A theme or plugin is tracked in git and has a lockfile, but is not listed | Add it to `THEMES` or `PLUGINS`. With `STRICT_BUILD_LIST=true` this fails the build |
| `No .distignore found in the project — using the bundled default.` (warning) | The project has no `.distignore` | Add one. The bundled default is in [`actions/build-release`](https://github.com/linchpin/actions/blob/main/actions/build-release/default.distignore) |
| `REMOTE_PLUGIN_INSTALL is true but no composer.lock was found at <path>` | Remote plugin install needs the lock in the release | Commit `composer.lock` |

## Deploy

| Message | Cause | Fix |
| --- | --- | --- |
| `HOST='<x>' is not supported by linchpin/actions v4 (expected pressable, wpengine, or cloudways)` | `HOST` is unset or misspelled on the environment | Set `HOST` |
| `Failed to authenticate with the Pressable API` | Every Pressable deploy authenticates first | Check `PRESSABLE_API_CLIENT_ID` and `PRESSABLE_API_CLIENT_SECRET` |
| `release.zip never appeared on <tag> after ~2 min.` | A `release_tag` deploy found no `release.zip` on that release | Deploy the release once with `build_for_release`, which attaches the zip |
| `composer.lock is not in release.zip.` | `REMOTE_PLUGIN_INSTALL` is on and the project's `.distignore` excludes the lock | Stop excluding `composer.lock` |
| `REMOTE_PLUGIN_INSTALL is not supported with DEPLOYMENT_AUTH_TYPE=pass (password SSH).` | Cloudways Autonomous password auth | Use SSH key auth, or turn the remote install off |
| `Health check failed for <URL>` | `SITE_URL` answered 5xx, or not at all, for ten attempts | Fix the site. Any status below 500 passes, so redirects and auth walls are fine |
| `wp mantle health failed on the server`, `WordPress failed to load on the server` | Pressable's server-side check after the sync | Fix what the check reports. `wp mantle health isn't available on this site (update Mantle)` is only a warning |
| `Active but not on disk: <slug>` (error) | A plugin is active in the database but its files aren't on the server. On a development site, the database is production's, so production has it active, and it was installed there outside the repo | Add it to the repo, or deactivate it where it is active. The error says which, with the `composer require` command. `PROTECTED_PATHS` can't fix this: it only keeps a plugin that is already on the server |
| `Not in the repo: <slug>` (warning) | A plugin is on the server but the release doesn't ship it, its `composer.lock` doesn't list it, and it isn't a symlink or a protected path | Add it to the repo, add it to `PROTECTED_PATHS` if the host installs it on every environment, or delete it. See [unmanaged-plugins](composite-actions/unmanaged-plugins.md) |
| `<path> ships in this release but was NOT deployed` (warning) | The release ships a path the server has as a platform symlink or a protected path | Stop shipping it, or add it to `PROTECTED_PATHS` on purpose. See [Host-managed folders](guides/host-managed-folders.md) |

## Backup and continue

| Message | Cause | Fix |
| --- | --- | --- |
| `do_backup needs the MANTLE_API_BEARER secret to ask api.linchpin.com for the backup.` | `do_backup: true` without the token | Pass `MANTLE_API_BEARER` |
| `api.linchpin.com would not take the backup, so nothing was deployed: <answer>` | api refused the request. The deployment is marked failed | Read api's answer |
| `The backup-and-continue flow currently supports HOST=pressable only` | `deploy-continue.yml` ran for another host | Use `do_backup` on Pressable only |
| `release.zip never appeared on <tag> after ~10 min.` | The continue run was given a `release_tag` with no zip attached | Deploy that release with `build_for_release` first |

## Remote plugin install

| Message | Cause | Fix |
| --- | --- | --- |
| `Could not enter <path> on the server` | `wp-path` is wrong for the host | Check the path the deploy passes |
| `Could not parse 'wp plugin list' output from the server. Is WP-CLI available at <path>?` | WP-CLI did not run in that path | Check WP-CLI on the server |
| `Install failed: <kind>/<slug>@<version>` | The dist URL, or the registry credentials, failed | Check `SATISPRESS_USER` and `SATISPRESS_PASSWORD` for packagist.linchpin.com packages |
| `Version mismatch after install: … not present after install` | The archive's top-level folder is not named for the slug | Fix the package's archive |
| `Newly installed and NOT activated: …` (warning) | The action never activates packages | Activate them in wp-admin or with WP-CLI |

[Remote plugin install](guides/remote-plugin-install.md) covers the mode end to end.

## Safety Net

| Message | Cause | Fix |
| --- | --- | --- |
| `safety_net is for development only, and not with do_backup. This deploy is to '<env>'.` | `safety_net: true` on another environment, or with `do_backup` | Use it on the development deploy only |
| `safety_net needs SSH key auth, and DEPLOYMENT_AUTH_TYPE is pass.` | Cloudways password auth | Use key auth |
| `The server says its environment type is '<type>', not development, so Safety Net was not installed.` | `wp_get_environment_type()` on the server is not `development` | Set the environment type to `development` on the dev site |
| `Could not download <url>. Is <version> released on <repository>, with safety-net.zip attached?` | `safety_net_version` names a release without the zip | Pick a released version |
| `Safety Net has not finished on <n> site(s), so nothing was deployed.` | A site did not report every scrub step done. The lines above it say which site and which step | Fix that site and redeploy. The first request after the next sync runs the scrub again |

## Deployment log

`Not reported: DEPLOYMENTS_API_CLIENT_ID and DEPLOYMENTS_API_CLIENT_SECRET are not set.` is a notice, and `Not reported to the deployment log: …` is a warning. Neither fails the deploy. The first means the organization secrets did not reach the run, usually because the caller passes secrets one by one instead of with `secrets: inherit`.

## Monthly window

`auto-merge-maintenance.yml` skips rather than fails, and logs why:

| Log line | Meaning |
| --- | --- |
| `skip: base branch '<base>' is not a maintenance/YYYY-MM branch` | Not a monthly window. On rolling maintenance, `rolling-maintenance.yml` merges instead |
| `skip: author '<login>' is not renovate[bot]` | Only Renovate's PRs auto-merge. Merge others by hand |
| `skip: labeled 'major'` | Majors are excluded on purpose |
| `skip: changed file '<path>' is outside the allow-list` | A file is off the allow-list. Merge by hand |
| `skip: mergeStateStatus is '<state>', not CLEAN yet — will retry next run` | A required check or review is pending |

`auto-approve-maintenance.yml` comments `❌ Not auto-approved: Non-allowed files detected` when a PR touches a file off its allow-list, and a person has to review it. Its allow-list includes `.husky/` and auto-merge's does not, so a Renovate PR that touches `.husky/` is approved but never auto-merged.

## PR checks

| Message | Cause | Fix |
| --- | --- | --- |
| `php-parallel-lint is not installed, so nothing checked syntax.` | `lint.yml` found no syntax linter in the project | Add `php-parallel-lint/php-parallel-lint` to require-dev, or set `require_tools: false` to make it a warning |
| `phpcs is not installed, so nothing checked coding standards.` | No PHPCS in the project | Add it to require-dev, or set `require_tools: false` |
| `PHPStan requested but not installed in this project — skipped.` (warning) | `run_phpstan: true` with no PHPStan | Install PHPStan, or stop requesting it |
| `No plugins activated` (from Plugin Check) | `php_version` is below the plugin's `Requires PHP`, so WordPress refused to activate it and no check ran | Raise `php_version`; it sets the wp-env container's PHP too |
| `Artifact '<name>' holds <n> zip files at its root; Plugin Check needs exactly one.` | The `artifact` input names an artifact with more or fewer than one zip | Upload exactly one zip |
| `build_dir '<dir>' does not end in a plugin slug.` | `build_dir` ends in `/`, `.` or `..` | End it in the plugin's slug |
| `composer.lock in '<dir>' can no longer be installed against its composer.json` | A constraint changed in `composer.json` without rebuilding the lock | Run `composer update` in that directory and commit the lock |

A Plugin Check run that passes while excluding nothing usually has codes in `exclude_checks`. That input takes check names; the codes a check emits go in `ignore_codes`. Neither input errors on the wrong kind of value. See [PR checks](guides/pr-checks.md).

## Browser QA

| Message | Cause | Fix |
| --- | --- | --- |
| `Triggering the run failed (HTTP <status>): <detail>` | The QA platform refused the trigger. A 403 usually means another project's token | Use this project's own `QA_API_TOKEN` |
| `Status poll failed (HTTP <status>): <detail>` | A permanent 4xx while polling: a revoked token, the wrong project, or a missing run | Check the token and `project` |
| `Run <id> did not reach a terminal state within <n> minute(s).` | The suite outlasted `timeout_minutes` | Raise it, keeping it under the job's 60-minute limit |
| `QA run failed. See <url>` | A test is red | Open the run. The deploy before it has already happened; nothing rolls back |
| `<name> must be a whole number (got '<value>').` | A fractional `timeout_minutes` or `poll_interval_seconds` | Use whole numbers |
| `This PR was authored by the QA platform but changes files outside qa/.` | The QA platform's PR touched application code | Do not merge it |

If the `qa-guard.yml` schema job fails at checkout, `QA_SCHEMA_TOKEN` is missing or cannot read linchpin/automated-testing.

## README updates

`composer update --lock failed; leaving composer.lock unchanged` is a warning from `update-readme.yml`. The README still updates. The usual cause is a missing `PACKAGIST_COMPOSER_AUTH_JSON`, because packagist.linchpin.com answers 401 without it.

## Merges and rolling maintenance

Rolling maintenance reports why it left a PR alone rather than failing:

| Log line | Meaning |
| --- | --- |
| ``Cannot create `maintenance` while these branches exist; merge or delete them first: …`` | A `maintenance/YYYY-MM` branch still exists, and Git cannot hold both. Close the window, or run `bin/convert-repo` with `--close-windows` |
| ``#<n> into `maintenance`: waiting for an approving review.`` | The PR is not labelled `automerge-safe`, so it needs an approval first |
| ``#<n> into `maintenance`: checks red, and someone other than Renovate pushed to it; not retrying.`` | Someone else committed to the PR. Retry or fix it by hand |
| `#<n> … leaving it for a person.` (Governing merge) | A Governing PR changes files other than `composer.json` and `composer.lock`, moves more than one package, or conflicts after a person committed to it |

`resolve-merge` never fails the step when it gives up. It warns `The merge was not resolved; see the step summary for why.`, sets `resolved` to `false`, and its `reason` output starts `Not resolved:`. [Resolving merge conflicts](guides/resolving-merges.md) lists the reasons and what to do about each.

When neither `resolve-merge` nor Sisyphus can settle a conflict, rolling maintenance opens one `maintenance-conflict` issue titled `Bring <base> into <branch> by hand`. It closes when production is merged in again.

A snapshot refresh stops with `refresh needs head, …`, `refresh never pushes to the production branch (…); it moves only by a PR.` or `head and base are both …` when its inputs are wrong. It fails with `Not refreshed: <reason> (files: <files>)` when `resolve-merge` gives up. The template caller does not pass `publish_conflicts`, so a refresh started from it never hands files to Sisyphus. Resolve them by hand, or set `publish_conflicts: true` and refresh again once Sisyphus has answered.

[`bin/convert-repo`](scripts/convert-repo.md) and [`bin/onboard-site`](scripts/onboard-site.md) list what each `!` line means and what to do about it.
