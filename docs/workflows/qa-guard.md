---
title: qa-guard.yml
---

The pull-request gate for a client repository's `qa/` directory of browser tests, managed by the QA platform ([linchpin/automated-testing](https://github.com/linchpin/automated-testing)). Two independent jobs answer two different questions: did a platform-authored PR touch anything outside `qa/`, and are the `qa/` files valid?

## Example

```yaml
name: QA Guard
on:
  pull_request:

jobs:
  qa-guard:
    uses: linchpin/actions/.github/workflows/qa-guard.yml@v4
    secrets:
      QA_SCHEMA_TOKEN: ${{ secrets.QA_SCHEMA_TOKEN }}
```

## How it works

### boundary

Fails when a pull request authored by the QA platform's GitHub App changes anything outside `qa_path`. The platform opens PRs into client production repositories, so a bug there would put unwanted changes into a client's codebase in a PR that looks ordinary; this makes that failure loud and unmergeable.

- It binds only PRs whose author, `pull_request.user.login`, is `platform_actor` (default `linchpin-qa[bot]`). People legitimately change application code and its tests together, so their PRs pass with a notice. Authorship is not taken from `github.actor`, so a person pushing a fixup commit onto the platform's branch does not switch the check off.
- The changed paths come from the API, paginated, so no full-history checkout is needed.
- Each path outside `qa_path` gets its own error annotation.
- Outside a pull request there are no changed paths, and the job passes with a notice.

### schema

Validates every `qa/` file against the Zod schema in `linchpin/automated-testing`, the single definition of a valid test shared by the platform's Worker, API and AI generator. Re-implementing it here would create a second definition that drifts.

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"Check out both repositories","content":"\u003cp\u003eThe client repository, then \u003ccode\u003elinchpin/automated-testing\u003c/code\u003e at \u003ccode\u003eschema_ref\u003c/code\u003e into \u003ccode\u003e.qa-schema\u003c/code\u003e with \u003ccode\u003eQA_SCHEMA_TOKEN\u003c/code\u003e. Neither checkout persists its credentials.\u003c/p\u003e"},{"title":"Install the validator","content":"\u003cp\u003eNode from \u003ccode\u003enode_version\u003c/code\u003e, else \u003ccode\u003evars.NODE_VERSION\u003c/code\u003e, else 24; then \u003ccode\u003enpm ci --ignore-scripts\u003c/code\u003e in the schema checkout.\u003c/p\u003e"},{"title":"Validate","content":"\u003cp\u003e\u003ccode\u003enpx tsx scripts/validate-qa.ts\u003c/code\u003e against \u003ccode\u003eqa_path\u003c/code\u003e in the client checkout.\u003c/p\u003e"}]} /-->

The validator ([`scripts/validate-qa.ts`](https://github.com/linchpin/automated-testing/blob/main/scripts/validate-qa.ts)) parses `targets.yaml`, `environments.yaml`, `suite.yaml` and every `*.test.yaml` or `*.test.yml` file, and reports targets a test references but `targets.yaml` never defines, suggesting the closest defined name. Those otherwise fail at run time with `Unknown target`, a slower and more confusing way to find a typo. A repository with no `qa/` directory passes.

## Behaviour notes

- **`QA_SCHEMA_TOKEN` is required** because the schema repository is private; without it the schema job fails closed. It is used for that one checkout and not persisted, so no later step can reach the repository with it.
- **Pin `schema_ref`** to make the gate reproducible rather than tracking `main`.
- **`qa_path` must match** the project's `qa_path` in the platform. It defaults to `qa`.
- The schema's dependencies install with `--ignore-scripts`, so no postinstall code runs in a client's CI.

See [Browser QA](../guides/qa.md) for running the suite after a deploy.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"qa_path","type":"string","required":false,"defaultValue":"qa","description":"Directory holding the tests. Must match the project's qa_path in the platform.","values":"","deprecated":false},{"name":"platform_actor","type":"string","required":false,"defaultValue":"linchpin-qa[bot]","description":"Login of the GitHub App's bot account. PRs authored by it are held to the path boundary.","values":"","deprecated":false},{"name":"schema_ref","type":"string","required":false,"defaultValue":"main","description":"Ref of linchpin/automated-testing to validate against. Pin this to make the gate reproducible.","values":"","deprecated":false},{"name":"node_version","type":"string","required":false,"defaultValue":"","description":"Node version. Defaults to vars.NODE_VERSION, then 24.","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"QA_SCHEMA_TOKEN","type":"string","required":true,"defaultValue":"","description":"Token that can read linchpin/automated-testing. Without it the schema job cannot run and fails closed.","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `boundary` | `contents: read`, `pull-requests: read` |
| `schema` | `contents: read` |

## Source

[`.github/workflows/qa-guard.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/qa-guard.yml)
