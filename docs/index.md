---
title: GitHub Actions
---

linchpin/actions holds the reusable GitHub workflows, composite actions and operator scripts that Linchpin's WordPress site and plugin repositories build, check, deploy and maintain themselves with.

<!-- wp:docspress/hero {"eyebrow":"linchpin/actions v4","title":"Shared GitHub workflows for Linchpin WordPress projects","description":"Build, check, deploy and maintain a site or plugin repository with reusable workflows and composite actions, all pinned at @v4.","primaryLabel":"Call a shared workflow","primaryUrl":"/actions/getting-started/","primaryNewTab":false,"secondaryLabel":"Workflow reference","secondaryUrl":"/actions/workflows/","secondaryNewTab":false,"visualVariant":"image","layout":"editorial","mediaPosition":"right","mediaWidth":44,"imageScale":100,"height":"compact","tone":"theme","textAlign":"left","showGrid":false,"showOrbit":false} /-->

<!-- wp:docspress/audience-paths {"eyebrow":"Start here","title":"What are you doing?","description":"Each path starts at the page that answers it.","paths":[{"title":"Deploying a site","description":"Staging on push, production on release, rollback to any earlier release, on Pressable, WP Engine or Cloudways.","url":"/actions/guides/deploy-a-site/","cta":"Deploy a site","icon":"rocket","accent":"blue","newTab":false},{"title":"Checking pull requests","description":"Lint for site repositories; PHPStan, PHPUnit and Plugin Check for plugins.","url":"/actions/guides/pr-checks/","cta":"Set up PR checks","icon":"testing","accent":"green","newTab":false},{"title":"Running maintenance","description":"The permanent maintenance branch, Sisyphus's nightly run, snapshots and conflict hand-off.","url":"/actions/guides/rolling-maintenance/","cta":"Rolling maintenance","icon":"terminal","accent":"gold","newTab":false},{"title":"Changing linchpin/actions","description":"How this repository is checked, how a change is released, and how @v4 moves.","url":"/actions/contributing/","cta":"Contribute","icon":"contribute","accent":"coral","newTab":false}],"columns":2,"tone":"theme","textAlign":"left","compact":false,"showNumbers":false} /-->

## What is here

- **[Reusable workflows](workflows/index.md):** whole jobs a repository calls with `uses: linchpin/actions/.github/workflows/<file>@v4`.
- **[Composite actions](composite-actions/index.md):** the steps those workflows are built from, usable on their own.
- **[Scripts](scripts/index.md):** `bin/convert-repo` and `bin/onboard-site`, which move a site onto rolling maintenance.
- **[Guides](guides/index.md):** the flows that span several of the above.
- **[Renovate presets](renovate-presets.md):** the Renovate configuration this repository carries, and where the live presets are.

<!-- wp:docspress/diagram {"title":"How a change reaches a site","type":"flow","source":"Pull request -\u003e lint.yml: checks\nPull request -\u003e Staging branch: merge\nStaging branch -\u003e deploy.yml: push deploys staging\nrelease-please -\u003e GitHub release: release PR merged\nGitHub release -\u003e deploy.yml: build_for_release deploys production\ndeploy.yml -\u003e Deployment log: report-deployment","caption":"A typical site repository. Rolling maintenance feeds Renovate updates into the same path."} /-->

## Start

1. [Call a shared workflow](getting-started/index.md): pinning `@v4`, secrets, permissions and concurrency.
2. [Secrets and variables](getting-started/secrets-and-variables.md): every one the workflows read.
3. [Choosing a runner](getting-started/choosing-a-runner.md).

Moving from `@v3`, `@v2` or `@main`? Read [Migrating from v3 to v4](MIGRATION-v3-to-v4.md). Something failed? Try [Troubleshooting](troubleshooting.md).
