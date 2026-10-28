#!/usr/bin/env bash
#
# Rolling maintenance: bring the production branch in, then merge what is green.
#
# One permanent maintenance branch (MAINTENANCE_BRANCH, `maintenance`), never
# closed and never dated. The site's renovate.json routes non-major updates,
# lock-file maintenance and the Linchpin packages Linchpin Governing does not
# watch to it; third-party majors, security fixes and Governing's bumps go to the
# production branch. This script keeps the branch current, in two hops, and is run by
# .github/workflows/rolling-maintenance.yml in linchpin/actions:
#
#   1. The production branch (PRODUCTION_BRANCH, the repository's default branch)
#      is brought into the maintenance branch first, so every update is tested on
#      top of it: a fast-forward when the branch has nothing of its own, otherwise
#      a merge commit made by GitHub.
#   2. A Renovate PR into the maintenance branch is squash-merged once every check
#      on its head is green. One labelled automerge-safe needs nothing more; any
#      other, a major or the PHPStan PR, waits for a person's approving review. No
#      other rules: the branch needs none, and a PR need not be up to date,
#      because the snapshot PR checks the combination. A red one whose checks ran
#      before something other than another update changed the branch (the
#      production branch coming in, a person's fix) is asked to retry through
#      Renovate's rebase box, because nothing else runs its checks again: a
#      broken branch would otherwise leave every PR it failed red after the fix.
#
# It never promotes. The maintenance branch reaches production only through a
# snapshot PR that a person approves and merges (actions/snapshot), and
# production moves only when the release-please release is published.
#
# It resolves no conflict itself. When both branches changed neighbouring lines,
# nearly always in a manifest or lockfile, GitHub refuses the merge. With
# LOCK_RESOLVER=true the script hands that to actions/resolve-merge (the workflow
# runs it next, then this script again), on every run while the conflict lasts:
# the production branch keeps moving, and a conflict the resolver gave up on can
# become one it resolves. Once the resolver has given up, or without
# LOCK_RESOLVER, it opens one issue labelled maintenance-conflict for a person,
# and closes it once the production branch is in again. Sisyphus reads that
# label, so it is not an input.
#
# Run it locally to see what it would do against the live repository:
#
#   GH_REPO=linchpin/linchpin.com DRY_RUN=true actions/rolling-maintenance/rolling-maintenance.sh
#
# Env: GH_REPO (owner/name, required), GH_TOKEN (gh's own login otherwise),
# DRY_RUN (true logs every write instead of making it), GITHUB_STEP_SUMMARY,
# LOCK_RESOLVER (true hands a refused merge to the resolver through GITHUB_OUTPUT;
# tried says it already gave up), MAINTENANCE_BRANCH (maintenance),
# PRODUCTION_BRANCH (the default branch), BRANCH_SKIPS_CHECKS (checks the
# production branch requires that never run on a PR into the maintenance branch,
# one per line), and SELF_CHECK (this job's own check name, Rolling maintenance,
# which is never waited for).

set -euo pipefail

: "${GH_REPO:?Set GH_REPO to owner/name}"
DRY_RUN=${DRY_RUN:-false}
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
LOCK_RESOLVER=${LOCK_RESOLVER:-false}

BRANCH=${MAINTENANCE_BRANCH:-maintenance}
CONFLICT=maintenance-conflict
# The workflow job's own check run sits on the branch head while it runs. Called
# from a site's workflow, GitHub names it "<caller's job> / Rolling maintenance".
SELF=${SELF_CHECK:-Rolling maintenance}
BASE=${PRODUCTION_BRANCH:-$(gh api "repos/$GH_REPO" --jq .default_branch)}
SKIPS=${BRANCH_SKIPS_CHECKS:-}

note() {
	echo "$*" >&2
	echo "- $*" >>"$SUMMARY"
}

# Every write goes through here, so a dry run reports it instead.
write() {
	if [ "$DRY_RUN" = "true" ]; then
		note "Dry run, would run: $*"
		return 0
	fi
	"$@"
}

ref_sha() {
	gh api "repos/$GH_REPO/git/ref/heads/$1" --jq .object.sha
}

ensure_label() {
	gh api "repos/$GH_REPO/labels/$1" >/dev/null 2>&1 ||
		write gh api "repos/$GH_REPO/labels" -f name="$1" -f color="$2" -f description="$3" >/dev/null
}

# green, pending or red for a commit. Green needs every check finished and
# passing, and each name in $2 (a JSON array) present among them.
verdict() {
	gh api "repos/$GH_REPO/commits/$1/check-runs?per_page=100" |
		jq -r --arg self "$SELF" --argjson want "$2" '
			def ok: (.conclusion // "") as $c | $c == "success" or $c == "skipped" or $c == "neutral";
			[.check_runs[] | select(.name != $self and (.name | endswith(" / " + $self) | not))] as $runs
			| if any($runs[]; .status != "completed") then "pending"
			  elif any($runs[]; ok | not) then "red"
			  elif ($want - [$runs[].name] | length) > 0 then "pending"
			  else "green" end'
}

# true when a person approved the PR and nobody's latest review asks for changes.
approved() {
	gh api "repos/$GH_REPO/pulls/$1/reviews?per_page=100" --jq '
		[.[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")]
		| group_by(.user.login) | map(last.state)
		| any(. == "APPROVED") and all(. != "CHANGES_REQUESTED")'
}

# The checks the production branch requires, read from its rules rather than
# copied here.
required=$(gh api "repos/$GH_REPO/rules/branches/$BASE" \
	--jq '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]')
# Some run only on PRs into the production branch, like linchpin.com's npm audit,
# so a Renovate PR into the branch reports them skipped at most; the snapshot PR
# runs them.
into_branch=$(jq -c --arg skips "$SKIPS" '. - ($skips | split("\n") | map(select(length > 0)))' <<<"$required")

# The branch is permanent: recreate it from the production branch if it was deleted.
if ! ref_sha "$BRANCH" >/dev/null 2>&1; then
	# Git cannot hold `maintenance` beside `maintenance/YYYY-MM`: one name would be
	# a file and a directory at once. Dated windows have to go first.
	blocking=$(gh api "repos/$GH_REPO/git/matching-refs/heads/$BRANCH/" --jq '.[].ref | sub("^refs/heads/"; "")' | tr '\n' ' ')
	if [ -n "$blocking" ]; then
		note "Cannot create \`$BRANCH\` while these branches exist; merge or delete them first: $blocking"
		exit 1
	fi
	write gh api "repos/$GH_REPO/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$(ref_sha "$BASE")" >/dev/null
	note "Created \`$BRANCH\` from \`$BASE\`."
	exit 0
fi

# Hop 1: the production branch into the maintenance branch.
read -r ahead behind < <(gh api "repos/$GH_REPO/compare/$BASE...$BRANCH" \
	--jq '"\(.ahead_by) \(.behind_by)"')
issue=$(gh api "repos/$GH_REPO/issues?state=open&labels=$CONFLICT&per_page=10" \
	--jq '[.[] | select(.pull_request | not)][0].number // empty')
level=false

if [ "$behind" -eq 0 ]; then
	level=true
elif [ "$ahead" -eq 0 ]; then
	write gh api -X PATCH "repos/$GH_REPO/git/refs/heads/$BRANCH" \
		-f sha="$(ref_sha "$BASE")" -F force=false >/dev/null
	note "Fast-forwarded \`$BRANCH\` to \`$BASE\`."
	level=true
elif [ "$DRY_RUN" = "true" ]; then
	note "Dry run, would merge \`$BASE\` into \`$BRANCH\` ($behind commits behind, $ahead ahead)."
elif out=$(gh api "repos/$GH_REPO/merges" -f base="$BRANCH" -f head="$BASE" \
	-f commit_message="Merge branch '$BASE' into $BRANCH" 2>&1); then
	note "Merged \`$BASE\` into \`$BRANCH\` ($behind commits)."
	level=true
elif grep -q 'HTTP 409' <<<"$out"; then
	# GitHub refuses rather than guesses when both sides changed neighbouring
	# lines. The resolver gets every run, even with the issue open.
	if [ "$LOCK_RESOLVER" = "true" ]; then
		echo "conflict=true" >>"${GITHUB_OUTPUT:-/dev/null}"
		note "\`$BASE\` conflicts with \`$BRANCH\`; handing it to linchpin/actions resolve-merge."
	elif [ -n "$issue" ]; then
		note "\`$BASE\` still conflicts with \`$BRANCH\`; #$issue is open for a person."
	else
		ensure_label "$CONFLICT" B60205 "Main and maintenance changed the same lockfile"
		tried=""
		if [ "$LOCK_RESOLVER" = "tried" ]; then
			tried=" linchpin/actions resolve-merge tried first and gave up; the workflow run's summary says why and names the files left."
		fi
		body=$(printf '%s\n\n%s\n\n%s\n' \
			"**\`$BASE\` and \`$BRANCH\` changed the same lines, so \`$BASE\` cannot be brought into \`$BRANCH\` automatically.**$tried" \
			"Merge \`$BASE\` into \`$BRANCH\` locally, resolve what the resolver could not, and push. For a lockfile, take the lock from \`$BASE\` and re-run \`composer update\` (or \`npm install\`) for the packages \`$BRANCH\` bumped. The next run closes this issue." \
			"_Opened by linchpin/actions rolling-maintenance._")
		number=$(gh api "repos/$GH_REPO/issues" -f title="Bring $BASE into $BRANCH by hand" \
			-f body="$body" -f "labels[]=$CONFLICT" --jq .number)
		note "\`$BASE\` conflicts with \`$BRANCH\`; opened #$number for a person."
	fi
else
	note "Could not merge \`$BASE\` into \`$BRANCH\`: $out"
	exit 1
fi

if [ "$level" = "true" ] && [ -n "$issue" ]; then
	write gh api -X PATCH "repos/$GH_REPO/issues/$issue" -f state=closed -f state_reason=completed >/dev/null
	note "Closed #$issue: \`$BASE\` is in \`$BRANCH\` again."
fi

# true when the branch changed under a PR since its checks ran ($1, the base they
# tested), by anything but another Renovate update: production coming in, a person's
# fix, a merge resolve-merge pushed. CI runs only on a push to the PR, and
# Renovate rebases a PR here only when it conflicts, so a PR that a broken branch
# failed stays red once the branch is fixed unless it is asked to retry. Another
# update merging is no reason to expect a pass, and retrying after every one
# would only re-run CI.
moved_under() {
	if [ "$1" = "$head" ]; then
		echo false
		return
	fi
	gh api "repos/$GH_REPO/compare/$1...$head" \
		--jq 'any(.commits[]; .author.login != "renovate[bot]")'
}

# Ticks Renovate's rebase box on PR $1 (head $2), which Renovate answers by
# rebasing it onto the branch, so its checks run again. Not by pushing to it: a
# commit Renovate does not recognise makes it abandon the PR. For the same reason
# never over a commit someone else pushed, which the rebase would throw away.
retry() {
	local box='- [ ] <!-- rebase-check -->' ticked='- [x] <!-- rebase-check -->' body
	if [ "$(gh api "repos/$GH_REPO/commits/$2" --jq '.author.login')" != "renovate[bot]" ]; then
		note "#$1 into \`$BRANCH\`: checks red, and someone other than Renovate pushed to it; not retrying."
		return
	fi
	body=$(gh api "repos/$GH_REPO/pulls/$1" --jq .body)
	if ! grep -qF -- "$box" <<<"$body"; then
		note "#$1 into \`$BRANCH\`: checks red, and a retry is already asked for."
		return
	fi
	# On stdin, so a dry run logs the call rather than the whole body.
	write gh api -X PATCH "repos/$GH_REPO/pulls/$1" --input - >/dev/null \
		<<<"$(jq -n --arg body "${body/"$box"/$ticked}" '{body: $body}')"
	note "#$1 into \`$BRANCH\`: checks red from before \`$BRANCH\` last changed; asked Renovate to retry."
}

# Hop 2: green Renovate PRs into the branch, approved ones when not automerge-safe.
head=$(ref_sha "$BRANCH")
gh api "repos/$GH_REPO/pulls?state=open&base=$BRANCH&per_page=100" |
	jq -r '.[] | select(.user.login == "renovate[bot]" and (.draft | not))
	           | "\(.number) \(.head.sha) \(.base.sha) \(any(.labels[]; .name == "automerge-safe"))"' |
	while read -r number sha tested safe; do
		v=$(verdict "$sha" "$into_branch")
		# Before the approval check, so a reviewer sees a fair result.
		if [ "$v" = "red" ] && [ "$(moved_under "$tested")" = "true" ]; then
			retry "$number" "$sha"
			continue
		fi
		if [ "$safe" != "true" ] && [ "$(approved "$number")" != "true" ]; then
			note "#$number into \`$BRANCH\`: waiting for an approving review."
			continue
		fi
		if [ "$v" != "green" ]; then
			note "#$number into \`$BRANCH\`: checks $v."
			continue
		fi
		if write gh api -X PUT "repos/$GH_REPO/pulls/$number/merge" \
			-f merge_method=squash -f sha="$sha" >/dev/null; then
			note "Merged #$number into \`$BRANCH\`."
		else
			note "Could not merge #$number (conflicted, or pushed since); Renovate rebases it."
		fi
	done
