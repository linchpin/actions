---
title: build.yml
---

`build.yml` builds a wp-content-shaped project in one job — the root Composer install, every listed theme and plugin — and uploads a single deploy-ready `release.zip` as the `release` artifact. [`deploy.yml`](deploy.md) calls it for every deploy except a `release_tag` redeploy, so call it directly only when you want the artifact without a deploy.

## Example

```yaml
permissions:
  contents: write # build.yml declares it, for attaching release.zip

jobs:
  build:
    uses: linchpin/actions/.github/workflows/build.yml@v4
    secrets: inherit
    with:
      themes: '["linchpin"]'
      plugins: '["linchpin-functionality"]'
```

## How it works

1. **PHP and the root install.** [`setup-wp-php`](../composite-actions/setup-wp-php.md) pins PHP (`php_version`, else `vars.PHP_VERSION`) and runs `composer install --no-dev` at the repository root. With `REMOTE_PLUGIN_INSTALL=true` PHP is still pinned and the Composer cache warmed, but nothing is installed: the server resolves those packages itself.
2. **Node.** `node_version`, else `vars.NODE_VERSION`, with the npm cache when any `themes/*/`, `plugins/*/` or `plugins/*/blocks/` `package-lock.json` exists.
3. **Private npm packages.** With `NPM_READ_TOKEN`, the token goes in a job-scoped npm user config under `RUNNER_TEMP`, never `~/.npmrc`. Without it, public packages install as before.
4. **Build list check.** See [Unlisted packages](#unlisted-packages) below.
5. **Themes.** For each name in `themes` (else `vars.THEMES`): `composer install --no-dev` when `THEME_USES_COMPOSER` is `true` and the theme has a `composer.lock`, then `npm ci` and `npm run build` when it has a `package-lock.json`.
6. **Plugins.** For each name in `plugins` (else `vars.PLUGINS`): `npm ci` and `npm run build`, then `composer install --no-dev` when `PLUGIN_USES_COMPOSER` is `true` and the plugin has a `composer.lock`. Composer runs after npm so the runtime `vendor/` ships.
7. **`build_commands`**, when set, run from the repository root.
8. **Assemble.** [`build-release`](../composite-actions/build-release.md) copies the tree into `release/` through the project's `.distignore`.
9. **Package once.** `release/` is zipped with its contents at the zip root and uploaded as the `release` artifact, stored without recompression and kept for one day.
10. **Archive.** With `release_tag`, the same zip is uploaded to that already-published release with `gh release upload --clobber`, so a later rollback can deploy it without rebuilding.

## Build configuration is repository-level

The build job binds no GitHub environment, on purpose: binding one subjects the job to the environment's branch rules, which rejected release builds running from `main`. Environment-scoped variables are therefore invisible here. Set `THEMES`, `PLUGINS`, `PHP_VERSION`, `NODE_VERSION`, `THEME_USES_COMPOSER`, `PLUGIN_USES_COMPOSER` and `REMOTE_PLUGIN_INSTALL` on the repository or organization.

The `*_USES_COMPOSER` installs run only when the variable is exactly `true`. An unset `PLUGIN_USES_COMPOSER` skips every plugin's Composer install.

## Unlisted packages

A directory listed in `THEMES` or `PLUGINS` that does not exist fails the build (`Theme directory themes/<name> not found`). The opposite mistake is quieter: a theme or plugin that needs building but was never listed is skipped, and the release ships it with no `build/` or `vendor/`.

The build list check catches that. A package counts as buildable when it is tracked in git **and** has a `package-lock.json` or `composer.lock`; Composer-installed packages are gitignored and arrive prebuilt, so they are correctly left out. Each unlisted one is annotated:

```text
<name> is tracked in git and has a lockfile, but is not listed in PLUGINS — it will not be built, so the release would ship it without build/ or vendor/. Add it to the PLUGINS repository variable.
```

It warns by default. Set the repository variable `STRICT_BUILD_LIST` to `true` to fail the build instead, once the repository's lists are known good.

## Other behaviour

- **No `composer validate`.** release-please bumps the `version` in `composer.json` on every release without rebuilding the lock, which `composer validate` rejects. `composer install` tolerates it, and still fails when a locked version no longer satisfies `composer.json`.
- **Linux sass binary.** When a theme's `package.json` or lockfile mentions `sass-embedded`, the build also runs `npm install --no-save sass-embedded-linux-x64`, since lockfiles generated on macOS can omit it.
- **`node_modules` is left in place.** `build-release` excludes it, so it never ships.
- **Artifact lifetime.** The `release` artifact is kept for one day. A `release_tag` rollback reads the copy archived on the release instead.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"themes","type":"string","required":false,"defaultValue":"","description":"JSON array of theme folder names. Defaults to vars.THEMES. Example: [\"linchpin\"]","values":"","deprecated":false},{"name":"plugins","type":"string","required":false,"defaultValue":"","description":"JSON array of plugin folder names. Defaults to vars.PLUGINS. Example: [\"linchpin-functionality\"]","values":"","deprecated":false},{"name":"php_version","type":"string","required":false,"defaultValue":"","description":"PHP version. Defaults to vars.PHP_VERSION","values":"","deprecated":false},{"name":"node_version","type":"string","required":false,"defaultValue":"","description":"Node version. Defaults to vars.NODE_VERSION","values":"","deprecated":false},{"name":"build_commands","type":"string","required":false,"defaultValue":"","description":"Optional additional shell commands to run after the standard build (multi-line)","values":"","deprecated":false},{"name":"release_tag","type":"string","required":false,"defaultValue":"","description":"When set, attach the built release.zip to this existing GitHub release as a deployable archive (rollback source)","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"PACKAGIST_COMPOSER_AUTH_JSON","type":"string","required":false,"defaultValue":"","description":"auth.json contents for packagist.linchpin.com (passed via COMPOSER_AUTH, never written to disk)","values":"","deprecated":false},{"name":"NPM_READ_TOKEN","type":"string","required":false,"defaultValue":"","description":"Read-only npmjs.com token, for themes and plugins that depend on private @linchpinagency packages","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Outputs

<!-- wp:docspress/fields {"title":"Outputs","fields":[{"name":"artifact","type":"string","required":false,"defaultValue":"","description":"Name of the uploaded release artifact","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `build` | `contents: write` |

## Source

[`.github/workflows/build.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/build.yml)
