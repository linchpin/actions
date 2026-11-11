---
title: deploy-wpengine
---

Ships a built release to a WP Engine install through its SSH gateway, syncs it
into `wp-content` without touching symlinked or protected folders, clears any
maintenance mode left on, and checks that the site answers.
[deploy.yml](../workflows/deploy.md) runs it when the `HOST` variable is
`wpengine`.

## Example

The entry point is `deploy.yml`, with `HOST=wpengine`, `INSTALL_NAME` and
`SITE_URL` set as variables and the gateway key in the `SSH_KEY` secret:

```yaml
jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: staging
```

`deploy.yml` passes `vars.INSTALL_NAME` as `install-name`, `vars.SITE_URL` as
`site-url`, the `SSH_KEY` secret, the build's `release.zip`, and its own
`post_deploy_command`, `health_check`, `protected_paths` and
`preserve_symlinks`. The install name is both the SSH user and the host,
`<install>.ssh.wpengine.net`, so WP Engine needs no `SSH_HOST` or `SSH_USER`.

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Connect","content":"\u003cp\u003eWrites an SSH config for \u003ccode\u003e&lt;install-name&gt;.ssh.wpengine.net\u003c/code\u003e with the install name as the user.\u003c/p\u003e"},{"title":"Upload","content":"\u003cp\u003eShips the release zip, the server entrypoint and the protected-paths list to \u003ccode\u003e~/sites/&lt;install-name&gt;/&lt;deployment-path&gt;\u003c/code\u003e, by default \u003ccode\u003e_wpeprivate/releases\u003c/code\u003e.\u003c/p\u003e"},{"title":"Sync on the server","content":"\u003cp\u003eThe entrypoint unzips the release, logs every symlink under \u003ccode\u003ewp-content\u003c/code\u003e, then syncs each plugin and theme folder with its own rsync and \u003ccode\u003emu-plugins\u003c/code\u003e as one tree, skipping symlinks and protected paths.\u003c/p\u003e"},{"title":"Clean up","content":"\u003cp\u003eKeeps the two newest release zips and deletes \u003ccode\u003e.gz\u003c/code\u003e archives left by older deploy flows and stale release folders.\u003c/p\u003e"},{"title":"Clear maintenance","content":"\u003cp\u003eRemoves a \u003ccode\u003emaintenance.php\u003c/code\u003e from the site root, deactivates WP-CLI maintenance mode if it is active, and flushes the page cache when \u003ccode\u003ewp page-cache\u003c/code\u003e exists.\u003c/p\u003e"},{"title":"Post-deploy command","content":"\u003cp\u003eRuns \u003ccode\u003epost-deploy-command\u003c/code\u003e from \u003ccode\u003e~/sites/&lt;install-name&gt;\u003c/code\u003e.\u003c/p\u003e"},{"title":"Health check","content":"\u003cp\u003eRequests \u003ccode\u003esite-url\u003c/code\u003e up to 10 times; any HTTP status below 500 passes. Skipped when \u003ccode\u003esite-url\u003c/code\u003e is empty.\u003c/p\u003e"}]} /-->

## Behaviour to know

- **No maintenance window.** The action has no maintenance-mode input, so
  `deploy.yml`'s `maintenance_mode` does not reach WP Engine. The entrypoint
  only switches maintenance mode *off* if something left it on.
- **No WordPress-load check.** Unlike Pressable, success rests on the HTTP
  check alone.
- **`deployment-path` sets the site root too.** The entrypoint treats the
  directory two levels above the releases directory as the site root, which
  holds for the default `_wpeprivate/releases`.
- **Only folders the release ships are synced,** exactly as on Pressable: a
  plugin or theme the release lacks stays on the server, while `mu-plugins`
  syncs as one tree with `--delete`. See
  [Host-managed folders](../guides/host-managed-folders.md).
- **The health check is the gate:** the entrypoint runs without `set -e`, so a
  failed rsync does not stop it.
- **`do_backup` is Pressable-only.** There is no WP Engine backup step.

<!-- wp:docspress/callout {"tone":"note","title":"Not yet validated on a live install","content":"\u003cp\u003eThe migration guide still lists validating the WP Engine composite against a live client site as an open item. It is ported from the v3 logic with its shell bugs fixed.\u003c/p\u003e","collapsible":false} /-->

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"install-name","type":"string","required":true,"defaultValue":"","description":"WP Engine install name (SSH user; host becomes &lt;install&gt;.ssh.wpengine.net)","values":"","deprecated":false},{"name":"site-url","type":"string","required":false,"defaultValue":"","description":"Public URL of the site (used for the health check)","values":"","deprecated":false},{"name":"ssh-key","type":"string","required":true,"defaultValue":"","description":"SSH private key for the WP Engine SSH gateway","values":"","deprecated":false},{"name":"release-directory","type":"string","required":false,"defaultValue":"release","description":"Local directory containing the cleaned release. Ignored when release-archive is set.","values":"","deprecated":false},{"name":"release-archive","type":"string","required":false,"defaultValue":"","description":"Path to a pre-built release zip (contents at root, e.g. plugins/ and themes/ at the top level). When set, it is shipped to the server as-is instead of re-zipping release-directory — the build job already zipped the release, so this avoids a redundant compression pass.","values":"","deprecated":false},{"name":"deployment-path","type":"string","required":false,"defaultValue":"_wpeprivate/releases","description":"Remote staging path for uploaded releases, relative to the site root","values":"","deprecated":false},{"name":"protected-paths","type":"string","required":false,"defaultValue":"","description":"Paths this deploy must never overwrite, relative to wp-content — one per line, comma separated, or a JSON array. Globs are allowed (e.g. \u003ccode\u003eplugins/woocommerce*\u003c/code\u003e), and a bare name matches that folder in any of plugins/themes/mu-plugins. Anything that is a symlink on the server is skipped automatically; use this for paths that are still real folders but are managed outside the repo.","values":"","deprecated":false},{"name":"preserve-symlinks","type":"string","required":false,"defaultValue":"true","description":"Leave any plugin/theme/mu-plugin that is a symlink on the server exactly as it is instead of syncing over it (true/false). Without this, rsync writes through the link into whatever storage the platform manages, or replaces the link with a real directory. Only set this to false if a deploy is meant to replace symlinks with real directories.","values":"","deprecated":false},{"name":"post-deploy-command","type":"string","required":false,"defaultValue":"","description":"Optional shell command(s) run on the server (from the site root) after the sync","values":"","deprecated":false},{"name":"health-check","type":"string","required":false,"defaultValue":"true","description":"Curl the site after deploy and fail on connection errors or HTTP 5xx (true/false)","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/deploy-wpengine/action.yml), [`wpengine-entrypoint.sh`](https://github.com/linchpin/actions/blob/main/actions/deploy-wpengine/wpengine-entrypoint.sh)
