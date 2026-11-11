---
title: Scripts
---

Two scripts in `bin/` put a site on rolling maintenance. They run on a person's machine, from a checkout of linchpin/actions, not in a workflow.

| Script | Does |
| --- | --- |
| [bin/convert-repo](convert-repo.md) | Moves one site repository onto rolling maintenance: closes monthly windows, creates `maintenance`, opens the PR with the three callers, sets up dev's GitHub environment and adds the maintenance ruleset |
| [bin/onboard-site](onboard-site.md) | The whole onboarding of one client site: picks dev and staging, checks Sisyphus can reach dev, runs `bin/convert-repo`, enrolls the site in Sisyphus, runs the first Deploy to Dev and starts the first run |

Both work the same way:

- **A plan by default.** Without `--apply` they only report. Each line says what is done (`✓`), what `--apply` would do (`→`), a note (`~`), or what needs a person (`!`).
- **Safe to run again.** They make only the changes still missing, so a run after a person's fix carries on where the last one stopped.
- **The same exit status.** `0` when the work is done or the plan needs nothing from a person, `2` when something needs a person first, `1` on an error.
- **Plain tools.** `gh` logged in as a repository admin with the `workflow` scope, and `jq`; `bin/onboard-site` also needs `curl`. Both run on macOS's own bash 3.2.

[Rolling maintenance](../guides/rolling-maintenance.md) explains what they set up.
