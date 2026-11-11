---
title: remote-plugin-install
---

Brings the third-party plugins and themes on a server in line with
`composer.lock`, with one WP-CLI call per package over SSH, so a release only has
to carry the project's own code. [deploy.yml](../workflows/deploy.md) and
[deploy-continue.yml](../workflows/deploy-continue.md) run it after the code
sync when the `REMOTE_PLUGIN_INSTALL` variable is `true`. The
[Remote plugin install](../guides/remote-plugin-install.md) guide covers the
whole mode, build side included.

## Example

Normally you only set the variable, plus the registry credentials when the
lock pulls from packagist.linchpin.com:

```
REMOTE_PLUGIN_INSTALL = true
SATISPRESS_USER / SATISPRESS_PASSWORD
```

`deploy.yml` then extracts `composer.lock` from `release.zip` and calls the
action with the host's layout:

| Host | `ssh-host`, `ssh-user` | `wp-path` |
| --- | --- | --- |
| Pressable | the `SSH_HOST`, `SSH_USER` secrets | `/srv/htdocs` |
| WP Engine | `<INSTALL_NAME>.ssh.wpengine.net`, `INSTALL_NAME` | `~/sites/<INSTALL_NAME>` |
| Cloudways (key auth) | the `SSH_HOST`, `SSH_USER` secrets | `~/public_html` |

To see the plan for a server without deploying, call it directly with
`dry-run`:

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v6
      - uses: linchpin/actions/actions/remote-plugin-install@v4
        with:
          ssh-host: ${{ secrets.SSH_HOST }}
          ssh-user: ${{ secrets.SSH_USER }}
          ssh-key: ${{ secrets.SSH_KEY }}
          wp-path: /srv/htdocs
          protected-paths: ${{ vars.PROTECTED_PATHS }}
          package-auth-user: ${{ secrets.SATISPRESS_USER }}
          package-auth-password: ${{ secrets.SATISPRESS_PASSWORD }}
          dry-run: 'true'
```

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Read the server","content":"\u003cp\u003eOne SSH call lists the installed plugins and themes with WP-CLI (with \u003ccode\u003e--skip-plugins --skip-themes\u003c/code\u003e, so a fatal in another plugin cannot hide the inventory) and every symlink in \u003ccode\u003ewp-content/plugins\u003c/code\u003e and \u003ccode\u003ewp-content/themes\u003c/code\u003e.\u003c/p\u003e"},{"title":"Plan","content":"\u003cp\u003eFor each \u003ccode\u003ewordpress-plugin\u003c/code\u003e and \u003ccode\u003ewordpress-theme\u003c/code\u003e package in the lock, skips platform symlinks, protected paths and packages with no dist archive, and skips packages already at the locked version. Everything else is an install or an update. The plan is logged as \u003ccode\u003ePlan: N to install, N to update, …\u003c/code\u003e.\u003c/p\u003e"},{"title":"Apply","content":"\u003cp\u003eRuns \u003ccode\u003ewp plugin install &lt;dist url&gt; --force\u003c/code\u003e (or \u003ccode\u003ewp theme install\u003c/code\u003e) per package. The URL reaches the server on stdin, with registry credentials added only for \u003ccode\u003epackage-auth-host\u003c/code\u003e, so they never appear in a process list or the run log.\u003c/p\u003e"},{"title":"Verify","content":"\u003cp\u003eReads the inventory again and fails when any install failed or a package is not at its locked version. Warns about newly installed packages that are inactive.\u003c/p\u003e"}]} /-->

## Behaviour to know

- **The lock wins in both directions.** A package at any other version is
  reinstalled at the locked one, so deploying an older `release_tag` downgrades
  plugins instead of leaving them ahead of the code.
- **Versions are compared loosely:** a leading `v` and build metadata are
  dropped and trailing `.0` segments collapse, so `v8.0.0`, `8.0` and `8` match.
- **The folder is named after the package.** The slug is the part of the
  Composer name after the `/`. WP-CLI names the directory after the zip's
  top-level folder, so an archive whose folder differs fails verification with
  `not present after install`.
- **It installs and updates; it never activates or removes.** A package dropped
  from the lock stays on the server, and a new one arrives inactive.
- **Key auth only.** Cloudways with `DEPLOYMENT_AUTH_TYPE=pass` is refused by
  `deploy.yml`.
- **`wp-path` is restricted** to letters, digits, `.`, `_`, `~`, `/` and `-`,
  because it is interpolated into a remote command.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"ssh-host","type":"string","required":true,"defaultValue":"","description":"SSH host","values":"","deprecated":false},{"name":"ssh-user","type":"string","required":true,"defaultValue":"","description":"SSH user","values":"","deprecated":false},{"name":"ssh-key","type":"string","required":true,"defaultValue":"","description":"SSH private key. Password auth is not supported by this action — Cloudways Autonomous (DEPLOYMENT_AUTH_TYPE=pass) installs cannot use remote plugin install yet.","values":"","deprecated":false},{"name":"wp-path","type":"string","required":true,"defaultValue":"","description":"Absolute (or ~-relative) path to the WordPress root on the server. Pressable: /srv/htdocs. WP Engine: ~/sites/&lt;install&gt;. Cloudways: ~/public_html.","values":"","deprecated":false},{"name":"composer-lock","type":"string","required":false,"defaultValue":"composer.lock","description":"Path to composer.lock on the runner. It is the source of truth: any package whose installed version differs is reinstalled at the locked version, so a rollback downgrades rather than leaving plugins ahead.","values":"","deprecated":false},{"name":"protected-paths","type":"string","required":false,"defaultValue":"","description":"Paths this action must never install over, relative to wp-content — same format as the deploy actions (one per line, comma separated, or a JSON array; globs allowed).","values":"","deprecated":false},{"name":"preserve-symlinks","type":"string","required":false,"defaultValue":"true","description":"Skip any package whose target directory is a symlink on the server (true/false). Composer's installer-paths would delete such a link and replace it with a real directory; WP-CLI would too, so this is checked before every install.","values":"","deprecated":false},{"name":"package-auth-host","type":"string","required":false,"defaultValue":"packagist.linchpin.com","description":"Hostname of the private Composer registry whose dist URLs need credentials (e.g. packagist.linchpin.com). Packages served from anywhere else are downloaded unauthenticated.","values":"","deprecated":false},{"name":"package-auth-user","type":"string","required":false,"defaultValue":"","description":"Username for the private registry (v3's SATISPRESS_USER)","values":"","deprecated":false},{"name":"package-auth-password","type":"string","required":false,"defaultValue":"","description":"Password for the private registry (v3's SATISPRESS_PASSWORD)","values":"","deprecated":false},{"name":"dry-run","type":"string","required":false,"defaultValue":"false","description":"Print the plan and make no changes (true/false)","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/remote-plugin-install/action.yml), [`remote-plugin-install.sh`](https://github.com/linchpin/actions/blob/main/actions/remote-plugin-install/remote-plugin-install.sh)
