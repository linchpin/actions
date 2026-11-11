---
title: report-deployment
---

`report-deployment` records a finished deploy in the deployment log on api.linchpin.com: which commit went to which environment, the commits since that environment's last successful deploy, and, for a release, the release's notes. [`deploy.yml`](../workflows/deploy.md) and [`deploy-continue.yml`](../workflows/deploy-continue.md) run it as their last step, on success or failure.

## Example

As `deploy.yml` runs it, after the step that created the GitHub Deployment:

```yaml
- name: Report to the deployment log
  if: ${{ always() && steps.deployment.outputs.id != '' }}
  continue-on-error: true
  timeout-minutes: 3
  uses: linchpin/actions/actions/report-deployment@v4
  with:
    deployment-id: ${{ steps.deployment.outputs.id }}
    status: ${{ job.status }}
    environment-url: ${{ vars.SITE_URL }}
    client-id: ${{ secrets.DEPLOYMENTS_API_CLIENT_ID }}
    client-secret: ${{ secrets.DEPLOYMENTS_API_CLIENT_SECRET }}
```

Run it with `continue-on-error`: a refusal exits non-zero as a warning, and logging must never fail a deploy.

## How it works

1. Without `client-id` and `client-secret` it notes `Not reported: DEPLOYMENTS_API_CLIENT_ID and DEPLOYMENTS_API_CLIENT_SECRET are not set.` and succeeds.
2. Maps `status`: `success` and `failure` pass through; anything else, such as `cancelled`, is sent as `error`.
3. Reads the GitHub Deployment for its commit, environment and start time, and the `branch`, `release_tag` and `correlation_id` that `deploy.yml` puts in its payload.
4. Finds the commit the environment had before: the newest earlier deployment to it, among the last 30, that ever reached `success`. It reads each status history rather than the current state, because GitHub marks a superseded deployment inactive.
5. Compares that commit with this one and lists the commits between them, oldest first: first line of the message, author, whether it is a merge, and whether it declares a `BREAKING CHANGE:`.
6. Adds the release's notes when the payload names a `release_tag`, unless the comparison says this deploy went back to an older commit.
7. Exchanges the client credentials for a token at `<api-url>/auth/token`, posts the report to `<api-url>/deployments`, and writes the log's notes to the step summary.

`deploy.yml` passes the `DEPLOYMENTS_API_CLIENT_ID` and `DEPLOYMENTS_API_CLIENT_SECRET` secrets, which are organization secrets and reach callers through `secrets: inherit`.

## Run it locally

The script prints what it would send, without credentials, when `DRY_RUN` is `true`. It reads the deployment with your `gh` login:

```bash
GH_REPO=owner/site DEPLOYMENT_ID=1234567890 STATUS=success \
  DRY_RUN=true actions/report-deployment/report-deployment.sh
```

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"deployment-id","type":"string","required":true,"defaultValue":"","description":"The GitHub Deployment to report","values":"","deprecated":false},{"name":"status","type":"string","required":true,"defaultValue":"","description":"The job's status: success, failure or cancelled","values":"","deprecated":false},{"name":"environment-url","type":"string","required":false,"defaultValue":"","description":"The deployed site's URL, which places the deploy on its site","values":"","deprecated":false},{"name":"client-id","type":"string","required":false,"defaultValue":"","description":"An api.linchpin.com application client with deployments:write","values":"","deprecated":false},{"name":"client-secret","type":"string","required":false,"defaultValue":"","description":"That client's secret","values":"","deprecated":false},{"name":"api-url","type":"string","required":false,"defaultValue":"https://api.linchpin.com/api/v1","description":"api.linchpin.com's API base","values":"","deprecated":false},{"name":"github-token","type":"string","required":false,"defaultValue":"${{ github.token }}","description":"Reads the deployment, its history, the comparison and the release","values":"","deprecated":false}],"searchable":true,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/report-deployment/action.yml), [`report-deployment.sh`](https://github.com/linchpin/actions/blob/main/actions/report-deployment/report-deployment.sh)
