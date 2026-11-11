---
title: bin/onboard-site
---

The whole onboarding of one client site onto Sisyphus's nightly [rolling maintenance](../guides/rolling-maintenance.md), with [bin/convert-repo](convert-repo.md) as its step 4. It walks the steps in order and stops at the first one that needs a person, saying what to do. Run it again afterwards: what was already picked is read back from the site's enrollment, and every step already done is skipped.

## Requirements

- `gh`, as a repository admin with the `workflow` scope, plus `jq` and `curl`.
- A checkout of linchpin/actions: it runs the `bin/convert-repo` beside it.
- A WordPress application password for packagist.linchpin.com, created under **Users › Profile › Application Passwords**.

<!-- wp:docspress/fields {"title":"Environment","fields":[{"name":"SISYPHUS_AUTH","type":"string","required":true,"defaultValue":"","description":"\u003ccode\u003eusername:application password\u003c/code\u003e for packagist.linchpin.com. Without it the script exits 1.","values":"","deprecated":false},{"name":"SISYPHUS_URL","type":"url","required":false,"defaultValue":"https://packagist.linchpin.com","description":"Points it at another install.","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Usage

<!-- wp:docspress/terminal-session {"title":"Plan, picking the client and its site from lists","shell":"bash","prompt":"$","command":"export SISYPHUS_AUTH='your-username:application password'\nbin/onboard-site"} /-->

<!-- wp:docspress/terminal-session {"title":"Apply, for a site already picked","shell":"bash","prompt":"$","command":"bin/onboard-site www.ctoec.org --close-windows --task LINCHPIN-5946 --apply"} /-->

Every pick has a flag, so it also runs without a terminal. With more than one choice and no terminal to ask in, it exits 1 and asks you to name the choice with an option.

## Options

<!-- wp:docspress/fields {"title":"Arguments and options","fields":[{"name":"\u003chostname\u003e","type":"string","required":false,"defaultValue":"","description":"The production site, as the first argument without a flag. Without it you pick the client, then its production site.","values":"","deprecated":false},{"name":"--dev","type":"string","required":false,"defaultValue":"","description":"Dev's Pressable id, instead of picking it.","values":"","deprecated":false},{"name":"--staging","type":"string","required":false,"defaultValue":"","description":"Staging's Pressable id, or \u003ccode\u003enone\u003c/code\u003e, instead of picking it.","values":"","deprecated":false},{"name":"--repo","type":"string","required":false,"defaultValue":"","description":"The repository, \u003ccode\u003e&lt;owner/name&gt;\u003c/code\u003e, instead of confirming the suggestion.","values":"","deprecated":false},{"name":"--promote","type":"enum","required":false,"defaultValue":"","description":"Where snapshot PRs go: production's branch, or staging's.","values":"main, staging","deprecated":false},{"name":"--run-time","type":"string","required":false,"defaultValue":"the next free slot","description":"When it runs, \u003ccode\u003eHH:MM\u003c/code\u003e in America/New_York.","values":"","deprecated":false},{"name":"--close-windows","type":"boolean","required":false,"defaultValue":"","description":"Passed to bin/convert-repo.","values":"","deprecated":false},{"name":"--task","type":"string","required":false,"defaultValue":"","description":"ClickUp key, passed to bin/convert-repo.","values":"","deprecated":false},{"name":"--apply","type":"boolean","required":false,"defaultValue":"","description":"Make the changes. Without it nothing is written.","values":"","deprecated":false},{"name":"-h, --help","type":"boolean","required":false,"defaultValue":"","description":"Print the usage and exit 0.","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

An unknown option prints `Unknown option <option>` and the usage, and exits 1.

## The steps

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"The client and its production site","content":"\u003cp\u003ePicked from what api.linchpin.com knows, through packagist.linchpin.com: its environments and Sisyphus's choices. The site needs a Pressable id in api.linchpin.com, on Linchpin's account, that is not a staging site.\u003c/p\u003e"},{"title":"Dev and staging","content":"\u003cp\u003eDev is picked from the client's Pressable staging sites: never a sandbox, and no other site's dev. Then it reads Safety Net's status route on dev over HTTPS, as Sisyphus's preflight does every night. Staging, if snapshots promote through one, is optional.\u003c/p\u003e"},{"title":"The repository and its branches","content":"\u003cp\u003eConfirms the repository, its production and staging branches, where snapshot PRs go, and the run time.\u003c/p\u003e"},{"title":"Convert the repository","content":"\u003cp\u003eRuns bin/convert-repo with dev's site id and URL, dev's GitHub environment when api.linchpin.com knows it, the promotion target and staging branch, and your \u003ccode\u003e--close-windows\u003c/code\u003e, \u003ccode\u003e--task\u003c/code\u003e and \u003ccode\u003e--apply\u003c/code\u003e.\u003c/p\u003e"},{"title":"Enroll in Sisyphus","content":"\u003cp\u003eA new site is enrolled paused, because preflight refuses a dev without Safety Net. An enrolled one is updated.\u003c/p\u003e"},{"title":"The first Deploy to Dev","content":"\u003cp\u003eOnce the conversion PR is merged: dispatches \u003ccode\u003edeploy-dev.yml\u003c/code\u003e from \u003ccode\u003emaintenance\u003c/code\u003e, which installs Safety Net on dev, and stops until it passes.\u003c/p\u003e"},{"title":"Enable it, and one Run now","content":"\u003cp\u003eEnables the site and starts one run to watch. A site already enabled is left running as it is, with no extra run.\u003c/p\u003e"}]} /-->

Without `--apply`, steps 1 to 5 read and report (the reads include packagist.linchpin.com's API and dev's status route), `bin/convert-repo` runs as a plan, and it ends: `Nothing needs a person yet. Run it again with --apply; steps 6 and 7 follow once the conversion PR is merged.`

Some details of each step:

- **Run times** are staggered a site to a slot, so the nightly syncs and backups never queue behind one another on the host. The slots run every 20 minutes from 01:00 to 04:40 America/New_York; it takes the first one no other enrolled site holds, else 03:00.
- **The staging branch** is the one api.linchpin.com deploys staging from, else the enrollment's, else `staging`, and it must exist. Staging is loaded over HTTPS too, since its deploys' health check loads it; one that does not answer is a warning, not a stop.
- **A saved environment map** in Sisyphus decides dev, staging and the branches, so for a mapped site only the repository and run time are sent; change the rest in Sisyphus's map.
- **When bin/convert-repo needs a person** (its exit 2), the enrollment step still runs, then the script stops with exit 2. Its exit 1 stops the script at once.
- **The first Deploy to Dev** counts a successful or still-running run among the last five from `maintenance`; with none it starts one and stops with the `gh run watch` command to follow it.

## When dev cannot be reached

Sisyphus's preflight fails a night it cannot read dev's status route, after 15 minutes of asking again, so step 2 stops here with what to fix. WordPress without Safety Net yet is fine: the first Deploy to Dev installs it.

| Dev answers | Message | What to do |
| --- | --- | --- |
| No DNS record (curl exit 6) | `<host> has no DNS record. Add A records for it pointing at its Pressable site's IP addresses, DNS only, then run this again.` | Add the records |
| No valid certificate (curl exit 35, 51, 58, 59 or 60) | `<host> has no valid certificate yet. Pressable issues one once its DNS points at the site; wait for it, then run this again.` | Wait for Pressable's certificate |
| Nothing (any other curl failure) | `<host> did not answer (curl exit N). Check the site is up on Pressable, then run this again.` | Check the site on Pressable |
| Safety Net, outside development | `<host> reports its environment as <type>, not development, so Safety Net would not run there. Set WP_ENVIRONMENT_TYPE to development, then run this again.` | Set `WP_ENVIRONMENT_TYPE` |
| A redirect to Cloudflare Access | `Cloudflare Access stands in front of <host>. Add an Access application for <host>/wp-json/safety-net/v1/status with a Bypass policy (the route reports only Safety Net's flags), then run this again.` | Add the bypass |
| Any other redirect | `<host> redirects Safety Net's status route to <location>. Dev has to answer on its own hostname.` | Make dev answer on its own hostname |
| HTTP 401 | `<host> asks for a password. Let Safety Net's status route through without one, then run this again.` | Exempt the route |
| Anything else | `<host> answered HTTP <status> without a Safety Net status, so Preflight would fail every night.` | Fix what dev serves at the route |

## Other stops

| Message | What to do |
| --- | --- |
| `Sisyphus lists no site that can be enrolled.` | Check the site in api.linchpin.com |
| `<site> is not a production site Sisyphus can enroll: it needs a Pressable id in api.linchpin.com, on Linchpin's account, that is not a staging site.` | Give the site its Pressable id in api.linchpin.com |
| `<client> has no Pressable staging site to be dev. Clone production on Pressable as a staging site (never a sandbox), set WP_ENVIRONMENT_TYPE to development, then run this again.` | Create dev on Pressable |
| `Pressable <id> is not a staging site Sisyphus can use as dev (a sandbox, or not on Linchpin's account).` | Pick another dev |
| `Pressable <id> is already <site>'s; two sites sharing a dev overwrite each other every night.` | Give this site its own dev |
| `` <repo> has no `<branch>` branch for staging. `` | Create the branch, or pick no staging |
| `` Merge the conversion PR (<url>) into `<production>`, then run this again. `` | Merge the PR bin/convert-repo opened |
| `Deploy to Dev is still running (<url>). Run this again once it passes.` | Wait for it |

A warning that api.linchpin.com has more than one development environment for the site does not stop it, but the nightly test needs exactly one.

## What stays with a person

Creating dev on Pressable when the client has none, its DNS records, and mapping a Ghost Inspector suite to dev in Sisyphus, so the nightly test runs something. The last run ends by saying so.

## Exit status

| Status | Meaning |
| --- | --- |
| `0` | The site is onboarded, or the plan needs nothing from a person |
| `2` | A step needs a person: the line starts with `!` |
| `1` | An error: a missing tool or `SISYPHUS_AUTH`, an API call that failed (`<METHOD> <route> answered <status>: …`), a pick with no terminal, or bin/convert-repo's own error |
