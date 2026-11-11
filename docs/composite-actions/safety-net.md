---
title: safety-net
---

Installs Linchpin's [Safety Net](https://github.com/linchpin/safety-net/releases)
on a development server as an mu-plugin, loads every site so it scrubs the
production data a nightly sync copied there, and fails unless every site
reports the scrub done. [deploy.yml](../workflows/deploy.md) runs it before the
code ships when `safety_net` is `true`. The
[Safety Net on development](../guides/safety-net-on-development.md) guide covers
the whole flow.

## Example

The dev deploy caller from
[templates/rolling-maintenance/deploy-dev.yml](https://github.com/linchpin/actions/blob/main/templates/rolling-maintenance/deploy-dev.yml):

```yaml
permissions:
  contents: write
  deployments: write

jobs:
  deploy:
    uses: linchpin/actions/.github/workflows/deploy.yml@v4
    secrets: inherit
    with:
      environment: development
      safety_net: true
```

`deploy.yml` passes its `environment`, `safety_net_version` as `version`, and
the host's SSH details and WordPress root:

| Host | `ssh-host`, `ssh-user` | `wp-path` |
| --- | --- | --- |
| Pressable | the `SSH_HOST`, `SSH_USER` secrets | `/srv/htdocs` |
| WP Engine | `<INSTALL_NAME>.ssh.wpengine.net`, `INSTALL_NAME` | `~/sites/<INSTALL_NAME>` |
| Cloudways (key auth) | the `SSH_HOST`, `SSH_USER` secrets | `~/public_html` |

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Refuse anything but development","content":"\u003cp\u003eFails unless \u003ccode\u003eenvironment\u003c/code\u003e is \u003ccode\u003edevelopment\u003c/code\u003e, compared case-insensitively.\u003c/p\u003e"},{"title":"Download and check the release","content":"\u003cp\u003eFetches \u003ccode\u003esafety-net.zip\u003c/code\u003e from the \u003ccode\u003eversion\u003c/code\u003e release of \u003ccode\u003erepository\u003c/code\u003e, retrying briefly, and fails unless the \u003ccode\u003eVersion\u003c/code\u003e header of \u003ccode\u003esafety-net/safety-net.php\u003c/code\u003e inside it equals \u003ccode\u003eversion\u003c/code\u003e without a leading \u003ccode\u003ev\u003c/code\u003e.\u003c/p\u003e"},{"title":"Ask the server","content":"\u003cp\u003eRuns \u003ccode\u003ewp_get_environment_type()\u003c/code\u003e on the server and refuses, before writing anything, unless it returns \u003ccode\u003edevelopment\u003c/code\u003e.\u003c/p\u003e"},{"title":"Install","content":"\u003cp\u003eUnpacks the zip beside the live copy and swaps it into \u003ccode\u003ewp-content/mu-plugins/safety-net\u003c/code\u003e, then writes \u003ccode\u003emu-plugins/safety-net-loader.php\u003c/code\u003e, which loads Safety Net only while the environment type is \u003ccode\u003edevelopment\u003c/code\u003e.\u003c/p\u003e"},{"title":"Load every site","content":"\u003cp\u003eLists the sites (on a multisite, every subsite that is not archived, deleted or spam) and loads each up to three times, reading Safety Net's \u003ccode\u003e/safety-net/v1/status\u003c/code\u003e route after each load.\u003c/p\u003e"},{"title":"Report","content":"\u003cp\u003eWrites a per-site table to the step summary and fails with \u003ccode\u003eSafety Net has not finished on N site(s), so nothing was deployed.\u003c/code\u003e if any site is not done.\u003c/p\u003e"}]} /-->

## Behaviour to know

- **Done means every flag:** Safety Net loaded, its environment `development`,
  options scrubbed, plugins deactivated, users and orders deleted, transients
  deleted, and emails not enabled. The error names whichever is missing.
- **An mu-plugin on purpose.** The nightly sync replaces the active plugins list
  with production's, and mu-plugins load regardless of that list.
- **Never under `--skip-plugins`.** Safety Net runs while WordPress loads; under
  WP-CLI's `--skip-plugins` the active plugins list is hidden, so a first run
  would deactivate nothing and still record the step done. The action never
  passes it.
- **Key auth only.** `deploy.yml` fails a Cloudways deploy with
  `DEPLOYMENT_AUTH_TYPE=pass` before calling it.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"environment","type":"string","required":true,"defaultValue":"","description":"The environment being deployed. Anything but \u003ccode\u003edevelopment\u003c/code\u003e, in any case (GitHub matches environment names that way), is refused.","values":"","deprecated":false},{"name":"ssh-host","type":"string","required":true,"defaultValue":"","description":"SSH host","values":"","deprecated":false},{"name":"ssh-user","type":"string","required":true,"defaultValue":"","description":"SSH user","values":"","deprecated":false},{"name":"ssh-key","type":"string","required":true,"defaultValue":"","description":"SSH private key. Password auth is not supported.","values":"","deprecated":false},{"name":"wp-path","type":"string","required":true,"defaultValue":"","description":"Absolute (or ~-relative) path to the WordPress root on the server. Pressable: /srv/htdocs. WP Engine: ~/sites/&lt;install&gt;. Cloudways: ~/public_html.","values":"","deprecated":false},{"name":"version","type":"string","required":true,"defaultValue":"","description":"The release of \u003ccode\u003erepository\u003c/code\u003e to install: its tag, which must match the Version header of the safety-net.php inside its safety-net.zip","values":"","deprecated":false},{"name":"repository","type":"string","required":false,"defaultValue":"linchpin/safety-net","description":"Where the release is published","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/safety-net/action.yml), [`safety-net.sh`](https://github.com/linchpin/actions/blob/main/actions/safety-net/safety-net.sh)
