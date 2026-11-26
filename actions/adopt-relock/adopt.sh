#!/usr/bin/env bash
#
# Lock each branch Sisyphus opened to adopt a plugin production runs outside
# the repository.
#
# Deploy to Dev fails `wp mantle health` with "Active but not on disk: <slug>"
# when production runs a plugin that was installed by hand: Sisyphus copies
# production's database to dev, so dev lists the plugin as active, and only
# the repository's plugins are deployed. When wp-packages.org serves the
# version production runs, Sisyphus opens the fix itself: a pull request from
# sisyphus/adopt/<slug> into the production branch whose composer.json
# requires the plugin at that version. Sisyphus has no Composer, so the lock is
# left to this step, and the pull request's Composer check fails until it
# runs.
#
# For each branch: check it out, run composer-relock's relock.sh (which
# re-locks exactly the packages Composer names, with scripts and plugins off,
# and refuses if anything else in the lock moves), commit the lock, and push.
# A branch whose lock already agrees is left alone, so a branch is locked once.
# A branch that cannot be locked gets a warning with Composer's reason, and the
# next branch is tried: a person reads it on the pull request.
#
# Env: BRANCHES (one per line), RELOCK (path to relock.sh), DRY_RUN,
# COMPOSER_AUTH, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY, and the git identity.

set -euo pipefail

: "${RELOCK:?Set RELOCK to the path of relock.sh in composer-relock}"
DRY_RUN=${DRY_RUN:-false}
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
OUTPUT=${GITHUB_OUTPUT:-/dev/null}

start=$(git rev-parse --abbrev-ref HEAD)
locked=()

while IFS= read -r branch; do
	[ -n "$branch" ] || continue

	if ! git fetch -q --depth=1 origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null; then
		echo "::warning title=Could not lock $branch::The branch could not be fetched; it may have been deleted."
		continue
	fi

	git checkout -q -B "$branch" "refs/remotes/origin/$branch"

	if ! out=$(bash "$RELOCK" . 2>relock.err); then
		reason=$(tail -n 1 relock.err)
		cat relock.err >&2
		rm -f relock.err
		echo "::warning title=Could not lock $branch::$reason The pull request's Composer check fails until composer.lock is locked by hand."
		echo "- Could not lock \`$branch\`: $reason" >>"$SUMMARY"
		continue
	fi

	cat relock.err >&2
	rm -f relock.err

	if [ -z "$(git status --porcelain -- composer.lock)" ]; then
		continue
	fi

	lines=()
	while IFS= read -r line; do
		[ -n "$line" ] && lines+=("$line")
	done <<<"$out"

	if [ "${#lines[@]}" -eq 1 ]; then
		read -r name _ new <<<"${lines[0]}"
		subject="build(composer): Lock $name at $new"
	else
		subject="build(composer): Lock composer.lock to match composer.json"
	fi
	[ "${#subject}" -le 100 ] || subject="build(composer): Lock composer.lock to match composer.json"

	for line in ${lines[@]+"${lines[@]}"}; do
		locked+=("$branch $line")
	done

	if [ "$DRY_RUN" = "true" ]; then
		echo "- Dry run, would lock \`$branch\`: ${lines[*]:-content-hash only}" >>"$SUMMARY"
		continue
	fi

	git add composer.lock
	git commit -q -m "$subject"

	if git push -q origin "HEAD:refs/heads/$branch"; then
		echo "::notice title=Locked $branch::$subject"
		echo "- Locked \`$branch\`: $subject" >>"$SUMMARY"
	else
		echo "::warning title=Could not push the lock to $branch::The push was refused; the branch may have moved. The next run tries again."
	fi
done <<<"${BRANCHES:-}"

git checkout -q "$start" 2>/dev/null || true

{
	echo "locked<<ADOPT_EOF"
	printf '%s\n' ${locked[@]+"${locked[@]}"}
	echo "ADOPT_EOF"
} >>"$OUTPUT"
