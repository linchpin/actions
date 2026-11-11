---
title: php-checks.yml
---

PHP checks for a plugin or package: parse lint, PHPStan, PHPUnit, branch-scoped PHPCS, and PHPUnit again on a second PHP runtime, as steps in one job. mantle and block-alchemy arrived at this shape independently. A site repository, with no test suite, uses [lint.yml](lint.md) instead.

## Example

```yaml
jobs:
  php:
    uses: linchpin/actions/.github/workflows/php-checks.yml@v4
    secrets: inherit
    with:
      php_version: '8.2'
      php_extra_version: '8.4'   # second runtime for the suite; empty runs it once
      php_extensions: 'dom, libxml, mbstring'
      setup_command: composer install-wp-core
      composer_scripts: fixer:test
```

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Install PHP","content":"\u003cp\u003e\u003ccode\u003ephp_version\u003c/code\u003e, else \u003ccode\u003evars.PHP_VERSION\u003c/code\u003e, else 8.2, with \u003ccode\u003ezend.assertions=1\u003c/code\u003e, \u003ccode\u003eerror_reporting=-1\u003c/code\u003e and \u003ccode\u003edisplay_errors=On\u003c/code\u003e, and Composer's dev dependencies.\u003c/p\u003e"},{"title":"Run setup_command","content":"\u003cp\u003eWhen set, for example to install WordPress core for the test suite.\u003c/p\u003e"},{"title":"Parse lint","content":"\u003cp\u003e\u003ccode\u003ecomposer php-lint -- --checkstyle\u003c/code\u003e, annotated through \u003ccode\u003ecs2pr\u003c/code\u003e. On the primary version only: a parse that succeeds there cannot fail on a newer runtime.\u003c/p\u003e"},{"title":"PHPStan and extra scripts","content":"\u003cp\u003e\u003ccode\u003ecomposer phpstan\u003c/code\u003e, then each of \u003ccode\u003ecomposer_scripts\u003c/code\u003e in order.\u003c/p\u003e"},{"title":"PHPUnit","content":"\u003cp\u003e\u003ccode\u003evendor/bin/phpunit\u003c/code\u003e.\u003c/p\u003e"},{"title":"Coding standards for the branch","content":"\u003cp\u003ePull requests only: \u003ccode\u003ecomposer validate --no-check-all\u003c/code\u003e, then \u003ccode\u003ecomposer check-branch-cs -- origin/&lt;base&gt;\u003c/code\u003e. When it fails, \u003ccode\u003e./phpcs-report.xml\u003c/code\u003e is annotated on the PR.\u003c/p\u003e"},{"title":"PHPUnit on the second runtime","content":"\u003cp\u003eWith \u003ccode\u003ephp_extra_version\u003c/code\u003e set, PHP is swapped in place and the suite runs again.\u003c/p\u003e"}]} /-->

Every check after setup runs unless the run was cancelled, so one failure still lets the rest annotate. As steps that costs nothing; as separate jobs it was a billed minute each.

## Composer scripts

The checks call the plugin's own Composer scripts rather than tools of their own.

<!-- wp:docspress/fields {"title":"Composer scripts the plugin defines","fields":[{"name":"php-lint","type":"string","required":true,"defaultValue":"","description":"Run as \u003ccode\u003ecomposer php-lint -- --checkstyle\u003c/code\u003e. Its checkstyle output is piped to \u003ccode\u003ecs2pr\u003c/code\u003e.","values":"","deprecated":false},{"name":"phpstan","type":"string","required":false,"defaultValue":"","description":"Run as \u003ccode\u003ecomposer phpstan\u003c/code\u003e. Needed while \u003ccode\u003erun_phpstan\u003c/code\u003e is true, which is the default.","values":"","deprecated":false},{"name":"check-branch-cs","type":"string","required":false,"defaultValue":"","description":"Run as \u003ccode\u003ecomposer check-branch-cs -- origin/&lt;base&gt;\u003c/code\u003e on pull requests while \u003ccode\u003erun_phpcs\u003c/code\u003e is true. Must write \u003ccode\u003e./phpcs-report.xml\u003c/code\u003e.","values":"","deprecated":false}],"searchable":false,"compact":true} /-->

`run_phpunit` runs `vendor/bin/phpunit` directly, so PHPUnit has to be a dev dependency.

## Behaviour notes

- **PHPCS needs a pull request.** It diffs the base branch, so on any other event it is skipped whatever `run_phpcs` says. The step also runs `composer validate --no-check-all` first, so an invalid `composer.json` fails it.
- **The second runtime runs PHPUnit only.** Parse lint, PHPStan and PHPCS run once, on the primary version. The extra version is swapped in place with `setup-php`, which costs seconds where a matrix job costs a billed minute.
- **Repo-specific checks stay in the caller**, as their own job.
- The job times out after 15 minutes.

See [PR checks](../guides/pr-checks.md) for the full plugin set, with [plugin-check.yml](plugin-check.md) and [wp-version-checker.yml](wp-version-checker.md).

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"php_version","type":"string","required":false,"defaultValue":"","description":"Primary PHP version. Defaults to vars.PHP_VERSION, then 8.2","values":"","deprecated":false},{"name":"php_extra_version","type":"string","required":false,"defaultValue":"","description":"Second runtime for the test suite. Empty runs it once","values":"","deprecated":false},{"name":"php_extensions","type":"string","required":false,"defaultValue":"","description":"Extra PHP extensions, e.g. dom, libxml, mbstring","values":"","deprecated":false},{"name":"setup_command","type":"string","required":false,"defaultValue":"","description":"Shell run after Composer install, before the checks (e.g. composer install-wp-core)","values":"","deprecated":false},{"name":"composer_scripts","type":"string","required":false,"defaultValue":"","description":"Newline-separated extra composer scripts, e.g. fixer:test","values":"","deprecated":false},{"name":"run_phpstan","type":"boolean","required":false,"defaultValue":"true","description":"Run composer phpstan","values":"","deprecated":false},{"name":"run_phpunit","type":"boolean","required":false,"defaultValue":"true","description":"Run vendor/bin/phpunit","values":"","deprecated":false},{"name":"run_phpcs","type":"boolean","required":false,"defaultValue":"true","description":"Run branch-scoped PHPCS. Pull requests only, since it diffs the base","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"PACKAGIST_COMPOSER_AUTH_JSON","type":"string","required":false,"defaultValue":"","description":"auth.json contents for packagist.linchpin.com (v4 passes this via the COMPOSER_AUTH env)","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `php` | `contents: read` |

## Source

[`.github/workflows/php-checks.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/php-checks.yml)
