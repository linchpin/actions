---
title: setup-wp-php
---

`setup-wp-php` pins PHP with `shivammathur/setup-php`, restores Composer's download cache keyed on `composer.lock`, and runs `composer install` with registry credentials passed through the `COMPOSER_AUTH` environment variable, so no `auth.json` is ever written to disk. [`build.yml`](../workflows/build.md), [`lint.yml`](../workflows/lint.md), [`php-checks.yml`](../workflows/php-checks.md) and [`plugin-check.yml`](../workflows/plugin-check.md) all start with it.

## Example

```yaml
steps:
  - uses: actions/checkout@v6
  - uses: linchpin/actions/actions/setup-wp-php@v4
    with:
      php-version: '8.4'
      composer-auth: ${{ secrets.PACKAGIST_COMPOSER_AUTH_JSON }}
      dev: 'yes' # tests and linters need require-dev
```

## How it works

1. Installs PHP `php-version` with the given `extensions`, `ini-values` and `tools`, and code coverage off.
2. Finds Composer's download cache directory (`composer config --global cache-files-dir`, else `~/.cache/composer/files`).
3. Restores and saves that directory under `composer-<os>-php<version>-<hash of composer.lock>`, falling back to the newest cache for the same OS and PHP version. It caches Composer's downloads, not `vendor/`.
4. Unless `install` is `false`, runs `composer install <composer-args>` in `working-directory`, adding `--no-dev --optimize-autoloader` when `dev` is `no`.

## Behaviour to know

- **Production by default.** `dev` defaults to `no`, so require-dev packages are not installed. Pass `yes` for anything that runs tests or linters.
- **No `composer.json`, no install.** The step notes `No composer.json in '<directory>' — skipping Composer install` and succeeds.
- **`install: false`** gives the pinned PHP and a warm cache without installing anything. `build.yml` uses it when `REMOTE_PLUGIN_INSTALL` is `true`, since the server installs those packages.
- **Blacksmith and Depot runners.** They register as self-hosted, so `setup-php` would install a missing PHP through apt. On a runner whose name starts with `blacksmith-` or `depot-`, the action turns on `setup-php`'s experimental `use_builds_cache` so it unpacks a prebuilt PHP instead; on any other runner the setting stays off. See [Choosing a runner](../getting-started/choosing-a-runner.md).
- **`composer-args` is split on spaces**, so pass flags, not quoted values containing spaces.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"php-version","type":"string","required":true,"defaultValue":"","description":"PHP version to install (e.g. 8.5)","values":"","deprecated":false},{"name":"working-directory","type":"string","required":false,"defaultValue":".","description":"Directory containing composer.json","values":"","deprecated":false},{"name":"dev","type":"string","required":false,"defaultValue":"no","description":"Install dev dependencies (yes/no). 'no' adds --no-dev --optimize-autoloader","values":"","deprecated":false},{"name":"composer-args","type":"string","required":false,"defaultValue":"--prefer-dist --no-progress --no-interaction","description":"Base arguments passed to composer install","values":"","deprecated":false},{"name":"composer-auth","type":"string","required":false,"defaultValue":"","description":"JSON for the COMPOSER_AUTH env var (e.g. the PACKAGIST_COMPOSER_AUTH_JSON secret)","values":"","deprecated":false},{"name":"extensions","type":"string","required":false,"defaultValue":"","description":"PHP extensions for shivammathur/setup-php (e.g. dom, libxml, mbstring)","values":"","deprecated":false},{"name":"ini-values","type":"string","required":false,"defaultValue":"","description":"php.ini values for shivammathur/setup-php (e.g. zend.assertions=1)","values":"","deprecated":false},{"name":"tools","type":"string","required":false,"defaultValue":"composer, cs2pr","description":"Tools for shivammathur/setup-php","values":"","deprecated":false},{"name":"install","type":"string","required":false,"defaultValue":"true","description":"Run the Composer install (true/false). Set false to get the pinned PHP and a warm Composer cache without installing — used by the remote-plugin-install build, where the server resolves packages from composer.lock and installing them on the runner would only be thrown away.","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/setup-wp-php/action.yml)
