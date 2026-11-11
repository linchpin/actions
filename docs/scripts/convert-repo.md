---
title: bin/convert-repo
---

Moves one site repository onto [rolling maintenance](../guides/rolling-maintenance.md). It looks at the repository first, then does the parts that need no judgment and says which ones do. Without `--apply` it only reports. Run it again at any time: it makes only the changes still missing.

## Requirements

- `gh`, logged in as an admin of the repository with the `workflow` scope, and `jq`.
- A checkout of linchpin/actions: it reads the callers from `templates/rolling-maintenance` beside it.

## Usage

<!-- wp:docspress/terminal-session {"title":"See the plan","shell":"bash","prompt":"$","command":"bin/convert-repo linchpin/ctoec --dev-site-id 1804699 --promotion-target staging"} /-->

<!-- wp:docspress/terminal-session {"title":"Make the changes","shell":"bash","prompt":"$","command":"bin/convert-repo linchpin/ctoec --dev-site-id 1804699 --promotion-target staging --close-windows --apply"} /-->

`--out <dir>` writes the files the PR would change, so you can read them first.

## Options

<!-- wp:docspress/fields {"title":"Arguments and options","fields":[{"name":"\u003cowner/name\u003e","type":"string","required":true,"defaultValue":"","description":"The repository, as the first argument without a flag.","values":"","deprecated":false},{"name":"--dev-environment","type":"string","required":false,"defaultValue":"","description":"Dev's GitHub environment, \u003ccode\u003e&lt;name&gt;\u003c/code\u003e. Without it: the environment whose \u003ccode\u003eSITE_ID\u003c/code\u003e variable is \u003ccode\u003e--dev-site-id\u003c/code\u003e, else \u003ccode\u003edevelopment\u003c/code\u003e. Created when missing; an existing one is matched in any case.","values":"","deprecated":false},{"name":"--dev-site-id","type":"string","required":false,"defaultValue":"","description":"Dev's site id at the host, \u003ccode\u003e&lt;id&gt;\u003c/code\u003e, set as the environment's \u003ccode\u003eSITE_ID\u003c/code\u003e.","values":"","deprecated":false},{"name":"--dev-url","type":"string","required":false,"defaultValue":"","description":"Dev's URL, \u003ccode\u003e&lt;url&gt;\u003c/code\u003e, set as the environment's \u003ccode\u003eSITE_URL\u003c/code\u003e.","values":"","deprecated":false},{"name":"--dev-ssh-user","type":"string","required":false,"defaultValue":"","description":"Dev's SSH user, \u003ccode\u003e&lt;user&gt;\u003c/code\u003e, stored as the environment's \u003ccode\u003eSSH_USER\u003c/code\u003e secret.","values":"","deprecated":false},{"name":"--promotion-target","type":"string","required":false,"defaultValue":"the production branch","description":"The branch snapshot PRs go into, \u003ccode\u003e&lt;ref&gt;\u003c/code\u003e.","values":"","deprecated":false},{"name":"--staging-branch","type":"string","required":false,"defaultValue":"staging, when it exists","description":"A staging branch snapshots may also go into, \u003ccode\u003e&lt;ref&gt;\u003c/code\u003e.","values":"","deprecated":false},{"name":"--ci-workflow","type":"string","required":false,"defaultValue":"detected","description":"A workflow that checks PRs, by its \u003ccode\u003ename:\u003c/code\u003e. Repeat for more. Detected as every workflow with a \u003ccode\u003epull_request\u003c/code\u003e trigger, other than the ones the PR removes; with none, the \u003ccode\u003eworkflow_run\u003c/code\u003e trigger is left out of \u003ccode\u003emaintenance.yml\u003c/code\u003e.","values":"","deprecated":false},{"name":"--skip-check","type":"string","required":false,"defaultValue":"","description":"A check production requires that never runs on PRs into \u003ccode\u003emaintenance\u003c/code\u003e, left out of the ruleset. Repeatable.","values":"","deprecated":false},{"name":"--close-windows","type":"boolean","required":false,"defaultValue":"","description":"Close monthly windows that hold only Renovate's commits.","values":"","deprecated":false},{"name":"--task","type":"string","required":false,"defaultValue":"NO-TASK","description":"ClickUp key, \u003ccode\u003e&lt;KEY&gt;\u003c/code\u003e, for the PR's branch (\u003ccode\u003eissue/&lt;KEY&gt;\u003c/code\u003e, else \u003ccode\u003eno-task/rolling-maintenance\u003c/code\u003e) and its commit scope.","values":"","deprecated":false},{"name":"--out","type":"string","required":false,"defaultValue":"","description":"Also write the files the PR would add or change into \u003ccode\u003e&lt;dir&gt;\u003c/code\u003e.","values":"","deprecated":false},{"name":"--apply","type":"boolean","required":false,"defaultValue":"","description":"Make the changes. Without it nothing is written.","values":"","deprecated":false},{"name":"-h, --help","type":"boolean","required":false,"defaultValue":"","description":"Print the usage and exit 0.","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

An unknown option prints `Unknown option <option>` and the usage, and exits 1, as does a missing repository.

## What it does

It reads the repository and its production (default) branch, and stops at once with `!` and exit 2 unless you are an admin of it. Then it walks five steps:

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Monthly windows","content":"\u003cp\u003eGit cannot hold \u003ccode\u003emaintenance\u003c/code\u003e beside \u003ccode\u003emaintenance/YYYY-MM\u003c/code\u003e, so each window has to go. One holding only Renovate's and linchpin-bot's commits is closed with \u003ccode\u003e--close-windows\u003c/code\u003e: its PR gets a comment and is closed, and the branch is deleted. One holding a person's commits is left for a person to merge into production.\u003c/p\u003e"},{"title":"The maintenance branch","content":"\u003cp\u003eCreated from the production branch, once no window is in the way.\u003c/p\u003e"},{"title":"One PR into production","content":"\u003cp\u003eAdds the three callers, replaces the Renovate maintenance-window preset with the rolling-maintenance one, and removes the window's workflows. Opened from \u003ccode\u003eno-task/rolling-maintenance\u003c/code\u003e or \u003ccode\u003eissue/&lt;KEY&gt;\u003c/code\u003e as \u003ccode\u003eci(&lt;KEY&gt;): Move to rolling maintenance\u003c/code\u003e; a run again force-updates that branch.\u003c/p\u003e"},{"title":"Dev's environment","content":"\u003cp\u003eDeploys from \u003ccode\u003emaintenance\u003c/code\u003e only, with \u003ccode\u003eBRANCH\u003c/code\u003e, \u003ccode\u003eENVIRONMENT\u003c/code\u003e, \u003ccode\u003eSITE_ID\u003c/code\u003e and \u003ccode\u003eSITE_URL\u003c/code\u003e, the \u003ccode\u003eSSH_USER\u003c/code\u003e secret when given, and \u003ccode\u003eHOST\u003c/code\u003e and \u003ccode\u003eREMOTE_PLUGIN_INSTALL\u003c/code\u003e copied from production's environment.\u003c/p\u003e"},{"title":"The ruleset","content":"\u003cp\u003eGreen checks into maintenance: the checks production requires, less \u003ccode\u003e--skip-check\u003c/code\u003e, with linchpin-bot exempt.\u003c/p\u003e"}]} /-->

It never merges anything into production, never deletes a branch holding a person's commits, and never rewrites a deploy workflow.

### The PR's files

| File | Change |
| --- | --- |
| `maintenance.yml`, `snapshots.yml`, `deploy-dev.yml` | Added from the templates. One that already calls linchpin/actions for rolling maintenance is kept, except a `snapshots.yml` from before refresh (no `mode`), which is updated. One of the same name that does something else is replaced. |
| `auto-approve-maintenance.yml`, `auto-merge-maintenance.yml`, `combine-dependency-prs.yml`, `combine-dependency-prs-schedule.yml` | Removed, since they served the monthly window |
| `renovate.json` or `.github/renovate.json` | `github>linchpin/renovatebot-config:rolling-maintenance` added to `extends`, and `github>linchpin/renovatebot-config:maintenance-window` taken out |

It also notes, and leaves alone, workflows that still call linchpin/actions at v3 or older (only Deploy to Dev needs v4) and workflows naming a `maintenance/` or `site-maintenance` branch.

Production's environment is the one whose `BRANCH` variable is the production branch, else one named `Production…`. When production requires no checks there is no ruleset to add, and `maintenance` merges an update once whatever runs on it is green.

## When it needs a person

Each `!` line is something to fix before running it again. They all end in exit 2.

| Message | What to do |
| --- | --- |
| `You need admin on <repo> for its environments and rulesets.` | Run it as a repository admin |
| `` `maintenance/YYYY-MM` holds N commits <production> lacks, some by <people>. Merge it into <production>, or close it, by hand. `` | Merge or close the window yourself |
| `` `maintenance/YYYY-MM` holds only Renovate's commits (N). Re-run with --close-windows to close it. `` | Add `--close-windows` |
| `Created once the windows above are gone.` | Deal with the windows first |
| `deploy-dev.yml does not set safety_net: true, so preflight refuses dev every night.` | Set `safety_net: true` in the existing `deploy-dev.yml` |
| ``It has no Renovate config, so nothing reaches `maintenance`.`` | Add a Renovate config |
| `Its Renovate config is not renovate.json; add <preset> to its extends by hand.` | Edit the config yourself |
| `<config> is not strict JSON; add <preset> to its extends by hand.` | Edit the config yourself |
| `<config> sets its own base branches (…), which would replace the preset's. Remove them, then run this again.` | Remove `baseBranches` or `baseBranchPatterns` |
| `Give dev's site id at the host with --dev-site-id.` | Add `--dev-site-id` |
| `Give dev's URL with --dev-url.` | Add `--dev-url` |
| `Neither the repository nor <environment> sets HOST (pressable, wpengine or cloudways).` | Set the `HOST` variable |
| `Give dev's SSH user with --dev-ssh-user (the SSH_USER secret).` | Add `--dev-ssh-user` |

Without `!` lines, a plan ends `Nothing needs a person. Run it again with --apply.` and an applied run ends `Converted. Merge the PR, then enroll the site in Sisyphus.` [bin/onboard-site](onboard-site.md) does that enrollment.

## Exit status

| Status | Meaning |
| --- | --- |
| `0` | The repository is converted, or would be with `--apply` |
| `2` | Something needs a person first: each such line starts with `!` |
| `1` | An error, such as `convert-repo needs gh.` or `Cannot read <repo>.` |
