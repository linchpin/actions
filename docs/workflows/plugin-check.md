---
title: plugin-check.yml
---

Runs WordPress's Plugin Check (`wordpress/plugin-check-action`) against a plugin's distributable. Either it builds the distributable itself, or, given `artifact`, it checks a zip an earlier job built, so a release checks the exact file it ships.

## Example

<!-- wp:docspress/code-tabs {"tabs":[{"label":"Build here","language":"yaml","filename":".github/workflows/ci.yml","code":"jobs:\n  plugin-check:\n    uses: linchpin/actions/.github/workflows/plugin-check.yml@v4\n    with:\n      build_dir: ./build/mantle\n      build_command: |\n        npm ci\n        npm run build\n        bash scripts/build.sh\n      exclude_directories: vendor,third-party\n      exclude_checks: plugin_updater        # check NAMES\n      ignore_codes: plugin_updater_detected # the codes a check emits"},{"label":"Check a prebuilt zip","language":"yaml","filename":".github/workflows/release.yml","code":"jobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      # …checkout, PHP, Node…\n      - run: bash scripts/build.sh\n      - uses: actions/upload-artifact@v7\n        with:\n          name: plugin-zip\n          path: build/discovery.zip\n          compression-level: 0\n\n  plugin-check:\n    needs: build\n    uses: linchpin/actions/.github/workflows/plugin-check.yml@v4\n    with:\n      artifact: plugin-zip\n      build_dir: ./build/discovery   # last segment is the plugin slug\n      php_version: '8.4'             # still sets the wp-env container's PHP"}],"showLineNumbers":false,"caption":"Build the distributable in the job, or check the zip an earlier job built."} /-->

## How it works

Without `artifact`:

1. Check out the repository and install PHP (`php_version`, else `vars.PHP_VERSION`, else 8.2) with production Composer dependencies.
2. Resolve one Node version: `node_version`, else `.nvmrc`, else `lts/*`. Node setup is skipped, with a notice, when there is no `package-lock.json`, because `cache: npm` fails outright without one.
3. Run `build_command`.

With `artifact`, those steps are skipped:

1. Download the artifact into the runner's temp directory.
2. Require exactly one zip at its root.
3. Unzip it. A zip that wraps the plugin in one directory named for the slug goes beside `build_dir`; a zip with the plugin's files at its root goes into `build_dir`.

Then, either way, run Plugin Check on `build_dir` with `WP_ENV_PHP_VERSION` set to the same PHP version.

<!-- wp:docspress/callout {"tone":"warning","title":"php_version must reach Requires PHP","content":"\u003cp\u003eIt sets the runner's PHP and, through \u003ccode\u003eWP_ENV_PHP_VERSION\u003c/code\u003e, the wp-env container's. Below the plugin's \u003ccode\u003eRequires PHP\u003c/code\u003e header, WordPress refuses to activate the plugin and the action fails with \u003ccode\u003eNo plugins activated\u003c/code\u003e having run no checks.\u003c/p\u003e","collapsible":false} /-->

<!-- wp:docspress/callout {"tone":"warning","title":"exclude_checks takes names, ignore_codes takes codes","content":"\u003cp\u003eNeither input errors on the wrong kind of value. mantle carried codes in \u003ccode\u003eexclude-checks\u003c/code\u003e for a while, which silently excluded nothing.\u003c/p\u003e","collapsible":false} /-->

## Behaviour notes

- **`build_dir`'s last segment is the plugin slug.** wp-env mounts the plugin under that name. A prebuilt zip whose wrapping directory has another name is an error rather than a guess.
- **With `artifact`, `build_command`, `php_extensions` and `node_version` go unused.** `php_version` still matters, because wp-env runs the plugin on it.
- **On a Blacksmith runner, `artifact` is most of the saving.** Blacksmith registers as self-hosted, so `setup-php` installs PHP through apt there, at about two minutes a job.
- **No concurrency group.** Under `workflow_call`, `github.workflow` is the caller's name, so a group here could deadlock against the caller's own.
- Categories default to `general`, `performance`, `accessibility`, `security` and `plugin_repo`, with experimental checks included.

## Errors

| Message | Cause |
| --- | --- |
| `Artifact '<name>' holds <n> zip files at its root; Plugin Check needs exactly one.` | The artifact holds no zip, several, or a zip inside a folder. Upload the zip itself with `upload-artifact`'s default archiving. |
| `<zip> wraps the plugin in '<dir>/', but build_dir ends in '<slug>'.` | The zip's top directory and `build_dir`'s last segment differ. Rename one so they match. |
| `build_dir '<value>' does not end in a plugin slug.` | `build_dir` ends in `/`, `.` or `..`. |
| `No plugins activated` | `php_version` is below the plugin's `Requires PHP`. |

See [PR checks](../guides/pr-checks.md) for the rest of the plugin set.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"build_dir","type":"string","required":true,"defaultValue":"","description":"Directory the build produces, e.g. ./build/mantle. Its last segment is the plugin slug","values":"","deprecated":false},{"name":"artifact","type":"string","required":false,"defaultValue":"","description":"Name of an artifact uploaded earlier in the same run, holding one plugin zip. Set, it is unzipped into build_dir and the checkout, PHP, Node and build steps are skipped, so build_command, php_extensions and node_version go unused. The zip may wrap the plugin in a directory named for the slug, or hold its files at the root","values":"","deprecated":false},{"name":"build_command","type":"string","required":false,"defaultValue":"bash scripts/build.sh","description":"Shell to build the distributable. Multi-line is fine","values":"","deprecated":false},{"name":"php_version","type":"string","required":false,"defaultValue":"","description":"PHP for the runner AND the wp-env container. Defaults to vars.PHP_VERSION, then 8.2. Must be &gt;= the plugin's Requires PHP header or it cannot activate","values":"","deprecated":false},{"name":"php_extensions","type":"string","required":false,"defaultValue":"","description":"Extra PHP extensions","values":"","deprecated":false},{"name":"node_version","type":"string","required":false,"defaultValue":"","description":"Node version. Empty uses the caller's .nvmrc","values":"","deprecated":false},{"name":"categories","type":"string","required":false,"defaultValue":"general\nperformance\naccessibility\nsecurity\nplugin_repo\n","description":"Newline-separated plugin-check categories","values":"","deprecated":false},{"name":"exclude_directories","type":"string","required":false,"defaultValue":"","description":"Comma-separated directories to skip, e.g. vendor,third-party","values":"","deprecated":false},{"name":"exclude_checks","type":"string","required":false,"defaultValue":"","description":"Comma-separated check NAMES to skip (not codes)","values":"","deprecated":false},{"name":"ignore_codes","type":"string","required":false,"defaultValue":"","description":"Comma-separated codes to ignore (not check names)","values":"","deprecated":false},{"name":"include_experimental","type":"boolean","required":false,"defaultValue":"true","description":"Include experimental checks","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"PACKAGIST_COMPOSER_AUTH_JSON","type":"string","required":false,"defaultValue":"","description":"auth.json contents for packagist.linchpin.com (v4 passes this via the COMPOSER_AUTH env)","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `plugin-check` | `contents: read` |

## Source

[`.github/workflows/plugin-check.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/plugin-check.yml)
