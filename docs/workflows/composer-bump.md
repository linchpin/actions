---
title: composer-bump.yml
---

Regenerates a site repository's `composer.lock` for one package and opens the pull request. Linchpin Governing dispatches it when an operator pushes an update, so the update survives the next deploy: [remote-plugin-install](../composite-actions/remote-plugin-install.md) reinstalls whatever `composer.lock` names, so a version applied straight to a server is reverted until the lock agrees.

It is not a reusable workflow. It runs here in linchpin/actions and acts on a *target* repository with a token minted for that repository, so one workflow serves every site repository and none needs a caller committed into it.

It runs on a runner because regenerating a lock means running Composer, a PHP phar, and Pressable's web tier has no PHP CLI binary: Composer cannot run in a web request, which is what Action Scheduler's default runner is.

## Example

Dispatching needs write access to linchpin/actions. Set the three variables first; the branch name here is only an example.

<!-- wp:docspress/terminal-session {"title":"Pin a package at a version in one site repository","shell":"bash","prompt":"$","command":"REPO=linchpin/\u003csite-repository\u003e SLUG=mantle VERSION=\u003cversion\u003e\ngh workflow run composer-bump.yml -R linchpin/actions \\\n  -f repo=\"$REPO\" -f slug=\"$SLUG\" -f version=\"$VERSION\" -f branch=\"bump/$SLUG-$VERSION\""} /-->

<!-- wp:docspress/callout {"tone":"warning","title":"This opens a real pull request","content":"\u003cp\u003eThere is no dry run. The PR opens in the target repository from the \u003ccode\u003ebranch\u003c/code\u003e you name, and the caller finds it by that branch, so choose the name once.\u003c/p\u003e","collapsible":false} /-->

The run is named `Bump <slug> to <version> in <repo> [<correlation_id>]`, because a dispatch returns no run id and the caller finds its run by `correlation_id`.

## How it works

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Check the target","content":"\u003cp\u003e\u003ccode\u003erepo\u003c/code\u003e must be \u003ccode\u003eowner/name\u003c/code\u003e inside this organisation. The workflow lives in a public repository, so the target is checked rather than trusted.\u003c/p\u003e"},{"title":"Mint a token","content":"\u003cp\u003eA Linchpin Governing GitHub App token, scoped to that one repository. The job's own \u003ccode\u003eGITHUB_TOKEN\u003c/code\u003e has no permissions at all.\u003c/p\u003e"},{"title":"Check out the manifests","content":"\u003cp\u003eA sparse checkout of \u003ccode\u003ecomposer.json\u003c/code\u003e and \u003ccode\u003ecomposer.lock\u003c/code\u003e at \u003ccode\u003ebase_branch\u003c/code\u003e, with PHP 8.4 and Composer 2.\u003c/p\u003e"},{"title":"Require a lock","content":"\u003cp\u003eNo \u003ccode\u003ecomposer.json\u003c/code\u003e fails the run. No \u003ccode\u003ecomposer.lock\u003c/code\u003e opens no PR: the deploy never reconciles that repository, so the update was never at risk.\u003c/p\u003e"},{"title":"Find the package","content":"\u003cp\u003eThe \u003ccode\u003erequire\u003c/code\u003e or \u003ccode\u003erequire-dev\u003c/code\u003e key whose name after the slash matches the slug, the same mapping remote-plugin-install uses. Not required: a removal stops there; a bump uses \u003ccode\u003epackage\u003c/code\u003e, or tries the repository's own vendors, then \u003ccode\u003elinchpin\u003c/code\u003e, \u003ccode\u003ewp-plugin\u003c/code\u003e, \u003ccode\u003ewp-theme\u003c/code\u003e, \u003ccode\u003ewpackagist-plugin\u003c/code\u003e and \u003ccode\u003ewpackagist-theme\u003c/code\u003e.\u003c/p\u003e"},{"title":"Change the lock","content":"\u003cp\u003eA removal runs \u003ccode\u003ecomposer remove\u003c/code\u003e. A bump runs \u003ccode\u003ecomposer require --no-update\u003c/code\u003e, then \u003ccode\u003ecomposer update &lt;package&gt; --with-dependencies\u003c/code\u003e, never a wholesale update. Scripts and plugins stay off.\u003c/p\u003e"},{"title":"Open the pull request","content":"\u003cp\u003eTitled \u003ccode\u003echore(deps): bump &lt;package&gt; to &lt;version&gt;\u003c/code\u003e or \u003ccode\u003echore(deps): remove &lt;package&gt;\u003c/code\u003e, with the labels, plus \u003ccode\u003esecurity\u003c/code\u003e when \u003ccode\u003esecurity\u003c/code\u003e is set.\u003c/p\u003e"}]} /-->

The step summary ends with the PR's URL, or `No pull request opened:` and one of these reasons:

| Reason | Meaning |
| --- | --- |
| `no_lock_file` | The repository has no `composer.lock` |
| `not_required` | A removal of a package the repository does not require |
| `package_not_published` | The slug is not required and neither packagist.linchpin.com nor wpackagist publishes it |

| Error | Meaning |
| --- | --- |
| `repo must be owner/name` | `repo` is not in `owner/name` form |
| `Refusing to act on <owner>; this workflow only touches <organisation>.` | The target is outside the organisation |
| `<repo> has no composer.json.` | Nothing to change |
| `Refusing version '<version>'.` | The version is empty or holds characters other than letters, digits and `._+-`, since it reaches a command line |

## The pull request

The body says what changed: a bump from one version to another, a removal, or an addition, which it calls out as a scope change because the package was being managed outside Composer. It adds the `reason` and the `sites` it covers when given, and a table of every package the lock moved. More than one row means `--with-dependencies` surfaced drift that predates the change, worth reading before merging.

It also lists the comments Governing answers on the PR: `@linchpin-packagist rebase`, `@linchpin-packagist recreate` and `@linchpin-packagist close`.

## Secrets

These are read in linchpin/actions itself, not passed by a caller.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"LINCHPIN_GOVERNING_APP_ID","type":"string","required":true,"defaultValue":"","description":"The Linchpin Governing GitHub App's id, for the token scoped to the target repository.","values":"","deprecated":false},{"name":"LINCHPIN_GOVERNING_APP_KEY","type":"string","required":true,"defaultValue":"","description":"That app's private key.","values":"","deprecated":false},{"name":"PACKAGIST_COMPOSER_AUTH_JSON","type":"string","required":false,"defaultValue":"","description":"\u003ccode\u003eCOMPOSER_AUTH\u003c/code\u003e for packagist.linchpin.com. Without it Composer gets a 401 there, and a package Linchpin publishes looks like one nobody publishes.","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Inputs

<!-- wp:docspress/fields {"title":"workflow_dispatch inputs","fields":[{"name":"repo","type":"string","required":true,"defaultValue":"","description":"Target repository, owner/name","values":"","deprecated":false},{"name":"slug","type":"string","required":true,"defaultValue":"","description":"WordPress package slug, e.g. mantle","values":"","deprecated":false},{"name":"operation","type":"enum","required":false,"defaultValue":"bump","description":"bump to pin a package at a version, or remove to stop the repository pinning it at all. A removal matters for the same reason a bump does: the deploy reinstalls whatever composer.lock names, so dropping a plugin from a site without dropping it from the lock brings it back.","values":"bump, remove","deprecated":false},{"name":"version","type":"string","required":false,"defaultValue":"","description":"Version to pin. Ignored for a removal.","values":"","deprecated":false},{"name":"package","type":"string","required":false,"defaultValue":"","description":"Composer package name, when the caller already knows it. Left empty the workflow reads it out of the target's composer.json, which is the only reliable source: the vendor prefix varies per package and per project, and courier-notices ships as wpackagist-plugin/courier-notices next to linchpin/mantle in the same require block.","values":"","deprecated":false},{"name":"base_branch","type":"string","required":false,"defaultValue":"","description":"Branch to open the pull request against. Empty uses the repository default.","values":"","deprecated":false},{"name":"reason","type":"string","required":false,"defaultValue":"","description":"Why this bump is being made; shown in the pull request body.","values":"","deprecated":false},{"name":"sites","type":"string","required":false,"defaultValue":"","description":"Governed sites this covers, comma separated; shown in the body.","values":"","deprecated":false},{"name":"branch","type":"string","required":true,"defaultValue":"","description":"Branch to open the pull request from. Supplied by the caller rather than derived here: the caller finds the resulting pull request by head branch, so the name is a contract and must not be computed twice.","values":"","deprecated":false},{"name":"labels","type":"string","required":false,"defaultValue":"governing,dependencies","description":"Comma-separated labels for the pull request. Defaults deliberately avoid \"automated pr\": these are opened because an operator pushed an update, not by a bot on a schedule, and whoever triages the queue needs to tell those apart.","values":"","deprecated":false},{"name":"security","type":"boolean","required":false,"defaultValue":"false","description":"Whether this change addresses a known vulnerability. Adds a security label and says so in the body, so it can be prioritised over routine maintenance.","values":"","deprecated":false},{"name":"correlation_id","type":"string","required":false,"defaultValue":"","description":"Opaque id echoed into the run name. workflow_dispatch returns no run id, so this is how the caller finds the run it started.","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Permissions

This workflow runs in linchpin/actions itself, not from a caller. Its job token gets:

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `bump` | none — the job's `GITHUB_TOKEN` has no scopes |

## Source

[`.github/workflows/composer-bump.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/composer-bump.yml)
