---
title: Remote plugin install
---

By default a deploy ships everything: the build resolves Composer, and the
release zip carries every third-party plugin and theme. `REMOTE_PLUGIN_INSTALL=true`
inverts that for the Composer-managed part. The release carries only the
project's own code plus `composer.json` and `composer.lock`, and after the sync
the deploy brings the server in line with the lock, one WP-CLI call per package.

## What actually gets faster

Not the build. Composer was never the slow part, since its cache is keyed on
`composer.lock`, and the npm theme and plugin builds that dominate still run on
the runner. What shrinks is everything after the build: the release zip, the
transfer, the copy attached to the GitHub release for rollbacks, the two zips
kept on the server, and the sync itself. A Renovate bump of one plugin becomes
one `wp plugin install` instead of re-syncing the whole tree.

## Turn it on

Set the variable on the repository, and the registry credentials when the lock
pulls from packagist.linchpin.com:

```
REMOTE_PLUGIN_INSTALL = true
SATISPRESS_USER / SATISPRESS_PASSWORD   # only for packagist.linchpin.com
```

No caller changes. [deploy.yml](../workflows/deploy.md) and
[deploy-continue.yml](../workflows/deploy-continue.md) read the variable and
pass the two secrets through `secrets: inherit`.

## End to end

<!-- wp:docspress/diagram {"title":"Remote plugin install","type":"sequence","source":"build.yml -\u003e release.zip: project code + composer.json/composer.lock\ndeploy.yml -\u003e Server: host action syncs release.zip\ndeploy.yml -\u003e deploy.yml: unzip composer.lock from release.zip\ndeploy.yml -\u003e Server: read installed plugins, themes and symlinks\ndeploy.yml -\u003e Server: wp plugin|theme install \u003cdist url\u003e --force, per package\ndeploy.yml -\u003e Server: read again and verify against composer.lock","caption":"The build ships the lock instead of the packages; the deploy reconciles the server against it."} /-->

1. **Build.** [build.yml](../workflows/build.md) still sets up PHP, but skips
   the root `composer install`, since everything it would install is about to be
   left out. [build-release](../composite-actions/build-release.md) keeps
   `composer.json` and `composer.lock` in the release, and excludes
   `plugins/<slug>/` or `themes/<slug>/` for every lock package of type
   `wordpress-plugin` or `wordpress-theme` that has a dist archive. Theme and
   plugin npm builds run as before.
2. **Sync.** The host action ships the smaller release like any other.
3. **Reconcile.** `deploy.yml` unzips `composer.lock` from `release.zip` and runs
   [remote-plugin-install](../composite-actions/remote-plugin-install.md), which
   installs what is missing, reinstalls anything at a different version, and then
   verifies the server against the lock.

Because the lock travels inside `release.zip`, a rollback with `release_tag`
reconciles against that release's lock. The lock is the source of truth in both
directions: a package ahead of it is reinstalled at the locked version, so a
rollback downgrades third-party plugins instead of leaving them ahead of the
code.

## Why not `composer install` over SSH

Pressable's Composer guide documents an "SSH build" that runs `composer install`
in the container. This repository deliberately does not: managed containers cap
a single exec at about 300 seconds, which a cold Composer install for a
WooCommerce-scale project does not reliably fit inside, and it would die
mid-write. One short WP-CLI call per package stays far inside the cap, keeps
Composer and registry credentials off the server, and leaves resolution on the
runner.

## Requirements and caveats

- **Per-plugin autoloaders only.** There is no root `vendor/` in the release and
  nothing creates one on the server. A project that depends on a root
  autoloader should not enable this.
- **Packages need a dist archive.** A source-only requirement, typically a
  `dev-*` VCS branch, has no zip for WP-CLI to install, so it stays in the
  release and arrives over rsync. This is automatic.
- **Only plugins and themes.** Packages of any other type are neither dropped
  from the release nor reconciled.
- **Key auth only.** Cloudways with `DEPLOYMENT_AUTH_TYPE=pass` fails the deploy
  rather than skipping the reconcile.
- **Symlinks and `PROTECTED_PATHS` are respected.** A package whose folder is a
  platform symlink or protected is skipped and logged, so a lock that lists
  `wpackagist-plugin/woocommerce` does not fight a Pressable-managed WooCommerce.
  See [Host-managed folders](host-managed-folders.md).
- **New packages install inactive,** and the run warns with their names.
- **Nothing is removed.** A package dropped from `composer.lock` stays on the
  server; remove it there yourself.

<!-- wp:docspress/callout {"tone":"warning","title":"Maintenance mode and post_deploy_command run before the reconcile","content":"\u003cp\u003eBoth belong to the host action, which finishes before the reconcile starts. Pressable's maintenance mode is already off when \u003ccode\u003ewp plugin install --force\u003c/code\u003e replaces a plugin directory, and WP Engine and Cloudways never receive \u003ccode\u003emaintenance_mode\u003c/code\u003e. A \u003ccode\u003epost_deploy_command\u003c/code\u003e that activates a package cannot activate one this same deploy installs for the first time.\u003c/p\u003e","collapsible":false} /-->

<!-- wp:docspress/callout {"tone":"warning","title":"Cloudways reinstalls on every deploy","content":"\u003cp\u003eCloudways syncs \u003ccode\u003eplugins/\u003c/code\u003e and \u003ccode\u003ethemes/\u003c/code\u003e as whole trees with \u003ccode\u003e--delete\u003c/code\u003e. The release no longer carries the Composer-managed packages, so unless they are symlinks or protected, the sync removes them and the reconcile installs them again, and they are missing from the site in between.\u003c/p\u003e","collapsible":false} /-->

## Troubleshooting

| Message | Cause and fix |
| --- | --- |
| `REMOTE_PLUGIN_INSTALL is true but no composer.lock was found at …` | The build found no lock at the project root. Commit `composer.lock`. |
| `composer.lock is not in release.zip.` | The project `.distignore` still excludes it, for example with a wildcard. Lines naming `composer.json` or `composer.lock` are removed automatically; broader patterns are not. |
| `REMOTE_PLUGIN_INSTALL is not supported with DEPLOYMENT_AUTH_TYPE=pass (password SSH).` | Switch the Cloudways server to key auth, or unset the variable. |
| `Could not enter … on the server` | `wp-path` does not exist for this SSH user. |
| `Could not parse 'wp plugin list' output from the server. Is WP-CLI available at …?` | WP-CLI did not answer in the WordPress root. |
| `Install failed: plugin/x@1.2.3` | `wp plugin install` failed for that package; the warning above it carries WP-CLI's output. Check the dist URL and, for packagist.linchpin.com, `SATISPRESS_USER` and `SATISPRESS_PASSWORD`. |
| `Version mismatch after install: plugin/x — expected 1.2.3, not present after install (…)` | The archive's top-level folder is not named after the package, so WP-CLI installed it somewhere else. |
| `Version mismatch after install: plugin/x — expected 1.2.3, server reports 1.2.2` | The archive at the dist URL is not the version the lock records. |
| `Newly installed and NOT activated: …` | A warning, not a failure. Activate them in wp-admin or with WP-CLI. |
