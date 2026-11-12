---
title: Host-managed folders
---

Managed hosts serve some plugins from storage the platform owns and link them
into the site: on Pressable, `jetpack` and `woocommerce` are usually symlinks in
`wp-content/plugins` rather than real folders. Syncing a release onto such a path
is destructive either way. rsync follows the link and writes through it, so
`--delete` prunes files the platform owns, or the link is replaced by a real
directory and the site silently stops receiving platform updates. Every v4
deploy leaves those paths alone, and `PROTECTED_PATHS` extends the same
treatment to real folders that something other than the repository manages.

## What every deploy does

Nothing needs configuring for this. Before syncing, the server-side entrypoint
of [deploy-pressable](../composite-actions/deploy-pressable.md),
[deploy-wpengine](../composite-actions/deploy-wpengine.md) and
[deploy-cloudways](../composite-actions/deploy-cloudways.md):

1. Prints every symlink under `wp-content`, two levels deep, with its target.
2. Skips any `plugins/`, `themes/` or `mu-plugins/` entry that is a symlink on
   the server, or that matches a protected path.
3. Annotates each skip, and warns when the release actually ships a path that
   was skipped only because it is a symlink.
4. Lists everything it left untouched in a closing summary.

How a skip is applied depends on how the host syncs:

| Host | `plugins/`, `themes/` | `mu-plugins/` | Always protected |
| --- | --- | --- | --- |
| Pressable | One rsync per folder; skipped folders are not synced at all | One tree; skipped entries become `--exclude` rules | `plugins/jetpack`, `plugins/akismet` |
| WP Engine | One rsync per folder | One tree, with excludes | — |
| Cloudways | One tree each, with excludes | One tree, with excludes | — |

The difference matters for folders the release does not ship. Synced one folder
at a time, a plugin the release lacks is never visited, so it survives. Synced as
a tree with `--delete`, as on Cloudways, it is removed unless it is a symlink or
protected. `mu-plugins/` is a tree on every host, because its files sit at the
root rather than one folder per plugin, and without the excludes `--delete`
would remove the host's own mu-plugins.

## Protect a real folder

Set `PROTECTED_PATHS`, as a repository or environment variable, when a path is
a real folder today but is still managed outside the repository: a client
installs it from wp-admin, another pipeline owns it, or a vendor ships it
directly. Any of these forms works:

<!-- wp:docspress/code-tabs {"tabs":[{"label":"Comma separated","language":"plaintext","filename":"PROTECTED_PATHS","code":"plugins/some-client-managed-plugin, plugins/woocommerce*"},{"label":"JSON array","language":"json","filename":"PROTECTED_PATHS","code":"[\"plugins/some-client-managed-plugin\", \"themes/legacy\"]"},{"label":"One per line","language":"plaintext","filename":"PROTECTED_PATHS","code":"# client installs this from wp-admin\nplugins/some-client-managed-plugin\nthemes/legacy"}],"showLineNumbers":false,"caption":"Three equivalent ways to write the variable."} /-->

- Paths are relative to `wp-content`. Surrounding whitespace, quotes and
  leading or trailing slashes are trimmed.
- Globs are allowed: `plugins/woocommerce*`.
- A bare name with no slash matches that folder under `plugins/`, `themes/` or
  `mu-plugins/`, so `woocommerce` covers `plugins/woocommerce`.
- A line starting with `#` is a comment. Keep comments on their own line: the
  deploy sync also strips a trailing `# …`, but the
  [remote plugin install](remote-plugin-install.md) reconcile does not, so a path
  followed by a comment protects nothing there.

## A plugin on the server but not in the repo

After every deploy, [unmanaged-plugins](../composite-actions/unmanaged-plugins.md)
warns about each plugin on the server that the release doesn't ship, its
`composer.lock` doesn't list, and isn't a symlink or a protected path, with
what to do: add it to the repo, protect it, or remove it.

Protect it only when the host, or something else, puts it on **every**
environment, the way Pressable puts Jetpack on every site. Protection stops a
deploy from overwriting a plugin that is on that server; it can't put one on a
server that never had it. A plugin installed by hand on production is missing
on development, and because development's database is a copy of production's,
the plugin is active there without its files. Pressable's health check then
fails Deploy to Dev with `Active but not on disk`, protected or not. Add a
plugin like that to the repo instead.

## Override it for one deploy

[deploy.yml](../workflows/deploy.md) takes two inputs for this:

- `protected_paths` replaces `vars.PROTECTED_PATHS` for that deploy.
- `preserve_symlinks: false` turns symlink detection off. Use it only when a
  deploy is meant to replace symlinks with real directories.

```yaml
jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: production
      protected_paths: plugins/some-client-managed-plugin
```

## Where else the list applies

- **Remote plugin install** checks every Composer package against the server's
  symlinks and the same protected paths before installing it, because WP-CLI,
  like Composer's `installer-paths`, would replace a symlink with a real
  directory. See [Remote plugin install](remote-plugin-install.md).
- **Safety Net** adds `mu-plugins/safety-net` and
  `mu-plugins/safety-net-loader.php` to the list on a `safety_net` deploy, so the
  `mu-plugins` sync does not delete it. See
  [Safety Net on development](safety-net-on-development.md).
- **Cloudways legacy links.** A `wp-content/themes`, `plugins` or `mu-plugins`
  symlink pointing into `private_html` or a release directory is a leftover from
  the old deploy process and is removed. Any other symlink at those paths is left
  in place with a notice.

## Reading the log

| Log line | Meaning |
| --- | --- |
| `ℹ︎ Symlinks detected under … (this deploy will not overwrite them):` | The list of links on the server, with targets. Copy paths from here into `PROTECTED_PATHS`. |
| `⤵︎ plugins/x left untouched — platform symlink → …` | A symlink the release does not ship. Nothing to do. |
| `⤵︎ plugins/x ships in this release but was not deployed — protected by configuration` | Protected on purpose, and the release carries it anyway. |
| `⤵︎ plugins/x ships in this release but was NOT deployed — platform symlink → … Add it to PROTECTED_PATHS to make this explicit.` | A warning: the build expected this folder to land. Either stop shipping it, or protect it so the skip is deliberate. |
| `ℹ︎ N path(s) left untouched on the server:` | The closing summary. |
