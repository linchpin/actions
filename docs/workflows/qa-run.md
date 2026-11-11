---
title: qa-run.yml
---

The deploy-time QA gate, replacing the Ghost Inspector job in client repositories. A job after the deploy triggers a run on the QA platform, polls it to a terminal state, and fails when a test is red: the `--errorOnFail` behaviour the team kept.

## Example

The only setup a client repository needs is its per-project bearer token in the `QA_API_TOKEN` secret, minted from the QA platform.

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
      # Optional: narrow to one suite, override the recorded ref, or tune waits.
      # suite: smoke
      # ref: ${{ github.sha }}
      # poll_interval_seconds: 10
      # timeout_minutes: 20
```

## How it works

<!-- wp:docspress/diagram {"title":"One QA run","type":"sequence","source":"qa-run.yml -\u003e QA API: POST /api/v1/runs\nQA API -\u003e qa-run.yml: 202 with batchId\nqa-run.yml -\u003e QA API: GET /api/v1/runs/{batchId}, every poll_interval_seconds\nQA API -\u003e qa-run.yml: state queued, running, succeeded, failed or cancelled\nqa-run.yml -\u003e QA API: GET /api/v1/runs/{batchId}/results, on failure","caption":"Requests go to api_base; ui_base only builds the run-detail links."} /-->

1. **Trigger.** `POST /api/v1/runs` with `project` and `environment`, plus `suite` and `ref` when they are set. `ref` defaults to the commit that called the workflow, so the run always records what was deployed. Anything but a 202 fails the job with the platform's own error detail.
2. **Poll.** `GET /api/v1/runs/{batchId}` every `poll_interval_seconds` until the run is `succeeded`, `failed` or `cancelled`.
3. **Report.** A pass writes the passed/total count and a run-detail link to the job summary. A failure or cancellation reads the results endpoint, lists each failing test with its error message, and fails the job.

Polling exists because a held request cannot work: Cloudflare's edge drops a held HTTP connection at about 100 seconds, and a real suite takes minutes.

<!-- wp:docspress/callout {"tone":"note","title":"Two hosts","content":"\u003cp\u003e\u003ccode\u003eapi_base\u003c/code\u003e (\u003ccode\u003ehttps://qa-api.linchpin.com\u003c/code\u003e) takes bearer tokens and has no Cloudflare Access in front of it. \u003ccode\u003eui_base\u003c/code\u003e (\u003ccode\u003ehttps://qa.linchpin.com\u003c/code\u003e) is behind Access, so a request there gets a 302 to the Access sign-in page instead of a run. Override \u003ccode\u003eapi_base\u003c/code\u003e only for staging.\u003c/p\u003e","collapsible":false} /-->

## Behaviour notes

- **A null batch id passes.** The platform de-duplicates identical queued runs, so re-triggering a suite that is already queued for the same ref returns `batchId: null`. The job passes with `All <n> test(s) already queued by an earlier trigger; nothing new to run.` rather than breaking a re-run of a green deploy.
- **Transient errors are retried, permanent ones are not.** A poll answered 408, 425, 429, 500, 502, 503 or 504 is retried. Any other status, such as a revoked or wrong-project token (401, 403) or a batch the token cannot see (404), fails at once instead of timing out minutes later.
- **The token is scoped to one project.** A token for the wrong project surfaces as a 403 on the trigger.
- **The deadline is `timeout_minutes`.** The job's own 60-minute limit is only a backstop, so keep `timeout_minutes` below it to get a message that names the run. Both `timeout_minutes` and `poll_interval_seconds` must be whole numbers.
- **It does not roll anything back.** It runs after the deploy job, so a red run fails the workflow run while the code stays deployed.

## Errors

| Message | Cause |
| --- | --- |
| `Triggering the run failed (HTTP <status>): <detail>` | The trigger was refused; 403 usually means the token belongs to another project. |
| `Status poll failed (HTTP <status>): <detail>. See <run_url>` | A non-transient status while polling. |
| `Run <batchId> did not reach a terminal state within <n> minute(s). See <run_url>` | The suite outlasted `timeout_minutes`. |
| `QA run failed. See <run_url>` (or `cancelled`) | At least one test failed or the run was cancelled; the failing tests follow in the log and the summary. |
| `<name> must be a whole number (got '<value>').` | A fractional `timeout_minutes` or `poll_interval_seconds`. |

See [Browser QA](../guides/qa.md) for the PR-side guard and the two tokens.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"project","type":"string","required":true,"defaultValue":"","description":"Project slug as registered in the QA platform.","values":"","deprecated":false},{"name":"environment","type":"string","required":true,"defaultValue":"","description":"Environment name to run against, e.g. production.","values":"","deprecated":false},{"name":"suite","type":"string","required":false,"defaultValue":"","description":"Optional suite path to narrow the run. Omit to run every active test.","values":"","deprecated":false},{"name":"ref","type":"string","required":false,"defaultValue":"","description":"The deployed ref, recorded on the run as provenance. Defaults to the calling commit SHA.","values":"","deprecated":false},{"name":"api_base","type":"string","required":false,"defaultValue":"https://qa-api.linchpin.com","description":"Base URL of the QA platform's machine API (bearer token, no Access). Override only for staging.","values":"","deprecated":false},{"name":"ui_base","type":"string","required":false,"defaultValue":"https://qa.linchpin.com","description":"Base URL of the QA platform's UI. Used only for the run-detail links in the job output.","values":"","deprecated":false},{"name":"poll_interval_seconds","type":"number","required":false,"defaultValue":"10","description":"Seconds between status polls.","values":"","deprecated":false},{"name":"timeout_minutes","type":"number","required":false,"defaultValue":"20","description":"How long to wait for a terminal result before failing cleanly.","values":"","deprecated":false},{"name":"runner","type":"string","required":false,"defaultValue":"","description":"Runner label for this workflow's jobs. Defaults to vars.RUNNER, then ubuntu-latest","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Secrets

Declared secrets can be passed one by one or with `secrets: inherit`.

<!-- wp:docspress/fields {"title":"Secrets","fields":[{"name":"QA_API_TOKEN","type":"string","required":true,"defaultValue":"","description":"Per-project bearer token minted by the QA platform. Fails closed if absent.","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Permissions

A called workflow can only lower the permissions its caller grants, so the calling job must grant at least these.

| Job | `GITHUB_TOKEN` permissions |
| --- | --- |
| `qa-run` | `contents: read` |

## Source

[`.github/workflows/qa-run.yml`](https://github.com/linchpin/actions/blob/main/.github/workflows/qa-run.yml)
