---
title: Safety Net on development
---

A dev site that production is copied onto every night, for Sisyphus's rolling
maintenance, holds real customers, API keys and an SMTP login. `safety_net: true`
on a development deploy installs
[Safety Net](https://github.com/linchpin/safety-net/releases) there and has it
scrub that copy before the deploy ships any code.

## Turn it on

Set it on the dev deploy caller. [bin/convert-repo](../scripts/convert-repo.md)
writes this caller from
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

`safety_net_version` picks the Safety Net release; it defaults to `1.12.0`.

## What happens

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Refuse anything else","content":"\u003cp\u003e\u003ccode\u003edeploy.yml\u003c/code\u003e fails before it records a deployment when \u003ccode\u003eenvironment\u003c/code\u003e is not \u003ccode\u003edevelopment\u003c/code\u003e, or when \u003ccode\u003edo_backup\u003c/code\u003e is on. It also fails a Cloudways deploy that uses password auth.\u003c/p\u003e"},{"title":"Download and check","content":"\u003cp\u003eThe \u003ccode\u003esafety-net\u003c/code\u003e action downloads \u003ccode\u003esafety-net.zip\u003c/code\u003e from the release and checks the version inside it.\u003c/p\u003e"},{"title":"Ask the server","content":"\u003cp\u003eIt refuses, before writing anything, unless the server's own \u003ccode\u003ewp_get_environment_type()\u003c/code\u003e is \u003ccode\u003edevelopment\u003c/code\u003e.\u003c/p\u003e"},{"title":"Install","content":"\u003cp\u003eIt installs \u003ccode\u003emu-plugins/safety-net/\u003c/code\u003e and \u003ccode\u003emu-plugins/safety-net-loader.php\u003c/code\u003e. The loader loads Safety Net only while the environment type is \u003ccode\u003edevelopment\u003c/code\u003e, so the files do nothing on any other site they are copied to.\u003c/p\u003e"},{"title":"Scrub and check every site","content":"\u003cp\u003eIt loads every site, each subsite of a multisite included, which runs Safety Net's scrub, and fails the deploy unless every site reports options scrubbed, plugins deactivated, users and orders deleted, transients deleted and emails blocked. The step summary lists each site.\u003c/p\u003e"},{"title":"Deploy the code","content":"\u003cp\u003eOnly then does the code deploy, with both Safety Net paths added to the protected paths, since \u003ccode\u003emu-plugins/\u003c/code\u003e is synced with \u003ccode\u003e--delete\u003c/code\u003e.\u003c/p\u003e"}]} /-->

The [safety-net](../composite-actions/safety-net.md) action does the middle four
steps; its page has the per-host inputs `deploy.yml` passes.

Between deploys the files stay put. A nightly sync copies the database and
uploads, not code, so the first request after the next sync runs the scrub
again.

## Caveats

- **It is an mu-plugin on purpose.** The nightly sync replaces the active
  plugins list with production's; mu-plugins load whatever that list says.
- **Not `REMOTE_PLUGIN_INSTALL`.** Safety Net is never in a project's
  `composer.lock` and never ships in a release; nothing else installs it.
- **Never `--skip-plugins`.** Safety Net runs as WordPress loads, while WP-CLI's
  `--skip-plugins` still hides the active plugins list, so a first run under it
  deactivates nothing and records the step done.
- **Turning it off** stops both the install and the protection, so the next
  deploy that ships `mu-plugins/` removes it.
- **Key auth only.** Cloudways with `DEPLOYMENT_AUTH_TYPE=pass` is refused.

## Troubleshooting

| Message | Cause and fix |
| --- | --- |
| `safety_net is for development only, and not with do_backup. This deploy is to '…'.` | Set `environment: development` and drop `do_backup` from the caller. |
| `safety_net needs SSH key auth, and DEPLOYMENT_AUTH_TYPE is pass.` | Move the Cloudways server to key auth. |
| `Could not download … Is … released on linchpin/safety-net, with safety-net.zip attached?` | `safety_net_version` names a release that does not exist or has no zip yet. The Safety Net release attaches its zip once its tests pass. |
| `safety-net.zip on … holds safety-net.php version '…', not ….` | The release's zip and its tag disagree. Pick another `safety_net_version`. |
| `The server says its environment type is '…', not development, so Safety Net was not installed.` | Set `WP_ENVIRONMENT_TYPE` to `development` on the dev server. |
| `Could not list the sites on the server.` | WP-CLI could not load WordPress; the last lines of its output follow the error. |
| `…: users and orders not deleted` and similar, per site | That site did not finish after three loads. The reason names the missing step. `SAFETY_NET_DELETE_DATA keeps its users and orders` means the site's Safety Net configuration keeps them; `Send emails is switched on` means emails are enabled. |
| `Safety Net has not finished on N site(s), so nothing was deployed.` | The summary of the per-site errors above it. |
