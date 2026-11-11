---
title: build-release
---

`build-release` copies a built project into a clean `release/` directory, leaving out everything the project's `.distignore` lists. It is the step that decides what ships: [`build.yml`](../workflows/build.md) runs it after the theme and plugin builds and zips the result.

## Example

```yaml
- name: Assemble release directory
  uses: linchpin/actions/actions/build-release@v4
  with:
    remote-plugin-install: ${{ vars.REMOTE_PLUGIN_INSTALL }}
```

## How it works

1. Reads `<source-directory>/.distignore`. Without one it warns `No .distignore found in the project — using the bundled default. Add one to your project.` and uses the bundled [`default.distignore`](https://github.com/linchpin/actions/blob/main/actions/build-release/default.distignore).
2. With `remote-plugin-install: true` it reshapes the release for [remote plugin install](../guides/remote-plugin-install.md): see below.
3. Adds `.git`, `.github`, `node_modules/`, `auth.json` and the target directory itself to the exclusions, whatever the `.distignore` says.
4. Runs `rsync -rcq --exclude-from=<list> --delete` from the source into the target, then prints the release size and its top-level directories.

The `.distignore` lines are rsync exclude patterns. `--delete` means anything already in the target that the source lacks is removed.

## Remote plugin install

With `remote-plugin-install: true` the release carries the project's own code plus the lock, and the server installs everything else:

- `composer.json` and `composer.lock` are taken off the exclusion list, so they ship.
- `composer.lock` must exist at the source root, or the step fails with `REMOTE_PLUGIN_INSTALL is true but no composer.lock was found at <path>`.
- Every `wordpress-plugin` and `wordpress-theme` package in the lock that has a dist URL is excluded as `/plugins/<slug>/` or `/themes/<slug>/`, where the slug is the part of the package name after the `/`. A source-only package, typically a `dev-*` VCS branch, has no zip for WP-CLI to install from, so it keeps shipping.

## The bundled default

[`default.distignore`](https://github.com/linchpin/actions/blob/main/actions/build-release/default.distignore) leaves out version-control and editor files, `node_modules/`, `bower_components/` and `scss/`, build and lint config (`Gruntfile.js`, `gulpfile.js`, `phpunit.xml`, `phpcs.xml`), `auth.json`, WordPress runtime paths (`uploads/`, `cache/*`, `upgrade/*`, `advanced-cache.php`, `object-cache.php`) and WP Engine platform files. It is a fallback: give each project its own `.distignore`.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"source-directory","type":"string","required":false,"defaultValue":".","description":"Directory containing the built project","values":"","deprecated":false},{"name":"target-directory","type":"string","required":false,"defaultValue":"release","description":"Directory to write the cleaned release into","values":"","deprecated":false},{"name":"remote-plugin-install","type":"string","required":false,"defaultValue":"false","description":"When 'true', composer.json/composer.lock are kept in the release so the server can install plugins remotely","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/build-release/action.yml), [`cleanup.sh`](https://github.com/linchpin/actions/blob/main/actions/build-release/cleanup.sh), [`default.distignore`](https://github.com/linchpin/actions/blob/main/actions/build-release/default.distignore)
