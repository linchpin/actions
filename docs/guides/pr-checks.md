---
title: PR checks
---

Which shared workflows check a pull request, by repository shape. A site repository gets lint and a Composer lock gate; a plugin repository gets a test suite, WordPress's Plugin Check, and a scheduled `Tested up to` check.

| Repository | On pull requests | On a schedule |
| --- | --- | --- |
| Site (`wp-content`-shaped) | [lint.yml](../workflows/lint.md), [validate-composer.yml](../workflows/validate-composer.md) | [check-overrides.yml](../workflows/check-overrides.md) |
| Plugin or package | [php-checks.yml](../workflows/php-checks.md), [plugin-check.yml](../workflows/plugin-check.md) | [wp-version-checker.yml](../workflows/wp-version-checker.md) |

## Callers

<!-- wp:docspress/code-tabs {"tabs":[{"label":"Site repository","language":"yaml","filename":".github/workflows/ci.yml","code":"name: CI\non:\n  pull_request:\n    types: [opened, synchronize, reopened]\n\npermissions:\n  contents: read\n\njobs:\n  lint:\n    uses: linchpin/actions/.github/workflows/lint.yml@v4\n    secrets:\n      PACKAGIST_COMPOSER_AUTH_JSON: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}\n    with:\n      lint_paths: themes/my-theme plugins/my-functionality\n      run_phpstan: true\n\n  composer:\n    uses: linchpin/actions/.github/workflows/validate-composer.yml@v4\n    secrets:\n      PACKAGIST_COMPOSER_AUTH_JSON: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}"},{"label":"Plugin repository","language":"yaml","filename":".github/workflows/ci.yml","code":"name: CI\non:\n  pull_request:\n\npermissions:\n  contents: read\n\njobs:\n  php:\n    uses: linchpin/actions/.github/workflows/php-checks.yml@v4\n    secrets: inherit\n    with:\n      php_version: '8.2'\n      php_extra_version: '8.4'   # second runtime for the suite; empty runs it once\n      php_extensions: 'dom, libxml, mbstring'\n      setup_command: composer install-wp-core\n      composer_scripts: fixer:test\n\n  plugin-check:\n    uses: linchpin/actions/.github/workflows/plugin-check.yml@v4\n    with:\n      build_dir: ./build/mantle\n      build_command: |\n        npm ci\n        npm run build\n        bash scripts/build.sh\n      exclude_directories: vendor,third-party\n      exclude_checks: plugin_updater        # check NAMES\n      ignore_codes: plugin_updater_detected # the codes a check emits"}],"showLineNumbers":false,"caption":"The pull-request checks for each repository shape."} /-->

`lint_paths` should name your own theme and plugins: after Composer install the tree also holds third-party plugin code, whose syntax is not yours to police. The plugin example is mantle's.

## Site repositories

[lint.yml](../workflows/lint.md) runs syntax lint, PHPCS on the files the PR changed, and optionally PHPStan, with the project's own tools from `require-dev`. PHPCS annotates the diff through `cs2pr`; errors fail the job and warnings do not. By default a missing `php-parallel-lint` or `phpcs` fails the job rather than skipping it, because a skipped gate reports green.

[validate-composer.yml](../workflows/validate-composer.md) dry-runs `composer install` from every lock in the repository, so a lock that no longer satisfies its `composer.json` fails the PR instead of the production deploy.

## Plugin repositories

[php-checks.yml](../workflows/php-checks.md) is the plugin shape: parse lint, PHPStan, PHPUnit, branch-scoped PHPCS, and PHPUnit again on a second runtime. It calls the plugin's own Composer scripts:

| Script | Needed when |
| --- | --- |
| `php-lint` | Always. It receives `--checkstyle`, and its output is annotated through `cs2pr`. |
| `phpstan` | `run_phpstan` is true, the default. |
| `check-branch-cs` | `run_phpcs` is true, on pull requests. It takes the base ref and must write `./phpcs-report.xml`. |

PHPCS runs on pull requests only, since it diffs the base branch. Repo-specific checks stay in the caller as their own job.

[plugin-check.yml](../workflows/plugin-check.md) builds the distributable and runs `wordpress/plugin-check-action` against it. `php_version` sets the PHP of the runner and of the wp-env container that activates the plugin, so set it to at least the plugin's `Requires PHP`; below that, the action fails with `No plugins activated` having run no checks.

<!-- wp:docspress/callout {"tone":"warning","title":"exclude_checks takes names, ignore_codes takes codes","content":"\u003cp\u003eNeither input errors on the wrong kind of value. mantle carried codes in \u003ccode\u003eexclude-checks\u003c/code\u003e for a while, which silently excluded nothing.\u003c/p\u003e","collapsible":false} /-->

[wp-version-checker.yml](../workflows/wp-version-checker.md) opens an issue when the plugin's `Tested up to` header falls behind WordPress. Give it a `schedule` trigger, not `push`.

## Check the zip a release ships

In a release, build the zip once and pass it to Plugin Check with `artifact`. The check then runs against the exact file that ships, and skips the checkout, PHP, Node and build steps.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      # …checkout, PHP, Node…
      - run: bash scripts/build.sh
      - uses: actions/upload-artifact@v7
        with:
          name: plugin-zip
          path: build/discovery.zip
          compression-level: 0

  plugin-check:
    needs: build
    uses: linchpin/actions/.github/workflows/plugin-check.yml@v4
    with:
      artifact: plugin-zip
      build_dir: ./build/discovery   # last segment is the plugin slug
      php_version: '8.4'             # still sets the wp-env container's PHP

  publish:
    needs: plugin-check
    # …download the same artifact and ship it…
```

- The artifact holds exactly one zip.
- The plugin can be wrapped in a directory named for the slug, or sit at the root of the zip: the two shapes WordPress installs. A wrapping directory that does not match `build_dir`'s last segment is an error.
- On a Blacksmith runner, skipping PHP is most of the saving. Blacksmith registers as self-hosted, so `setup-php` installs PHP through apt there, at about two minutes a job.

## Formatting fixes stay local

No workflow runs phpcbf. The v3 flow, a CI bot opening an "Auto Fix Formatting" PR that triggered more CI, was one of the most expensive per-PR items; run the fixer locally, ideally from a pre-commit hook.

Coming from v3's `phplint.yml`, `phpcs.yml` and `phpcbf.yml`? See [Migrating from v3 to v4](../MIGRATION-v3-to-v4.md).
