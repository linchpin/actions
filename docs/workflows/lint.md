---
title: lint.yml
---

PR lint for a site repository: PHP syntax lint, PHPCS on the files the pull request changed, annotated inline, and optional PHPStan, all in one job with one cached Composer install. It is the site shape, with no test suite; a plugin repository uses [php-checks.yml](php-checks.md) instead.

## Example

```yaml
name: CI
on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - "**.php"
      - "composer.lock"
      - "phpcs.xml"

permissions:
  contents: read

jobs:
  lint:
    uses: linchpin/actions/.github/workflows/lint.yml@v4
    secrets:
      PACKAGIST_COMPOSER_AUTH_JSON: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}
    with:
      # Your own code. After Composer install the tree also holds
      # third-party plugins, whose syntax is not yours to police.
      lint_paths: themes/my-theme plugins/my-functionality
      run_phpstan: true
```

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Check out the full history","content":"\u003cp\u003e\u003ccode\u003efetch-depth: 0\u003c/code\u003e, so the PR's changed files can be diffed against its base.\u003c/p\u003e"},{"title":"Install PHP and Composer dependencies","content":"\u003cp\u003eThrough \u003ccode\u003esetup-wp-php\u003c/code\u003e: PHP from \u003ccode\u003ephp_version\u003c/code\u003e, else \u003ccode\u003evars.PHP_VERSION\u003c/code\u003e; dev dependencies included; \u003ccode\u003ePACKAGIST_COMPOSER_AUTH_JSON\u003c/code\u003e passed as \u003ccode\u003eCOMPOSER_AUTH\u003c/code\u003e.\u003c/p\u003e"},{"title":"Syntax lint","content":"\u003cp\u003e\u003ccode\u003ecomposer lint:php\u003c/code\u003e when the project defines that script, otherwise \u003ccode\u003evendor/bin/parallel-lint\u003c/code\u003e over \u003ccode\u003elint_paths\u003c/code\u003e with every \u003ccode\u003evendor/\u003c/code\u003e and \u003ccode\u003enode_modules/\u003c/code\u003e excluded at any depth.\u003c/p\u003e"},{"title":"PHPCS on changed files","content":"\u003cp\u003ePull requests only. \u003ccode\u003evendor/bin/phpcs\u003c/code\u003e over the PHP files the PR added or changed, piped through \u003ccode\u003ecs2pr\u003c/code\u003e so findings annotate the diff. Errors fail the job; warnings only annotate.\u003c/p\u003e"},{"title":"PHPStan, when asked","content":"\u003cp\u003eWith \u003ccode\u003erun_phpstan: true\u003c/code\u003e: \u003ccode\u003ecomposer lint:phpstan\u003c/code\u003e when defined, otherwise \u003ccode\u003evendor/bin/phpstan analyse --no-progress --memory-limit=2G\u003c/code\u003e.\u003c/p\u003e"}]} /-->

## What the project provides

The tools are the project's own, from its `composer.json`, so the rules a PR is held to are the rules a developer runs locally.

| Check | Looked for | When it is missing |
| --- | --- | --- |
| Syntax | A `lint:php` Composer script, else `vendor/bin/parallel-lint` (`php-parallel-lint/php-parallel-lint` in `require-dev`) | Fails, unless `require_tools: false` |
| Coding standards | `vendor/bin/phpcs` (`linchpin/coding-standards` in `require-dev`) | Fails, unless `require_tools: false` |
| PHPStan | A `lint:phpstan` Composer script, else `vendor/bin/phpstan` | Skipped with a warning; `require_tools` does not apply |

<!-- wp:docspress/callout {"tone":"warning","title":"A skipped gate reports green","content":"\u003cp\u003eWith the default \u003ccode\u003erequire_tools: true\u003c/code\u003e, a project without \u003ccode\u003ephp-parallel-lint\u003c/code\u003e or \u003ccode\u003ephpcs\u003c/code\u003e fails instead of skipping the check. Set it to \u003ccode\u003efalse\u003c/code\u003e only while the project is being moved onto its own tooling.\u003c/p\u003e","collapsible":false} /-->

## Behaviour notes

- **PHPCS runs on pull requests only.** It diffs `--diff-filter=ACMRT` PHP files against the PR's base commit. A push runs syntax lint and PHPStan, and a PR that changes no PHP skips PHPCS.
- **Warnings annotate but never fail.** phpcs runs with `ignore_warnings_on_exit` and `cs2pr --graceful-warnings`. A sniff that should block has to be raised to an error in the project's ruleset.
- **Third-party code is excluded from syntax lint.** Every `vendor/` and `node_modules/` below `lint_paths` is skipped, at any depth, including the `plugins/*/vendor` directories Composer creates.
- **No auto-fixing.** phpcbf is not a CI step; run it locally, ideally from a pre-commit hook.
- The job times out after 10 minutes.

See [PR checks](../guides/pr-checks.md) for how this fits with the other pull-request workflows.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"php_version","type":"string","required":false,"defaultValue":"","description":"PHP version. Defaults to vars.PHP_VERSION","values":"","deprecated":false},{"name":"run_phpstan","type":"boolean","required":false,"defaultValue":"false","description":"Also run PHPStan (composer lint:phpstan or vendor/bin/phpstan)","values":"","deprecated":false},{"name":"lint_paths","type":"string","required":false,"defaultValue":".","description":"Space-separated paths to syntax-lint. Defaults to the whole repository. A wp-content-shaped repo wants its own theme or plugin here — after Composer install the tree also holds third-party plugin code, whose syntax is not ours to police.","values":"","deprecated":false},{"name":"require_tools","type":"boolean","required":false,"defaultValue":"true","description":"Fail when php-parallel-lint or phpcs is missing, rather than skipping the check. A skipped gate reports green, which is worse than no gate because it looks like one. Set false only while a project is being migrated onto its own tooling.","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"PACKAGIST_COMPOSER_AUTH_JSON","type":"string","required":false,"defaultValue":"","description":"auth.json contents for packagist.linchpin.com (v4 passes this via the COMPOSER_AUTH env)","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `lint` | `contents: read` |

## Source

[`.github/workflows/lint.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/lint.yml)
