#!/usr/bin/env bash
#
# Snapshots: the only way the maintenance branch reaches production or staging.
#
# A snapshot is a branch, snapshot/YYYY-MM-DD, frozen at one commit of the
# maintenance branch (MAINTENANCE_BRANCH, `maintenance`), with one PR from it into
# a target branch: the production branch, or a staging branch that promotes to
# it. It holds exactly the commit that was tested while the maintenance branch
# keeps rolling. A person approves the PR and merges it as a merge commit, so each
# update keeps its own changelog line, and production moves only when the
# release-please release is published. It is not maintenance/YYYY-MM-DD because
# Git cannot hold that beside `maintenance`. Run by
# .github/workflows/snapshots.yml in linchpin/actions, in one of two modes:
#
#   freeze  Cut a snapshot at SNAPSHOT_SHA (the head of the maintenance branch
#           when empty) and open its PR into SNAPSHOT_TARGET. The older open
#           snapshot PR into the same target is closed and its branch deleted.
#   tidy    A merged snapshot PR: delete its branch, then tag the frozen commit
#           with the branch's name. A closed one: delete its branch. One open for
#           more than SNAPSHOT_MAX_AGE_DAYS: close it and delete its branch. Only
#           snapshot/ branches are ever deleted.
#
# The frozen commit rides in the PR body (`snapshot-commit: <sha>`, which
# Sisyphus reads), so the tag marks it even after the PR is brought level with its
# target by "Update branch".
#
# Run it locally to see what it would do against the live repository:
#
#   GH_REPO=linchpin/linchpin.com DRY_RUN=true actions/snapshot/snapshot.sh freeze
#   GH_REPO=linchpin/linchpin.com DRY_RUN=true actions/snapshot/snapshot.sh tidy
#
# Env: GH_REPO (owner/name, required), GH_TOKEN (gh's own login otherwise),
# DRY_RUN (true logs every write instead of making it), GITHUB_STEP_SUMMARY,
# GITHUB_OUTPUT (freeze writes `branch` and `pr`), SNAPSHOT_TARGET (a branch other
# than the maintenance branch; the production branch), SNAPSHOT_SHA (a commit or
# ref on the maintenance branch), SNAPSHOT_MAX_AGE_DAYS (7), MAINTENANCE_BRANCH
# (maintenance) and PRODUCTION_BRANCH (the default branch).

set -euo pipefail

: "${GH_REPO:?Set GH_REPO to owner/name}"
MODE=${1:-}
DRY_RUN=${DRY_RUN:-false}
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
OUTPUT=${GITHUB_OUTPUT:-/dev/null}

SOURCE=${MAINTENANCE_BRANCH:-maintenance}
PRODUCTION=${PRODUCTION_BRANCH:-$(gh api "repos/$GH_REPO" --jq .default_branch)}
TARGET=${SNAPSHOT_TARGET:-$PRODUCTION}
SHA=${SNAPSHOT_SHA:-}
MAX_AGE_DAYS=${SNAPSHOT_MAX_AGE_DAYS:-7}
PREFIX=snapshot/
LABEL=maintenance
MARKER=snapshot-commit
OWNER=${GH_REPO%%/*}

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

ref_exists() {
	gh api "repos/$GH_REPO/git/ref/$1" >/dev/null 2>&1
}

ensure_label() {
	gh api "repos/$GH_REPO/labels/$1" >/dev/null 2>&1 ||
		write gh api "repos/$GH_REPO/labels" -f name="$1" -f color="$2" -f description="$3" >/dev/null
}

# Gone already is fine: someone may have pressed "Delete branch" on the PR.
delete_branch() {
	if ref_exists "heads/$1"; then
		write gh api -X DELETE "repos/$GH_REPO/git/refs/heads/$1" >/dev/null
		note "Deleted \`$1\`."
	fi
}

# The commit a snapshot PR froze, read from its body; its head if the marker is gone.
frozen_sha() {
	jq -r --arg marker "$MARKER" '.head.sha as $head
		| ((.body // "") | capture($marker + ": (?<sha>[0-9a-f]{40})") | .sha) // $head' <<<"$1"
}

# Tag the frozen commit with the snapshot's name. The branch must be gone first:
# a tag beside a branch of the same name makes the name ambiguous.
tag_snapshot() {
	if ! ref_exists "tags/$1"; then
		write gh api "repos/$GH_REPO/git/refs" -f ref="refs/tags/$1" -f sha="$2" >/dev/null
		note "Tagged \`$1\` at $2 (#$3 merged)."
	fi
}

freeze() {
	if [ "$TARGET" = "$SOURCE" ] || ! ref_exists "heads/$TARGET"; then
		note "SNAPSHOT_TARGET must be a branch other than \`$SOURCE\`; \`$TARGET\` is not."
		exit 1
	fi

	local sha
	sha=$(gh api "repos/$GH_REPO/commits/${SHA:-$SOURCE}" --jq .sha)

	# Only a commit of the maintenance branch can be promoted.
	case "$(gh api "repos/$GH_REPO/compare/$sha...$SOURCE" --jq .status)" in
	ahead | identical) ;;
	*)
		note "\`${SHA:-$SOURCE}\` ($sha) is not on \`$SOURCE\`; nothing frozen."
		exit 1
		;;
	esac

	# The updates the target does not have yet, without the merges from production.
	local commits
	commits=$(gh api "repos/$GH_REPO/compare/$TARGET...$sha" \
		--jq '[.commits[] | select((.parents | length) == 1) | "- " + (.commit.message | split("\n")[0])] | join("\n")')
	if [ -z "$commits" ]; then
		note "\`$TARGET\` already has everything in $sha; nothing to promote."
		exit 0
	fi

	# A second snapshot the same day takes -2, -3: neither a branch nor a tag may
	# already hold the name.
	local day name n=1
	day=$(date -u +%F)
	name="$PREFIX$day"
	while ref_exists "heads/$name" || ref_exists "tags/$name"; do
		n=$((n + 1))
		name="$PREFIX$day-$n"
	done

	local older
	older=$(gh api "repos/$GH_REPO/pulls?state=open&base=$TARGET&per_page=100" \
		--jq '.[] | select(.head.ref | startswith("snapshot/")) | "\(.number) \(.head.ref)"')

	if [ "$DRY_RUN" = "true" ]; then
		note "Dry run, would freeze \`$name\` at $sha and open its PR into \`$TARGET\` with $(grep -c . <<<"$commits") updates:"
		echo "$commits" >&2
		if [ -n "$older" ]; then
			note "Dry run, would close the older snapshot PRs into \`$TARGET\`: $(cut -d' ' -f1 <<<"$older" | sed 's/^/#/' | tr '\n' ' ')"
		fi
		return 0
	fi

	local ships="Merging it deploys \`$TARGET\`."
	if [ "$TARGET" = "$PRODUCTION" ]; then
		ships="Production moves only when the release-please release is published."
	fi

	# Files a model resolved while production was brought in, which the merge commits
	# name (linchpin/actions resolve-merge, answered by Sisyphus): the person
	# merging reviews these first.
	local reviewed review=""
	reviewed=$(gh api "repos/$GH_REPO/compare/$TARGET...$sha" \
		--jq '[.commits[].commit.message | split("\n")[] | select(test("^- .*: resolved by Sisyphus with "))] | unique | join("\n")')
	if [ -n "$reviewed" ]; then
		review=$(printf '%s\n\n%s' \
			"> [!WARNING]
> A model resolved these conflicts when \`$PRODUCTION\` was brought into \`$SOURCE\`. Review each before you merge:" \
			"$reviewed")
		# After the substitution, which would strip it.
		review+=$'\n\n'
	fi

	local title body number
	title="chore(NO-TASK): Promote the ${name#"$PREFIX"} maintenance snapshot into $TARGET"
	body=$(printf '%s%s\n\n%s\n\n%s\n\n%s\n\n%s\n' \
		"$review" \
		"\`$name\` holds \`$SOURCE\` at $sha, frozen for \`$TARGET\`. These updates are in it and not yet in \`$TARGET\`:" \
		"$commits" \
		"Approve it and merge it as a **merge commit**, never a squash, so each update keeps its own changelog line. If \`$TARGET\` has moved, bring it level with **Update branch**; the tag still marks the frozen commit. $ships" \
		"A newer snapshot into \`$TARGET\` closes this one, and it is closed unmerged after $MAX_AGE_DAYS days." \
		"<!-- $MARKER: $sha -->
_Opened by linchpin/actions snapshot._")

	gh api "repos/$GH_REPO/git/refs" -f ref="refs/heads/$name" -f sha="$sha" >/dev/null
	ensure_label "$LABEL" FBCA04 "Dependency maintenance"
	number=$(gh api "repos/$GH_REPO/pulls" -f title="$title" -f head="$name" -f base="$TARGET" \
		-f body="$body" --jq .number)
	gh api "repos/$GH_REPO/issues/$number/labels" -f "labels[]=$LABEL" >/dev/null
	note "Froze \`$name\` at $sha and opened #$number into \`$TARGET\`."
	{
		echo "branch=$name"
		echo "pr=$number"
	} >>"$OUTPUT"

	# Superseded: the newer snapshot closes the older ones into the same target.
	local old old_ref
	while read -r old old_ref; do
		[ -n "$old" ] || continue
		gh api "repos/$GH_REPO/issues/$old/comments" -f body="Superseded by #$number." >/dev/null
		gh api -X PATCH "repos/$GH_REPO/pulls/$old" -f state=closed >/dev/null
		delete_branch "$old_ref"
		note "Closed #$old, superseded by #$number."
	done <<<"$older"
}

tidy() {
	local now max name pr number state age
	now=$(date -u +%s)
	max=$((MAX_AGE_DAYS * 86400))

	gh api "repos/$GH_REPO/git/matching-refs/heads/$PREFIX" --jq '.[].ref | sub("^refs/heads/"; "")' |
		while read -r name; do
			[ -n "$name" ] || continue
			pr=$(gh api "repos/$GH_REPO/pulls?state=all&head=$OWNER:$name&per_page=1" --jq '.[0] // empty')

			if [ -z "$pr" ]; then
				# A freeze that stopped before its PR: gone once its date is old enough.
				age=$((now - $(jq -rn --arg d "${name#"$PREFIX"}" '$d[0:10] | strptime("%Y-%m-%d") | mktime')))
				if [ "$age" -gt "$max" ]; then
					delete_branch "$name"
				fi
				continue
			fi

			number=$(jq -r .number <<<"$pr")
			state=$(jq -r .state <<<"$pr")
			if [ -n "$(jq -r '.merged_at // empty' <<<"$pr")" ]; then
				delete_branch "$name"
				tag_snapshot "$name" "$(frozen_sha "$pr")" "$number"
			elif [ "$state" = "closed" ]; then
				delete_branch "$name"
			else
				age=$((now - $(jq -r '.created_at | fromdateiso8601' <<<"$pr")))
				if [ "$age" -gt "$max" ]; then
					write gh api "repos/$GH_REPO/issues/$number/comments" \
						-f body="Closed unmerged after $MAX_AGE_DAYS days. Freeze a newer passing night when it is ready." >/dev/null
					write gh api -X PATCH "repos/$GH_REPO/pulls/$number" -f state=closed >/dev/null
					note "Closed #$number after $MAX_AGE_DAYS days."
					delete_branch "$name"
				else
					note "#$number (\`$name\`) is open, $((age / 86400)) days old."
				fi
			fi
		done

	# A merged snapshot whose branch someone deleted by hand still gets its tag.
	# One whose branch is still there was tagged above, or is a dry run's.
	gh api "repos/$GH_REPO/pulls?state=closed&per_page=100" \
		--jq '.[] | select((.head.ref | startswith("snapshot/")) and .merged_at) | tojson' |
		while read -r pr; do
			name=$(jq -r .head.ref <<<"$pr")
			if ! ref_exists "heads/$name"; then
				tag_snapshot "$name" "$(frozen_sha "$pr")" "$(jq -r .number <<<"$pr")"
			fi
		done
}

case "$MODE" in
freeze) freeze ;;
tidy) tidy ;;
*)
	echo "Usage: snapshot.sh freeze|tidy" >&2
	exit 2
	;;
esac
