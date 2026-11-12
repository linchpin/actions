---
title: unmanaged-plugins
---

`unmanaged-plugins` lists the plugins on a server that the repository does not manage, and says what to do about each. [`deploy.yml`](../workflows/deploy.md) and [`deploy-continue.yml`](../workflows/deploy-continue.md) run it after every successful deploy.

A plugin installed by hand on one environment never reaches the others, because no deploy ships it. A development site that copies that environment's database also lists it as active without its files, and the [health check](deploy-pressable.md) then fails Deploy to Dev. ideainfanttoddler hit exactly that with MCP Adapter, installed from wp-admin on production. This action reports such a plugin on the first deploy after it appears.

It only reports. Each plugin gets a warning and a row in the step summary, and the deploy never fails because of it.

## What counts as managed

A plugin on the server is managed when it is any of:

- **Shipped in `release.zip`**, as `plugins/<slug>/` or `plugins/<slug>.php`.
- **In the release's `composer.lock`**, as a `wordpress-plugin` package. With `REMOTE_PLUGIN_INSTALL`, [remote-plugin-install](remote-plugin-install.md) puts those on the server instead of the release.
- **A symlink on the server**, which is the host's own, like Pressable's Jetpack.
- **Covered by `PROTECTED_PATHS`**, or always managed by the host. On Pressable those are `plugins/jetpack`, `plugins/akismet` and `plugins/automattic-for-agencies-client`, which Pressable installs on every site.

Everything else is reported. Must-use plugins and drop-ins are not checked.

## What it says

For each plugin, the warning names it, its version and whether it is active, then gives three ways out:

1. **The site uses it:** add it to the repo. The message has the command. When [wp-packages.org](https://wp-packages.org) has the plugin, that is `composer require wp-plugin/<slug>:<version>`, at the version on the server when the registry has it. Otherwise it is `composer require linchpin/<slug>:<version>`, once the plugin is mirrored on packagist.linchpin.com.
2. **The host installs it on every environment**, like Pressable's Jetpack: add `plugins/<slug>` to `PROTECTED_PATHS`. See [Host-managed folders](../guides/host-managed-folders.md). This only fits a plugin every environment has. A plugin installed by hand on production alone is still missing on dev, so protecting it does not stop dev's health check failing.
3. **It isn't needed:** deactivate and delete it on that environment.

On a production site, the warning for an active plugin also says that a development copy of the database will fail its deploy health check. At most eight warnings are raised, which keeps under GitHub's ten per step; the step summary always has every plugin.

On Cloudways the sync replaces `plugins/` as one tree with `--delete`, so a hand-installed plugin is removed by the deploy itself unless it is protected. This check therefore rarely finds anything there.

## Example

As `deploy.yml` runs it, after the host action and remote plugin install:

```yaml
- name: Report plugins the repository doesn't manage
  if: ${{ success() }}
  continue-on-error: true
  timeout-minutes: 5
  uses: linchpin/actions/actions/unmanaged-plugins@v4
  with:
    host: ${{ vars.HOST }}
    ssh-host: ${{ secrets.SSH_HOST }}
    ssh-user: ${{ secrets.SSH_USER }}
    ssh-key: ${{ secrets.SSH_KEY }}
    wp-path: /srv/htdocs
    release-archive: ${{ github.workspace }}/release.zip
    protected-paths: ${{ steps.protected.outputs.paths }}
    environment: ${{ inputs.environment }}
```

## How it works

1. Lists the release's `plugins/` entries and, when the release carries `composer.lock`, its `wordpress-plugin` packages.
2. Reads the server in one SSH call: `wp plugin list` with `--skip-plugins --skip-themes`, so a plugin's fatal error cannot hide the list; the environment type; and the symlinks in `wp-content/plugins`.
3. Takes out everything managed, then looks each remaining plugin up on `registry-url` to name the package to require.
4. Writes a warning per plugin, the step summary, and the `count` and `unmanaged` outputs.

Anything it cannot read, such as the release zip, the SSH connection or WP-CLI's output, skips the check with a notice and an empty `count`.

## Run it locally

The script reads everything from the environment. With an SSH alias for the site in `~/.ssh/config`:

```bash
SSH_ALIAS=my-site HOST=pressable WP_PATH=/srv/htdocs \
  RELEASE_ARCHIVE=release.zip ENVIRONMENT_LABEL=production \
  actions/unmanaged-plugins/unmanaged-plugins.sh
```

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"host","type":"string","required":false,"defaultValue":"","description":"The deploy host: pressable, wpengine or cloudways. Pressable's jetpack, akismet and Automattic for Agencies client always count as managed by the host.","values":"","deprecated":false},{"name":"ssh-host","type":"string","required":true,"defaultValue":"","description":"SSH host","values":"","deprecated":false},{"name":"ssh-user","type":"string","required":true,"defaultValue":"","description":"SSH user","values":"","deprecated":false},{"name":"ssh-key","type":"string","required":true,"defaultValue":"","description":"SSH private key. Password auth is not supported.","values":"","deprecated":false},{"name":"wp-path","type":"string","required":true,"defaultValue":"","description":"Absolute (or ~-relative) path to the WordPress root on the server. Pressable: /srv/htdocs. WP Engine: ~/sites/\u003cinstall\u003e. Cloudways: ~/public_html.","values":"","deprecated":false},{"name":"release-archive","type":"string","required":true,"defaultValue":"","description":"Path to the release.zip that was just deployed, on the runner","values":"","deprecated":false},{"name":"protected-paths","type":"string","required":false,"defaultValue":"","description":"Paths managed outside the repo, relative to wp-content: the same value the deploy actions take","values":"","deprecated":false},{"name":"environment","type":"string","required":false,"defaultValue":"this environment","description":"The environment's name, for the messages (e.g. production)","values":"","deprecated":false},{"name":"registry-url","type":"string","required":false,"defaultValue":"https://wp-packages.org","description":"The Composer repository that serves WordPress.org plugins as wp-plugin/\u003cslug\u003e, used to suggest the package to require","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Outputs

<!-- wp:docspress/fields {"title":"Outputs","fields":[{"name":"count","type":"string","required":false,"defaultValue":"","description":"How many unmanaged plugins were found; empty when the check was skipped","values":"","deprecated":false},{"name":"unmanaged","type":"string","required":false,"defaultValue":"","description":"JSON array of {slug, title, version, status, package} for each unmanaged plugin","values":"","deprecated":false}],"searchable":false,"compact":true} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/unmanaged-plugins/action.yml), [`unmanaged-plugins.sh`](https://github.com/linchpin/actions/blob/main/actions/unmanaged-plugins/unmanaged-plugins.sh)
