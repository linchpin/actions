---
title: Browser QA
---

Client repositories keep their browser tests in a `qa/` directory, run by the QA platform ([linchpin/automated-testing](https://github.com/linchpin/automated-testing)), which replaced Ghost Inspector. Two shared workflows cover it: [qa-guard.yml](../workflows/qa-guard.md) checks the tests on every pull request, and [qa-run.yml](../workflows/qa-run.md) runs them against a site after each deploy.

<!-- wp:docspress/flow {"start":1,"steps":[{"title":"A pull request touches qa/","content":"\u003cp\u003eOpened by a person, or by the QA platform's GitHub App.\u003c/p\u003e"},{"title":"qa-guard checks it","content":"\u003cp\u003eEvery \u003ccode\u003eqa/\u003c/code\u003e file is validated against the platform's schema, and a platform-authored PR that changes anything outside \u003ccode\u003eqa/\u003c/code\u003e fails.\u003c/p\u003e"},{"title":"The change merges and deploys","content":"\u003cp\u003eThrough the repository's normal deploy workflow.\u003c/p\u003e"},{"title":"qa-run tests the deployed site","content":"\u003cp\u003eA job after the deploy triggers a run, polls it to a terminal state, and fails when a test is red.\u003c/p\u003e"}]} /-->

## Tokens

Each workflow needs one secret, and they are not interchangeable.

| Secret | Used by | What it is |
| --- | --- | --- |
| `QA_SCHEMA_TOKEN` | `qa-guard.yml` | A token that can read `linchpin/automated-testing`, where the schema lives. That repository is private, so without it the schema job fails closed. |
| `QA_API_TOKEN` | `qa-run.yml` | The project's bearer token, minted from the QA platform. Each token is scoped to one project, so a client repository holds only its own and a leaked token cannot trigger or read another client's runs. |

## Guard the tests on pull requests

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

- **schema** validates every `qa/` file against the platform's own Zod schema and reports targets a test references but `targets.yaml` never defines, which would otherwise fail at run time with `Unknown target`. Pin `schema_ref` to make the gate reproducible.
- **boundary** fails a pull request authored by the QA platform's GitHub App that changes anything outside `qa/`. The platform opens PRs into client production repositories, so this is the guardrail on our own tooling. PRs authored by people are not bound by it.

`qa_path` must match the project's `qa_path` in the platform. It defaults to `qa`.

## Run the suite after a deploy

Add a job that needs the deploy:

```yaml
jobs:
  # ... your build + deploy jobs ...

  qa:
    needs: [deploy]
    uses: linchpin/actions/.github/workflows/qa-run.yml@v4
    secrets:
      QA_API_TOKEN: ${{ secrets.QA_API_TOKEN }}
    with:
      project: linchpin-com
      environment: production
```

It triggers a run, polls it to a terminal state, and fails when a test is red, naming the failing tests in the log and the job summary. The run records the deployed commit unless `ref` says otherwise. Re-running a green deploy while the same suite is still queued passes straight away, because the platform de-duplicates queued runs.

A red run fails the workflow run, not the deploy: the code is already live, and nothing is rolled back.

## When it fails

| Symptom | Check |
| --- | --- |
| `Triggering the run failed (HTTP 403)` | `QA_API_TOKEN` belongs to another project. |
| `Status poll failed (HTTP 401)` or `(HTTP 403)` | The token was revoked, or is for another project. Permanent statuses fail at once rather than timing out. |
| `Run … did not reach a terminal state within … minute(s)` | The suite took longer than `timeout_minutes`, 20 by default. |
| `This PR was authored by the QA platform but changes files outside qa/.` | Do not merge it until the platform's change is understood. |
| Schema job fails before validating | `QA_SCHEMA_TOKEN` is missing or cannot read `linchpin/automated-testing`. |

The unit pages carry the full behaviour: [qa-guard.yml](../workflows/qa-guard.md) and [qa-run.yml](../workflows/qa-run.md).
