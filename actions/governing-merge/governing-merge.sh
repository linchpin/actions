#!/usr/bin/env bash
#
# Merge Linchpin Governing's release bumps into the production branch (main
# below: PRODUCTION_BRANCH, the default branch) once they are green.
#
# When one of Linchpin's own packages publishes a release, Linchpin Governing
# (packagist-plugin-manager, on packagist.linchpin.com) opens a PR against main
# from governing/bump-<slug>-<version> that changes composer.json and
# composer.lock. Renovate does not raise those packages (renovate.json, routing
# rule 5), so this is the only way they arrive, and no person reviews each one:
# the code was reviewed in its own repository, CI still runs here, and production
# still moves only when a person merges the release PR. That is what gets a
# release onto main in minutes rather than whenever someone next looks.
#
# A PR merges once all of these hold:
#
#   - linchpin-packagist[bot] opened it from governing/bump-*, labelled automated:
#     the release watcher, not a person pushing an update by hand.
#   - It changes composer.json and composer.lock and nothing else, moves one
#     require entry main already had (adding a package is a scope change), and
#     its lock moves that package alone.
#   - It is not a major, where the leading version number changes, unless a
#     person has approved it. A 0.x minor (0.23 to 0.24) is not a major here.
#   - It is up to date with main, and every check on its head is green, each
#     check main requires among them.
#
# Behind main, it updates the branch, which runs CI again. Conflicted, because
# another bump merged first and moved composer.lock's content-hash, it asks
# Governing to regenerate the lock against main; Governing reads that comment
# within about fifteen minutes. Either way a later run merges it.
#
# linchpin-bot is exempt from main's ruleset, which is why this can merge without
# a review, and why it checks the ruleset's conditions itself first.
#
#   GH_REPO=linchpin/linchpin.com DRY_RUN=true actions/governing-merge/governing-merge.sh
#
# Env: GH_REPO (owner/name, required), GH_TOKEN (gh's own login otherwise),
# DRY_RUN (true logs every write instead of making it), GITHUB_STEP_SUMMARY,
# PRODUCTION_BRANCH (the default branch), COMMIT_PREFIX (the squash commit's type
# and scope, worded like the repository's Renovate updates; build(composer):),
# SELF_CHECK (the calling job's own check name, Rolling maintenance), and PRS,
# only to dry-run against past PRs: it judges those numbers whatever their state,
# and forces DRY_RUN.

set -euo pipefail

: "${GH_REPO:?Set GH_REPO to owner/name}"
DRY_RUN=${DRY_RUN:-false}
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
PRS=${PRS:-}
if [ -n "$PRS" ]; then
	DRY_RUN=true
fi

GOVERNING="linchpin-packagist[bot]"
ME=$(gh api user --jq .login)
SELF=${SELF_CHECK:-Rolling maintenance}
BASE=${PRODUCTION_BRANCH:-$(gh api "repos/$GH_REPO" --jq .default_branch)}
PREFIX=${COMMIT_PREFIX:-build(composer):}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

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

# green, pending or red for a commit, as in rolling-maintenance.sh. Green needs
# every check finished and passing, and each name in $2 (a JSON array) present.
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

# true when a person approved the PR and nobody's latest review asks for
# changes, as in rolling-maintenance.sh.
approved() {
	gh api "repos/$GH_REPO/pulls/$1/reviews?per_page=100" --jq '
		[.[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")]
		| group_by(.user.login) | map(last.state)
		| any(. == "APPROVED") and all(. != "CHANGES_REQUESTED")'
}

# A file as it is at a commit, saved under $work; prints the path.
fetch() {
	gh api -H "Accept: application/vnd.github.raw" "repos/$GH_REPO/contents/$1?ref=$2" >"$work/$1.$2"
	echo "$work/$1.$2"
}

# The leading number of a version or constraint: 3 for ^3.2.0, 0 for 0.24.0.
leading() {
	sed -E 's/^[^0-9]*([0-9]+).*/\1/' <<<"$1"
}

required=$(gh api "repos/$GH_REPO/rules/branches/$BASE" \
	--jq '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]')

if [ -n "$PRS" ]; then
	candidates=$(for n in $PRS; do gh api "repos/$GH_REPO/pulls/$n"; done | jq -s '.')
else
	candidates=$(gh api "repos/$GH_REPO/pulls?state=open&base=$BASE&per_page=100")
fi

jq -r --arg bot "$GOVERNING" '.[]
	| select(.user.login == $bot and (.draft | not) and (.head.ref | startswith("governing/bump-"))
	         and any(.labels[]; .name == "automated"))
	| "\(.number) \(.head.sha)"' <<<"$candidates" |
	while read -r number sha; do
		files=$(gh api "repos/$GH_REPO/pulls/$number/files?per_page=100" --jq '[.[].filename] | sort | join(" ")')
		if [ "$files" != "composer.json composer.lock" ]; then
			note "#$number changes $files, not just composer.json and composer.lock; leaving it for a person."
			continue
		fi

		read -r merge_base behind < <(gh api "repos/$GH_REPO/compare/$BASE...$sha" \
			--jq '"\(.merge_base_commit.sha) \(.behind_by)"')

		# The require entry it moves, from the merge base to its head.
		change=$(jq -n --slurpfile a "$(fetch composer.json "$merge_base")" --slurpfile b "$(fetch composer.json "$sha")" '
			def reqs: (.require // {}) + (."require-dev" // {});
			($a[0] | reqs) as $from | ($b[0] | reqs) as $to
			| [($from + $to | keys)[] as $k | select($from[$k] != $to[$k]) | {name: $k, from: ($from[$k] // ""), to: ($to[$k] // "")}]')
		if [ "$(jq 'length == 1 and .[0].from != "" and .[0].to != ""' <<<"$change")" != "true" ]; then
			note "#$number does not move exactly one package main already requires ($(jq -c '[.[].name]' <<<"$change")); leaving it for a person."
			continue
		fi
		name=$(jq -r '.[0].name' <<<"$change")
		from=$(jq -r '.[0].from' <<<"$change")

		# Its lock must move that package and nothing else.
		head_lock=$(fetch composer.lock "$sha")
		moved=$(jq -nc --slurpfile a "$(fetch composer.lock "$merge_base")" --slurpfile b "$head_lock" '
			def versions: [(.packages // []) + (."packages-dev" // []) | .[] | {key: .name, value: .version}] | from_entries;
			($a[0] | versions) as $from | ($b[0] | versions) as $to
			| [($from + $to | keys)[] as $k | select($from[$k] != $to[$k]) | $k]')
		if [ "$moved" != "$(jq -nc --arg n "$name" '[$n]')" ]; then
			note "#$number moves more than $name in composer.lock ($moved); leaving it for a person."
			continue
		fi
		version=$(jq -r --arg n "$name" '[(.packages // []) + (."packages-dev" // []) | .[] | select(.name == $n)][0].version' "$head_lock")

		if [ "$(leading "$from")" != "$(leading "$version")" ] && [ "$(approved "$number")" != "true" ]; then
			note "#$number takes $name from $from to $version, a major; waiting for an approving review."
			continue
		fi

		mergeable=$(gh api "repos/$GH_REPO/pulls/$number" --jq '.mergeable')
		if [ "$mergeable" = "null" ]; then
			note "#$number: GitHub has not worked out yet whether it merges; the next run looks again."
			continue
		fi

		if [ "$mergeable" = "false" ]; then
			# Ask once per head commit; Governing answers by pushing a new one.
			pushed=$(gh api "repos/$GH_REPO/commits/$sha" --jq '.commit.committer.date')
			asked=$(gh api "repos/$GH_REPO/issues/$number/comments?per_page=100" | jq --arg me "$ME" --arg since "$pushed" '
				[.[] | select(.user.login == $me and (.body | startswith("@linchpin-packagist re")) and .created_at > $since)] | length')
			if [ "$asked" != "0" ]; then
				note "#$number conflicts with \`$BASE\`; waiting for Governing to regenerate its lock."
				continue
			fi
			# Governing refuses a plain rebase once anyone else has committed to the
			# branch. Updating it from main is the only commit this ever makes there,
			# so over that it asks for recreate; over a person's commit, nothing.
			others=$(gh api "repos/$GH_REPO/pulls/$number/commits?per_page=100" | jq -r --arg me "$ME" --arg base "$BASE" '
				(.[0].author.login // "") as $governing
				| [.[] | select((.author.login // "") != $governing)
				       | if .author.login == $me and (.commit.message | startswith("Merge branch '\''\($base)'\''")) then "update" else "person" end]
				| unique | join(" ")')
			case "$others" in
			*person*)
				note "#$number conflicts with \`$BASE\`, and a person has committed to it; leaving it for them."
				continue
				;;
			update) command=recreate ;;
			*) command=rebase ;;
			esac
			write gh api "repos/$GH_REPO/issues/$number/comments" -f body="@linchpin-packagist $command" >/dev/null
			note "#$number conflicts with \`$BASE\`; asked Governing to $command it."
			continue
		fi

		if [ "$behind" -gt 0 ]; then
			if write gh api -X PUT "repos/$GH_REPO/pulls/$number/update-branch" -f expected_head_sha="$sha" >/dev/null; then
				note "#$number was $behind commits behind \`$BASE\`; updated it, so CI runs again."
			else
				note "Could not update #$number from \`$BASE\`; the next run looks again."
			fi
			continue
		fi

		v=$(verdict "$sha" "$required")
		if [ "$v" != "green" ]; then
			note "#$number: checks $v."
			continue
		fi

		# The squash commit is what release-please reads, so it is worded the way
		# Renovate words the updates it merges (COMMIT_PREFIX), and lands in the
		# same section.
		if write gh api -X PUT "repos/$GH_REPO/pulls/$number/merge" \
			-f merge_method=squash -f sha="$sha" \
			-f commit_title="$PREFIX Update dependency $name to v$version (#$number)" \
			-f commit_message="Opened by Linchpin Governing for the release; merged by linchpin/actions governing-merge once it was level with $BASE and green." >/dev/null; then
			note "Merged #$number: $name $from to $version."
		else
			note "Could not merge #$number (conflicted, or pushed since); the next run looks again."
		fi
	done
