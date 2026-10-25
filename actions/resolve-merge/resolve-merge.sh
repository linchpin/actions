#!/usr/bin/env bash
#
# Bring one branch into the checked-out branch and resolve the conflicts that
# dependency updates leave, the way a person would, so the merge does not wait
# a day for one.
#
# GitHub's merge API refuses when both sides changed the same lines. Between a
# rolling `maintenance` branch and main that is nearly always the manifests and
# lockfiles: Renovate bumps one set of packages on each side, the entries sit
# next to each other, and git calls neighbouring lines a conflict even when no
# package moved on both sides. linchpin.com's #1890 (October 2026) was exactly
# that, in two package.json files and eight package-lock.json files, and it
# stopped every nightly run for days.
#
# Each conflicted file is resolved by what it is, and nothing cleverer:
#
#   package.json, composer.json
#       Three-way merge by key: each value comes from the side that changed it.
#       When both sides raised the same thing, the higher one wins: the
#       top-level "version", which release-please owns, or a dependency's range
#       (Renovate sends a major to main and a minor of the same package to
#       `maintenance`, and the major supersedes it). Any other key both sides
#       changed to different values gives up.
#   package-lock.json
#       Three-way merge by package entry, the same way, then
#       `npm install --package-lock-only` repairs the tree against the merged
#       package.json and `npm ls` checks it. An entry both sides moved takes the
#       higher version and npm checks it. It gives up when npm moved a package
#       that was already in the tree, neither side moved, and the merged
#       package.json does not name: npm's own conflict handling re-resolves
#       freely, and on #1890 it floated 74 untouched packages, one a major.
#   composer.lock
#       Keep this side's lock and re-apply each package the other side moved, at
#       exactly the version it locked (`composer update <name> --with
#       <name>:<version>`), then check nothing else moved. A package both sides
#       moved, or a dev branch, gives up.
#
# Any other conflicted file is left to Sisyphus or a person (LINCHPIN-5903).
# The two are handed over on branches named for the exact pair of commits, so
# an answer for an older pair never applies:
#
#   sisyphus/conflicts/<this side's commit>-<the other side's commit>
#       With PUBLISH_CONFLICTS=true, giving up pushes the conflicted files here,
#       with diff3 markers (each hunk carries its base) and
#       .sisyphus/conflicts.json naming the two commits and the files.
#   sisyphus/resolutions/<the same pair>
#       Sisyphus writes its answer for each file here, with
#       .sisyphus/resolutions.json saying which model resolved what. When it
#       exists for this pair, each conflicted file takes its answer, which must
#       carry no conflict markers and pass `php -l` or a JSON parse, and the
#       merge commit names every file resolved this way for review.
#
# A merge that succeeds deletes both branches. Giving up pushes nothing else.
#
# npm and Composer run with scripts and plugins off: the job holds a write
# token, and nothing from either branch should execute in it.
#
# Run it from a checkout of the branch with full history and the other side
# fetched:
#
#   MERGE_FROM=origin/main DRY_RUN=true bash resolve-merge.sh
#
# resolves in the checkout and pushes nothing; the merge commit is left for you
# to inspect (git reset --hard ORIG_HEAD drops it).
#
# Env: MERGE_FROM (the ref to bring in, required), MERGE_BRANCH (where to push,
# default the checked-out branch), DRY_RUN, PUBLISH_CONFLICTS, COMPOSER_AUTH,
# NPM_TOKEN (read token for private npm packages), GITHUB_STEP_SUMMARY and
# GITHUB_OUTPUT. Outputs: resolved (true or false), sha, reason, unresolved
# (space-separated), conflicts_branch (when it published one). Exits 1 when it
# gives up.

set -euo pipefail

: "${MERGE_FROM:?Set MERGE_FROM to the ref to bring in, such as origin/main}"
BRANCH=${MERGE_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}
FROM=${MERGE_FROM#origin/}
DRY_RUN=${DRY_RUN:-false}
PUBLISH_CONFLICTS=${PUBLISH_CONFLICTS:-false}
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
OUTPUT=${GITHUB_OUTPUT:-/dev/null}

note() {
	echo "$*" >&2
	echo "- $*" >>"$SUMMARY"
}

output() {
	echo "$1=$2" >>"$OUTPUT"
}

give_up() {
	note "Not resolved: $1"
	output resolved false
	output reason "$1"
	output unresolved "${2:-}"
	git merge --abort >/dev/null 2>&1 || true
	exit 1
}

# A file as a ref has it, or null when that side has no such file.
show() {
	git show "$1:$2" 2>/dev/null || echo null
}

# A file's path inside a directory, with "." meaning the top.
at() {
	if [ "$1" = "." ]; then echo "$2"; else echo "$1/$2"; fi
}

# jq's indent flags for a file, matching how this side wrote it, in INDENT.
indent_for() {
	local line spaces
	line=$(git show "HEAD:$1" 2>/dev/null | sed -n 2p)
	spaces=${line%%[! ]*}
	if [ "${line:0:1}" = $'\t' ]; then
		INDENT=(--tab)
	elif [ -n "$spaces" ]; then
		INDENT=(--indent "${#spaces}")
	else
		INDENT=(--indent 2)
	fi
}

# Higher of two versions, comparing their numeric parts.
JQ_VERSION='def vkey: tostring | sub("^[^0-9]*"; "") | split("-")[0] | split(".") | map(tonumber? // 0);'

if [ -n "${NPM_TOKEN:-}" ]; then
	NPM_CONFIG_USERCONFIG=$(mktemp)
	export NPM_CONFIG_USERCONFIG
	echo "//registry.npmjs.org/:_authToken=$NPM_TOKEN" >"$NPM_CONFIG_USERCONFIG"
fi

git rev-parse -q --verify "$MERGE_FROM^{commit}" >/dev/null || git fetch -q origin "$FROM"
BASE=$(git merge-base HEAD "$MERGE_FROM") || give_up "\`$BRANCH\` and \`$FROM\` share no history."
INTO_SHA=$(git rev-parse HEAD)
FROM_SHA=$(git rev-parse "$MERGE_FROM^{commit}")
PAIR="${INTO_SHA:0:12}-${FROM_SHA:0:12}"
CONFLICTS_BRANCH="sisyphus/conflicts/$PAIR"
RESOLUTIONS_BRANCH="sisyphus/resolutions/$PAIR"

# Push the conflicted files, markers and all, for Sisyphus to answer. A
# separate index builds the commit, so the merge in progress is left alone.
publish_conflicts() {
	local index file mode blob tree commit manifest

	if [ "$PUBLISH_CONFLICTS" != "true" ]; then
		return 0
	fi

	if [ "$DRY_RUN" = "true" ]; then
		note "Dry run, would publish ${#others[@]} conflicted file(s) to \`$CONFLICTS_BRANCH\`."
		return 0
	fi

	index=$(mktemp)
	GIT_INDEX_FILE=$index git read-tree "$INTO_SHA"

	for file in "${others[@]}"; do
		mode=$(git ls-files -s -- "$file" | awk '$3 == 2 { print $1; exit }')
		blob=$(git hash-object -w -- "$file")
		GIT_INDEX_FILE=$index git update-index --add --cacheinfo "${mode:-100644},$blob,$file"
	done

	manifest=$(jq -n --arg into "$INTO_SHA" --arg from "$FROM_SHA" --arg branch "$BRANCH" --arg source "$FROM" \
		'{into: $into, from: $from, branch: $branch, source: $source, files: $ARGS.positional}' --args "${others[@]}")
	blob=$(git hash-object -w --stdin <<<"$manifest")
	GIT_INDEX_FILE=$index git update-index --add --cacheinfo "100644,$blob,.sisyphus/conflicts.json"

	tree=$(GIT_INDEX_FILE=$index git write-tree)
	commit=$(git commit-tree "$tree" -p "$INTO_SHA" -m "Conflicts bringing $FROM into $BRANCH, for Sisyphus to resolve")
	rm -f "$index"

	if git push -q -f origin "$commit:refs/heads/$CONFLICTS_BRANCH"; then
		output conflicts_branch "$CONFLICTS_BRANCH"
		note "Published the conflicts to \`$CONFLICTS_BRANCH\` for Sisyphus."
	else
		note "Could not publish the conflicts to \`$CONFLICTS_BRANCH\`."
	fi
}

conflicted=()
if ! git -c merge.conflictStyle=diff3 merge --no-ff --no-commit "$MERGE_FROM" >/dev/null 2>&1; then
	git rev-parse -q --verify MERGE_HEAD >/dev/null || give_up "git could not start the merge."
	while IFS= read -r file; do
		conflicted+=("$file")
	done < <(git diff --name-only --diff-filter=U)
fi
# Otherwise GitHub refused but git merges it, and there is nothing to resolve.

manifests=()
npm_locks=()
composer_locks=()
others=()
for file in ${conflicted[@]+"${conflicted[@]}"}; do
	case "${file##*/}" in
	package.json | composer.json) manifests+=("$file") ;;
	package-lock.json) npm_locks+=("$file") ;;
	composer.lock) composer_locks+=("$file") ;;
	*) others+=("$file") ;;
	esac
done

done_lines=()
answered=""

# 0. Anything else takes Sisyphus's answer for this pair of commits, or waits
#    for one.
if [ "${#others[@]}" -gt 0 ]; then
	if ! git fetch -q origin "+refs/heads/$RESOLUTIONS_BRANCH:refs/sisyphus/resolutions" 2>/dev/null; then
		publish_conflicts
		give_up "more than manifests and lockfiles conflict: ${others[*]}" "${others[*]}"
	fi

	answers=$(git show refs/sisyphus/resolutions:.sisyphus/resolutions.json 2>/dev/null) ||
		give_up "\`$RESOLUTIONS_BRANCH\` has no .sisyphus/resolutions.json." "${others[*]}"
	if [ "$(jq -r '"\(.into) \(.from)"' <<<"$answers")" != "$INTO_SHA $FROM_SHA" ]; then
		give_up "\`$RESOLUTIONS_BRANCH\` answers another pair of commits." "${others[*]}"
	fi

	for file in "${others[@]}"; do
		git show "refs/sisyphus/resolutions:$file" >"$file" 2>/dev/null ||
			give_up "\`$RESOLUTIONS_BRANCH\` has no answer for $file." "$file"

		# ======= alone is ordinary text (a Markdown underline); the other three are not.
		if grep -qE '^(<<<<<<<|\|\|\|\|\|\|\||>>>>>>>)( |$)' "$file"; then
			give_up "the answer for $file still has conflict markers." "$file"
		fi

		case "$file" in
		*.php)
			php -l "$file" >/dev/null 2>&1 ||
				give_up "the answer for $file is not valid PHP: $(php -l "$file" 2>&1 | grep -m 1 -iE 'error' || true)" "$file"
			;;
		*.json)
			jq empty "$file" 2>/dev/null || give_up "the answer for $file is not valid JSON." "$file"
			;;
		esac

		git add -- "$file"
		by=$(jq -r --arg file "$file" '.files[$file].by // "a model"' <<<"$answers")
		done_lines+=("$file: resolved by Sisyphus with $by. Review it.")
		answered="$answered $file"
	done
fi

# 1. Manifests, so the lockfiles below resolve against the merged one.
for file in ${manifests[@]+"${manifests[@]}"}; do
	indent_for "$file"
	result=$(jq -n \
		--slurpfile b <(show "$BASE" "$file") \
		--slurpfile o <(show HEAD "$file") \
		--slurpfile t <(show "$MERGE_FROM" "$file") "$JQ_VERSION"'
		($b[0] // {}) as $B | ($o[0] // {}) as $O | ($t[0] // {}) as $T
		| ([$B, $O, $T] | map([paths(scalars)]) | add | unique) as $ps
		| [$ps[] | . as $p | {p: $p, b: ($B | getpath($p)), o: ($O | getpath($p)), t: ($T | getpath($p))}
			| select(.o != .b and .t != .b and .o != .t)] as $both
		# Both raised the same thing: the release version, or a dependency.
		| def raised: (.p == ["version"]) or (
			(.p | length) == 2
			and (.p[0] | IN("dependencies", "devDependencies", "optionalDependencies", "peerDependencies", "overrides", "require", "require-dev"))
			and (.o | type) == "string" and (.t | type) == "string");
		  [$both[] | select(raised | not) | .p | map(tostring) | join(".")] as $refused
		| if ($refused | length) > 0 then {refused: $refused}
		  else
			reduce ($ps[] | . as $p | select(($O | getpath($p)) != ($B | getpath($p)))) as $p ($T;
				($O | getpath($p)) as $v
				| if $v == null then delpaths([$p]) else setpath($p; $v) end)
			| reduce ($both[] | select(raised)) as $x (.; setpath($x.p; [$x.o, $x.t] | max_by(vkey)))
			# Keep dependency lists sorted when the other side kept them sorted.
			| reduce ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies", "require", "require-dev") as $k (.;
				if (.[$k] | type) == "object" and ($T[$k] | type) == "object" and ($T[$k] | keys_unsorted) == ($T[$k] | keys)
				then .[$k] |= (to_entries | sort_by(.key) | from_entries) else . end)
			| {merged: .}
		  end') || give_up "$file is not valid JSON on one side." "$file"

	if jq -e 'has("refused")' <<<"$result" >/dev/null; then
		give_up "$file: both sides changed $(jq -r '.refused | join(", ")' <<<"$result")." "$file"
	fi

	jq "${INDENT[@]}" '.merged' <<<"$result" >"$file"
	git add "$file"
	done_lines+=("$file: merged by key, each value from the side that changed it.")
done

# 2. npm lockfiles: merge the entries, then let npm repair and check the tree.
npm_dirs=()
for file in ${npm_locks[@]+"${npm_locks[@]}"}; do
	npm_dirs+=("$(dirname "$file")")
	jq -e '.packages' <<<"$(show HEAD "$file")" >/dev/null ||
		give_up "$file is lockfileVersion 1, which has no package entries to merge." "$file"

	indent_for "$file"
	jq "${INDENT[@]}" -n \
		--slurpfile b <(show "$BASE" "$file") \
		--slurpfile o <(show HEAD "$file") \
		--slurpfile t <(show "$MERGE_FROM" "$file") "$JQ_VERSION"'
		($b[0].packages // {}) as $B | ($o[0].packages // {}) as $O | ($t[0].packages // {}) as $T
		| ($t[0] // $o[0]) | .packages = (reduce ($B + $O + $T | keys[]) as $k ({};
			(if $O[$k] == $B[$k] then $T[$k]
			 elif $T[$k] == $B[$k] then $O[$k]
			 elif $O[$k] == $T[$k] then $O[$k]
			 elif $k == "" then $T[$k]
			 else [$O[$k], $T[$k]] | map(select(. != null)) | max_by(.version | vkey) end) as $entry
			| if $entry == null then . else .[$k] = $entry end))' >"$file.merged"
	mv "$file.merged" "$file"
done

# A package.json that conflicted while its lock merged cleanly still needs the
# lock repaired against it.
for file in ${manifests[@]+"${manifests[@]}"}; do
	dir=$(dirname "$file")
	if [ "${file##*/}" = package.json ] && [ -f "$(at "$dir" package-lock.json)" ]; then
		npm_dirs+=("$dir")
	fi
done

for dir in $(printf '%s\n' ${npm_dirs[@]+"${npm_dirs[@]}"} | sort -u); do
	lock=$(at "$dir" package-lock.json)
	log=$(mktemp)
	(cd "$dir" && npm install --package-lock-only --ignore-scripts --no-audit --no-fund --loglevel=error) >"$log" 2>&1 ||
		give_up "npm could not repair $lock: $(grep -m 3 -E 'ERR|error' "$log" | tr '\n' ' ')" "$lock"
	(cd "$dir" && npm ls --package-lock-only --all) >"$log" 2>&1 ||
		give_up "npm ls finds $lock's tree broken: $(grep -m 3 -E 'invalid|missing|ERR' "$log" | tr '\n' ' ')" "$lock"

	# Each existing package at the version a side moved it to, or left it at.
	drift=$(jq -nr \
		--slurpfile b <(show "$BASE" "$lock") \
		--slurpfile o <(show HEAD "$lock") \
		--slurpfile t <(show "$MERGE_FROM" "$lock") \
		--slurpfile r "$lock" \
		--slurpfile m "$(at "$dir" package.json)" '
		def v: (.packages // {}) | with_entries(.value = .value.version);
		($b[0] | v) as $B | ($o[0] | v) as $O | ($t[0] | v) as $T | ($r[0] | v) as $R
		| ([$m[0] | .dependencies, .devDependencies, .optionalDependencies, .peerDependencies | objects | keys[]]) as $named
		| ($R | keys[]) as $k
		| select($k != "" and ($named | index($k | ltrimstr("node_modules/"))) == null)
		| (if $O[$k] == $B[$k] then $T[$k] elif $T[$k] == $B[$k] then $O[$k] elif $O[$k] == $T[$k] then $O[$k] else "both" end) as $expected
		| select($expected != null and $expected != "both" and $R[$k] != $expected)
		| "\($k | ltrimstr("node_modules/")) \($expected) became \($R[$k])"' | head -5)
	if [ -n "$drift" ]; then
		give_up "npm moved packages neither side moved in $lock: $(tr '\n' ',' <<<"$drift" | sed 's/,$//; s/,/, /g')." "$lock"
	fi

	git add "$lock"
	done_lines+=("$lock: merged by package and repaired with npm; nothing else moved.")
done

# 3. composer.lock: keep this side's lock and re-apply what the other side moved.
composer_dirs=()
for file in ${composer_locks[@]+"${composer_locks[@]}"}; do
	composer_dirs+=("$(dirname "$file")")
done
for file in ${manifests[@]+"${manifests[@]}"}; do
	dir=$(dirname "$file")
	if [ "${file##*/}" = composer.json ] && [ -f "$(at "$dir" composer.lock)" ]; then
		composer_dirs+=("$dir")
	fi
done

# Every locked package, production and dev, as {name: version}, from a lock on stdin.
versions() {
	jq -c '[(.packages // []) + (."packages-dev" // []) | .[] | {key: .name, value: .version}] | from_entries'
}

for dir in $(printf '%s\n' ${composer_dirs[@]+"${composer_dirs[@]}"} | sort -u); do
	lock=$(at "$dir" composer.lock)
	ours=$(show HEAD "$lock" | versions)
	theirs=$(show "$MERGE_FROM" "$lock" | versions)
	base=$(show "$BASE" "$lock" | versions)

	# One line per package the other side moved, saying what to do with it here.
	plan=$(jq -nr --argjson base "$base" --argjson theirs "$theirs" --argjson ours "$ours" '
		($base + $theirs | keys)[] as $name
		| select($base[$name] != $theirs[$name])
		| if $ours[$name] == $theirs[$name] then empty
		  elif $ours[$name] != $base[$name] then "differ \($name) \($ours[$name] // "absent") \($theirs[$name] // "absent")"
		  elif $theirs[$name] == null then "remove \($name)"
		  elif ($theirs[$name] | startswith("dev-")) then "dev \($name) \($theirs[$name])"
		  else "apply \($name) \($theirs[$name])" end')

	names=()
	with=()
	applied=""
	while read -r action name version extra; do
		case "$action" in
		"") ;;
		differ) give_up "$lock: $name moved on both sides, $version in \`$BRANCH\` and $extra on \`$FROM\`." "$lock" ;;
		dev) give_up "$lock: $name is a dev branch ($version) on \`$FROM\`; its lock entry is not a version to re-apply." "$lock" ;;
		remove) names+=("$name") ;;
		apply)
			names+=("$name")
			with+=(--with "$name:$version")
			applied="$applied $name $version,"
			;;
		esac
	done <<<"$plan"

	git checkout --ours -- "$lock" 2>/dev/null || git checkout HEAD -- "$lock"

	# With no package to move, the other side changed composer.json alone, and
	# the lock needs only its content-hash refreshed.
	if [ "${#names[@]}" -eq 0 ]; then
		names=(--lock)
	fi
	composer update "${names[@]}" ${with[@]+"${with[@]}"} --working-dir="$dir" \
		--no-install --no-scripts --no-plugins --no-audit --no-interaction --no-ansi --no-progress >&2 ||
		give_up "composer could not apply what \`$FROM\` moved in $lock." "$lock"

	# This side's lock with the other side's packages applied, and nothing else moved.
	resolved=$(versions <"$lock")
	expected=$(jq -nc --argjson ours "$ours" --argjson theirs "$theirs" --argjson base "$base" '
		reduce (($base + $theirs | keys)[] | select($base[.] != $theirs[.])) as $name ($ours;
			if $theirs[$name] == null then del(.[$name]) else .[$name] = $theirs[$name] end)')
	if [ "$resolved" != "$expected" ]; then
		give_up "$lock moved more than \`$FROM\` did: $(jq -nr --argjson r "$resolved" --argjson e "$expected" '
			($r + $e | keys)[] as $n | select($r[$n] != $e[$n]) | "\($n) \($e[$n] // "absent") became \($r[$n] // "absent")"' | tr '\n' ' ')" "$lock"
	fi

	# composer update has just written the content-hash, so this fails only if
	# the merged composer.json itself is broken.
	composer validate --working-dir="$dir" --no-check-all --no-check-publish --no-check-version --no-interaction --no-ansi >&2 ||
		give_up "$lock does not agree with its composer.json after resolving." "$lock"

	git add "$lock"
	if [ -n "$applied" ]; then
		done_lines+=("$lock: kept \`$BRANCH\`'s lock and re-applied what \`$FROM\` moved:${applied%,}.")
	else
		done_lines+=("$lock: both sides lock the same versions, so only the content-hash was refreshed.")
	fi
done

if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
	give_up "files are still conflicted: $(git diff --name-only --diff-filter=U | tr '\n' ' ')" "$(git diff --name-only --diff-filter=U | tr '\n' ' ')"
fi

message="Merge branch '$FROM' into $BRANCH"
if [ "${#done_lines[@]}" -gt 0 ]; then
	message=$(printf '%s\n\n%s\n' "$message" "Resolved by linchpin/actions resolve-merge:")
	for line in "${done_lines[@]}"; do
		message=$(printf '%s\n- %s' "$message" "$line")
	done
fi
git commit -q -m "$message"
sha=$(git rev-parse HEAD)

for line in ${done_lines[@]+"${done_lines[@]}"}; do
	note "$line"
done

if [ "$DRY_RUN" = "true" ]; then
	note "Dry run, would push the merge of \`$FROM\` into \`$BRANCH\` (${sha:0:7})."
else
	git push -q origin "HEAD:refs/heads/$BRANCH" || give_up "the push to \`$BRANCH\` was refused; it may have moved."
	note "Merged \`$FROM\` into \`$BRANCH\` (${sha:0:7})."

	# The handover is spent; gone already is fine.
	for handover in "$CONFLICTS_BRANCH" "$RESOLUTIONS_BRANCH"; do
		git push -q origin --delete "$handover" >/dev/null 2>&1 || true
	done
fi

output resolved true
output sha "$sha"
output model_resolved "${answered# }"
