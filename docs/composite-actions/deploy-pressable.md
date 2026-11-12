---
title: deploy-pressable
---

Ships a built release to a Pressable site over SSH, syncs it into `wp-content`
without touching symlinked or protected folders, and then checks that WordPress
loads and the site answers before the deploy counts as a success.
[deploy.yml](../workflows/deploy.md) runs it when the `HOST` variable is
`pressable`, and [deploy-continue.yml](../workflows/deploy-continue.md) runs it to
finish a `do_backup` deploy. You rarely call it yourself.

## Example

The entry point is `deploy.yml`, with `HOST=pressable`, `SITE_ID` and `SITE_URL`
set as variables and the SSH and Pressable API credentials as secrets (see
[Secrets and variables](../getting-started/secrets-and-variables.md)):

```yaml
jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: staging
```

This is what `deploy.yml` hands the action:

| Input | From |
| --- | --- |
| `site-id`, `site-url` | `vars.SITE_ID`, `vars.SITE_URL` |
| `api-client-id`, `api-client-secret` | the `PRESSABLE_API_CLIENT_ID` and `PRESSABLE_API_CLIENT_SECRET` secrets |
| `ssh-host`, `ssh-user`, `ssh-key` | the `SSH_HOST`, `SSH_USER` and `SSH_KEY` secrets |
| `release-archive` | the `release.zip` the build produced, or the one attached to `release_tag` |
| `maintenance-mode`, `post-deploy-command`, `health-check`, `preserve-symlinks` | the `maintenance_mode`, `post_deploy_command`, `health_check` and `preserve_symlinks` inputs |
| `protected-paths` | the `protected_paths` input, else `vars.PROTECTED_PATHS`, plus Safety Net's two paths when `safety_net` is on |

`trigger-backup` and `deployment-path` stay at their defaults. With `do_backup:
true`, `deploy.yml` skips this action and `deploy-continue.yml` runs it once the
backup completes.

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Authenticate","content":"\u003cp\u003eExchanges the API client for a token at \u003ccode\u003emy.pressable.com\u003c/code\u003e. Fails here if the client is wrong.\u003c/p\u003e"},{"title":"Back up, optionally","content":"\u003cp\u003eWith \u003ccode\u003etrigger-backup: true\u003c/code\u003e, requests a Pressable on-demand backup and carries on without waiting for it.\u003c/p\u003e"},{"title":"Upload","content":"\u003cp\u003eShips the release zip (or zips \u003ccode\u003erelease-directory\u003c/code\u003e), the server entrypoint and the protected-paths list to \u003ccode\u003edeployment-path\u003c/code\u003e, as \u003ccode\u003e&lt;timestamp&gt;.zip\u003c/code\u003e.\u003c/p\u003e"},{"title":"Maintenance mode on","content":"\u003cp\u003eOnly with \u003ccode\u003emaintenance-mode: true\u003c/code\u003e, through the Pressable API.\u003c/p\u003e"},{"title":"Sync on the server","content":"\u003cp\u003eThe entrypoint unzips the release, logs every symlink under \u003ccode\u003ewp-content\u003c/code\u003e, then syncs each plugin and theme folder with its own rsync and \u003ccode\u003emu-plugins\u003c/code\u003e as one tree, skipping symlinks and protected paths. It keeps the two newest release zips and flushes the page cache when \u003ccode\u003ewp page-cache\u003c/code\u003e exists.\u003c/p\u003e"},{"title":"Maintenance mode off","content":"\u003cp\u003eRuns even when the sync failed.\u003c/p\u003e"},{"title":"Post-deploy command","content":"\u003cp\u003eRuns \u003ccode\u003epost-deploy-command\u003c/code\u003e from \u003ccode\u003e/srv/htdocs\u003c/code\u003e.\u003c/p\u003e"},{"title":"Health checks","content":"\u003cp\u003eRuns \u003ccode\u003ewp mantle health\u003c/code\u003e on the server and prints its checks, with an error for each failing one, or just loads WordPress when the site's Mantle predates that command, then requests \u003ccode\u003esite-url\u003c/code\u003e up to 10 times. Any HTTP status below 500 passes.\u003c/p\u003e"}]} /-->

## Behaviour to know

- **Only folders the release ships are synced.** Each plugin and theme is its
  own rsync with `--delete`, so a plugin or theme on the server that the release
  does not contain is left in place. `mu-plugins` is one tree, so `--delete`
  removes any mu-plugin the release no longer ships, unless it is a symlink or
  protected.
- **`jetpack` and `akismet` are always protected** on Pressable, whatever they
  are on disk, and the log says so. See
  [Host-managed folders](../guides/host-managed-folders.md).
- **The health check is the gate.** The entrypoint runs without `set -e`: a
  failed rsync does not stop it, and a release without `plugins/` or `themes/`
  logs `❌ Plugins directory not found at …` as an error annotation without
  failing the step. Leave `health-check` on.
- **The WordPress check runs on the server,** so Cloudflare Access and the CDN
  in front of the site do not hide a fatal error from it.
- **A plugin that is active but not on disk is explained.** The error says
  where the activation came from and what to do. On a development site with
  Safety Net, it says the database is production's, so production has the
  plugin, and that it belongs in the repo or should be deactivated on
  production. A plugin in the release's `composer.lock` is one that
  [remote-plugin-install](remote-plugin-install.md) installs after this check.
  The step summary repeats it. See
  [Host-managed folders](../guides/host-managed-folders.md).
- **`trigger-backup` never waits.** For a deploy that holds until the backup
  exists, use `deploy.yml`'s `do_backup`, which hands the second half to
  [deploy-continue.yml](../workflows/deploy-continue.md).
- **Third-party plugins** come from [remote-plugin-install](remote-plugin-install.md)
  when `REMOTE_PLUGIN_INSTALL` is on; it runs after this action finishes.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"site-id","type":"string","required":true,"defaultValue":"","description":"Pressable site ID","values":"","deprecated":false},{"name":"site-url","type":"string","required":true,"defaultValue":"","description":"Public URL of the site (used for maintenance mode + health check)","values":"","deprecated":false},{"name":"api-client-id","type":"string","required":true,"defaultValue":"","description":"Pressable API client ID","values":"","deprecated":false},{"name":"api-client-secret","type":"string","required":true,"defaultValue":"","description":"Pressable API client secret","values":"","deprecated":false},{"name":"ssh-host","type":"string","required":true,"defaultValue":"","description":"SSH host","values":"","deprecated":false},{"name":"ssh-user","type":"string","required":true,"defaultValue":"","description":"SSH user","values":"","deprecated":false},{"name":"ssh-key","type":"string","required":true,"defaultValue":"","description":"SSH private key","values":"","deprecated":false},{"name":"release-directory","type":"string","required":false,"defaultValue":"release","description":"Local directory containing the cleaned release. Ignored when release-archive is set.","values":"","deprecated":false},{"name":"release-archive","type":"string","required":false,"defaultValue":"","description":"Path to a pre-built release zip (contents at root, e.g. plugins/ and themes/ at the top level). When set, it is shipped to the server as-is instead of re-zipping release-directory — the build job already zipped the release, so this avoids a redundant compression pass.","values":"","deprecated":false},{"name":"deployment-path","type":"string","required":false,"defaultValue":"/tmp/releases","description":"Remote staging path for uploaded releases","values":"","deprecated":false},{"name":"protected-paths","type":"string","required":false,"defaultValue":"","description":"Paths this deploy must never overwrite, relative to wp-content — one per line, comma separated, or a JSON array. Globs are allowed (e.g. \u003ccode\u003eplugins/woocommerce*\u003c/code\u003e), and a bare name matches that folder in any of plugins/themes/mu-plugins. Anything that is a symlink on the server is skipped automatically; use this for paths that are still real folders but are managed outside the repo. Pressable's own jetpack and akismet are always protected.","values":"","deprecated":false},{"name":"preserve-symlinks","type":"string","required":false,"defaultValue":"true","description":"Leave any plugin/theme/mu-plugin that is a symlink on the server exactly as it is instead of syncing over it (true/false). Pressable serves platform-managed plugins (jetpack, woocommerce) this way, and rsync would otherwise write through the link into platform-owned storage or replace the link with a real directory. Only set this to false if a deploy is meant to replace symlinks with real directories.","values":"","deprecated":false},{"name":"maintenance-mode","type":"string","required":false,"defaultValue":"false","description":"Enable Pressable maintenance mode during the sync (true/false)","values":"","deprecated":false},{"name":"trigger-backup","type":"string","required":false,"defaultValue":"false","description":"Fire a Pressable on-demand backup before syncing and proceed without waiting (true/false). For the v3-style pause-until-backup-completes flow, use deploy.yml's do_backup input instead.","values":"","deprecated":false},{"name":"post-deploy-command","type":"string","required":false,"defaultValue":"","description":"Optional shell command(s) run on the server (from /srv/htdocs) after the sync","values":"","deprecated":false},{"name":"health-check","type":"string","required":false,"defaultValue":"true","description":"After deploy, run \u003ccode\u003ewp mantle health\u003c/code\u003e on the server and curl the site; fail on a failing check, a connection error or HTTP 5xx (true/false)","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/deploy-pressable/action.yml), [`pressable-entrypoint.sh`](https://github.com/linchpin/actions/blob/main/actions/deploy-pressable/pressable-entrypoint.sh), [`health-report.sh`](https://github.com/linchpin/actions/blob/main/actions/deploy-pressable/health-report.sh)
