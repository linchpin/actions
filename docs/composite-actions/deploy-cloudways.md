---
title: deploy-cloudways
---

Ships a built release to a Cloudways server over SSH, with a key or (for
Cloudways Autonomous) a password, and syncs it into `public_html/wp-content`
under maintenance mode before flushing Redis and the object cache.
[deploy.yml](../workflows/deploy.md) runs it when the `HOST` variable is
`cloudways`.

## Example

The entry point is `deploy.yml`, with `HOST=cloudways` and `SITE_URL` set as
variables and `SSH_HOST` and `SSH_USER` as secrets:

```yaml
jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: staging
```

`DEPLOYMENT_AUTH_TYPE` picks the authentication, and `deploy.yml` passes it as
`auth-type` (`key` when unset):

| `DEPLOYMENT_AUTH_TYPE` | Secret used | Not available |
| --- | --- | --- |
| `key` (default) | `SSH_KEY` | — |
| `pass` | `SSH_PASS` | `REMOTE_PLUGIN_INSTALL` and `safety_net`; `deploy.yml` fails rather than skip them |

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Upload and unpack","content":"\u003cp\u003eShips the release zip to \u003ccode\u003edeployment-path\u003c/code\u003e (default \u003ccode\u003e~/private_html/releases\u003c/code\u003e), unzips it into \u003ccode\u003erelease/\u003c/code\u003e, and adds the entrypoint, \u003ccode\u003emaintenance.php\u003c/code\u003e and the protected-paths list under \u003ccode\u003erelease/.deployment\u003c/code\u003e.\u003c/p\u003e"},{"title":"Maintenance mode on","content":"\u003cp\u003eCopies the bundled \u003ccode\u003emaintenance.php\u003c/code\u003e into \u003ccode\u003epublic_html\u003c/code\u003e and runs \u003ccode\u003ewp maintenance-mode activate\u003c/code\u003e. Every Cloudways deploy does this.\u003c/p\u003e"},{"title":"Remove legacy links","content":"\u003cp\u003eA \u003ccode\u003ewp-content/themes\u003c/code\u003e, \u003ccode\u003eplugins\u003c/code\u003e or \u003ccode\u003emu-plugins\u003c/code\u003e symlink that points into \u003ccode\u003eprivate_html\u003c/code\u003e or a release directory is a leftover from the old deploy process and is removed. Any other symlink there is left in place.\u003c/p\u003e"},{"title":"Sync","content":"\u003cp\u003eSyncs \u003ccode\u003eplugins/\u003c/code\u003e, \u003ccode\u003ethemes/\u003c/code\u003e and \u003ccode\u003emu-plugins/\u003c/code\u003e each as one tree with \u003ccode\u003e--delete\u003c/code\u003e. Symlinked and protected children become rsync excludes.\u003c/p\u003e"},{"title":"Clean up","content":"\u003cp\u003eKeeps the two newest release zips and removes old release folders.\u003c/p\u003e"},{"title":"Maintenance mode off, caches flushed","content":"\u003cp\u003eRemoves \u003ccode\u003emaintenance.php\u003c/code\u003e, deactivates maintenance mode, runs \u003ccode\u003ewp redis enable --force\u003c/code\u003e and \u003ccode\u003ewp redis flush\u003c/code\u003e when the Redis command exists, and \u003ccode\u003ewp cache flush\u003c/code\u003e.\u003c/p\u003e"},{"title":"Post-deploy command","content":"\u003cp\u003eRuns \u003ccode\u003epost-deploy-command\u003c/code\u003e in the SSH user's login directory.\u003c/p\u003e"},{"title":"Health check","content":"\u003cp\u003eRequests \u003ccode\u003esite-url\u003c/code\u003e up to 10 times; any HTTP status below 500 passes. Skipped when \u003ccode\u003esite-url\u003c/code\u003e is empty.\u003c/p\u003e"}]} /-->

<!-- wp:docspress/callout {"tone":"warning","title":"The release defines plugins/ and themes/","content":"\u003cp\u003eUnlike Pressable and WP Engine, Cloudways syncs \u003ccode\u003eplugins/\u003c/code\u003e and \u003ccode\u003ethemes/\u003c/code\u003e as whole trees. A plugin or theme folder on the server that the release does not ship is \u003cstrong\u003edeleted\u003c/strong\u003e, unless it is a symlink or listed in \u003ccode\u003ePROTECTED_PATHS\u003c/code\u003e.\u003c/p\u003e","collapsible":false} /-->

## Behaviour to know

- **Maintenance mode is not optional here.** The entrypoint always turns it on
  for the sync; `deploy.yml`'s `maintenance_mode` input does not reach this
  action.
- **`public_html` is found relative to `deployment-path`:** the entrypoint
  looks for it beside the directory that holds the releases directory, so the
  default `~/private_html/releases` resolves to `~/public_html`. A path that
  does not fit that shape fails with `❌ Public directory not found at …`.
- **`post-deploy-command` does not `cd` first.** Start it with `cd public_html &&`
  when it runs WP-CLI.
- **The health check is the gate:** the entrypoint runs without `set -e`, so a
  failed rsync does not stop it.
- **`do_backup` is Pressable-only.** There is no Cloudways backup step.

See [Host-managed folders](../guides/host-managed-folders.md) for how symlinks
and `PROTECTED_PATHS` are handled.

<!-- wp:docspress/callout {"tone":"note","title":"Not yet validated on a live install","content":"\u003cp\u003eThe migration guide still lists validating the Cloudways composite against a live client site as an open item. It is ported from the v3 logic with its shell bugs fixed.\u003c/p\u003e","collapsible":false} /-->

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"auth-type","type":"string","required":false,"defaultValue":"key","description":"SSH auth type: 'key' (default) or 'pass' (Cloudways Autonomous)","values":"","deprecated":false},{"name":"ssh-host","type":"string","required":true,"defaultValue":"","description":"SSH host","values":"","deprecated":false},{"name":"ssh-user","type":"string","required":true,"defaultValue":"","description":"SSH user","values":"","deprecated":false},{"name":"ssh-key","type":"string","required":false,"defaultValue":"","description":"SSH private key (auth-type: key)","values":"","deprecated":false},{"name":"ssh-pass","type":"string","required":false,"defaultValue":"","description":"SSH password (auth-type: pass)","values":"","deprecated":false},{"name":"site-url","type":"string","required":false,"defaultValue":"","description":"Public URL of the site (used for the health check)","values":"","deprecated":false},{"name":"release-directory","type":"string","required":false,"defaultValue":"release","description":"Local directory containing the cleaned release. Ignored when release-archive is set.","values":"","deprecated":false},{"name":"release-archive","type":"string","required":false,"defaultValue":"","description":"Path to a pre-built release zip (contents at root, e.g. plugins/ and themes/ at the top level). When set, it is shipped to the server as-is instead of re-zipping release-directory — the build job already zipped the release, so this avoids a redundant compression pass.","values":"","deprecated":false},{"name":"deployment-path","type":"string","required":false,"defaultValue":"~/private_html/releases","description":"Remote staging path for uploaded releases","values":"","deprecated":false},{"name":"protected-paths","type":"string","required":false,"defaultValue":"","description":"Paths this deploy must never overwrite, relative to wp-content — one per line, comma separated, or a JSON array. Globs are allowed (e.g. \u003ccode\u003eplugins/woocommerce*\u003c/code\u003e), and a bare name matches that folder in any of plugins/themes/mu-plugins. Anything that is a symlink on the server is skipped automatically; use this for paths that are still real folders but are managed outside the repo.","values":"","deprecated":false},{"name":"preserve-symlinks","type":"string","required":false,"defaultValue":"true","description":"Leave any plugin/theme/mu-plugin that is a symlink on the server exactly as it is instead of syncing over it (true/false). Without this, rsync writes through the link into whatever storage the platform manages, or --delete prunes files the platform owns. Only set this to false if a deploy is meant to replace symlinks with real directories.","values":"","deprecated":false},{"name":"post-deploy-command","type":"string","required":false,"defaultValue":"","description":"Optional shell command(s) run on the server after the sync","values":"","deprecated":false},{"name":"health-check","type":"string","required":false,"defaultValue":"true","description":"Curl the site after deploy and fail on connection errors or HTTP 5xx (true/false)","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/deploy-cloudways/action.yml), [`cloudways-entrypoint.sh`](https://github.com/linchpin/actions/blob/main/actions/deploy-cloudways/cloudways-entrypoint.sh), [`maintenance.php`](https://github.com/linchpin/actions/blob/main/actions/deploy-cloudways/maintenance.php)
