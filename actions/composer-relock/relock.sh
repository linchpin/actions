#!/usr/bin/env bash
#
# Re-lock the packages composer.json asks for and composer.lock does not hold,
# and nothing else, so `composer install` works again.
#
# A commit that changes composer.json without its lock breaks every build after
# it: `composer install` refuses with "Required package "linchpin/mantle" is in
# the lock file as "4.6.1" but that does not satisfy your constraint "4.6.2"".
# Renovate makes one when its artifact update fails (packagist.linchpin.com
# answered it 403 on 2026-11-18), and a repository with `ignoreTests` merges it
# anyway; a merge GitHub makes cleanly then carries it to the other branch,
# since git sees no conflict in a lock nobody touched. That night three sites
# stopped on one, at Deploy to Dev or at Update.
#
# The repair is what a person would do: `composer update` exactly the packages
# Composer names, with scripts and plugins off, then check that nothing else in
# the lock moved and that the lock now agrees with composer.json. A lock that
# lacks only a fresh content-hash gets `composer update --lock`.
#
#   bash relock.sh [directory]
#
# Prints one line per package it re-locked, "name old new" (old is "absent" for
# a package the lock did not have), and nothing when the lock already agreed or
# needed only its content-hash. Exits 1, saying why on stderr, when Composer
# cannot re-lock them or re-locking moved anything else; the lock is then put
# back as it was.
#
# Env: COMPOSER_AUTH, for private repositories such as packagist.linchpin.com.

set -euo pipefail

DIR=${1:-.}
LOCK="$DIR/composer.lock"

if [ ! -f "$DIR/composer.json" ] || [ ! -f "$LOCK" ]; then
	exit 0
fi

flags=(--working-dir="$DIR" --no-interaction --no-ansi)

# Every locked package, production and dev, as {name: version}, keys sorted.
versions() {
	jq -cS '[(.packages // []) + (."packages-dev" // []) | .[] | {key: .name, value: .version}] | from_entries' "$LOCK"
}

# Composer's own account of where the lock and composer.json disagree. The exit
# code says nothing useful here: a warning about composer.json alone is 1 too.
lock_errors() {
	composer validate "${flags[@]}" --no-check-all --no-check-publish --no-check-version 2>&1 |
		grep -E '^- (Required( \(in require-dev\))? package "|The lock file is not up to date)' || true
}

errors=$(lock_errors)
if [ -z "$errors" ]; then
	exit 0
fi

# The packages Composer names: locked at a version the constraint refuses, or
# not locked at all.
names=()
while IFS= read -r name; do
	[ -n "$name" ] && names+=("$name")
done < <(sed -nE 's/^- Required( \(in require-dev\))? package "([^"]+)".*/\2/p' <<<"$errors" | LC_ALL=C sort -u)

backup=$(mktemp)
cp "$LOCK" "$backup"
before=$(versions)

fail() {
	cp "$backup" "$LOCK"
	rm -f "$backup"
	echo "$1" >&2
	exit 1
}

if [ "${#names[@]}" -eq 0 ]; then
	update=(--lock)
else
	update=("${names[@]}")
fi

log=$(mktemp)
if ! composer update "${update[@]}" "${flags[@]}" --no-install --no-scripts --no-plugins --no-audit --no-progress >"$log" 2>&1; then
	cat "$log" >&2
	why=$(grep -m 3 -E '^ *(- |Problem|Your requirements|In [A-Za-z]+\.php|  The )' "$log" | sed -E 's/^ +//' | tr '\n' ' ' || true)
	fail "composer could not re-lock ${names[*]:-the content-hash}: ${why:-see the log above}"
fi
cat "$log" >&2

after=$(versions)
asked=$(printf '%s\n' ${names[@]+"${names[@]}"} | jq -R 'ascii_downcase' | jq -cs 'map(select(length > 0))')
moved=$(jq -nr --argjson b "$before" --argjson a "$after" --argjson asked "$asked" '
	($b + $a | keys)[] as $k
	| select($b[$k] != $a[$k] and ($asked | index($k)) == null)
	| "\($k) \($b[$k] // "absent") became \($a[$k] // "absent")"' | head -5)
if [ -n "$moved" ]; then
	fail "re-locking ${names[*]} moved packages composer.json did not ask for: $(tr '\n' ',' <<<"$moved" | sed 's/,$//; s/,/, /g')."
fi

left=$(lock_errors)
if [ -n "$left" ]; then
	fail "composer.lock still disagrees with composer.json after re-locking: $(head -n 3 <<<"$left" | sed 's/^- //' | tr '\n' ' ')"
fi

rm -f "$backup" "$log"

jq -nr --argjson b "$before" --argjson a "$after" --argjson asked "$asked" '
	$asked[] as $k | select($b[$k] != $a[$k]) | "\($k) \($b[$k] // "absent") \($a[$k] // "absent")"'
