#!/bin/bash

# Explain `wp mantle health --format=json` in the deploy log.
#
# Runs ON THE GITHUB RUNNER, from the WordPress health check step. It prints the
# checks as a table, raises an error annotation for each failing one, and for a
# plugin that is active but not on disk says where it came from and what to do,
# in the annotation and the step summary. It never decides the outcome: the step
# fails on wp mantle health's own exit status.
#
# The case it was written for (LINCHPIN-6087): MCP Adapter was installed by hand
# on ideainfanttoddler's production, outside the repo. Sisyphus copies
# production's database to dev, so dev listed it as active without its files,
# and Deploy to Dev failed with only "Active but not on disk".
#
# Expects (via the environment):
#   HEALTH_OUTPUT         what wp mantle health --format=json printed
#   SSH_ALIAS, WP_PATH    to read the site's environment type
#   PROTECTED_PATHS_FILE  the deploy's normalised protected paths
#   RELEASE_ARCHIVE or RELEASE_DIRECTORY, to find composer.lock in the release
#   REGISTRY_URL          serves WordPress.org plugins as wp-plugin/<slug>

set -uo pipefail

HEALTH_OUTPUT="${HEALTH_OUTPUT:-}"
SSH_ALIAS="${SSH_ALIAS:-pressable}"
WP_PATH="${WP_PATH:-/srv/htdocs}"
PROTECTED_PATHS_FILE="${PROTECTED_PATHS_FILE:-}"
RELEASE_ARCHIVE="${RELEASE_ARCHIVE:-}"
RELEASE_DIRECTORY="${RELEASE_DIRECTORY:-}"
REGISTRY_URL="${REGISTRY_URL:-https://wp-packages.org}"
REGISTRY_URL="${REGISTRY_URL%/}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

escape_data() {
	local s="$1"
	s="${s//%/%25}"
	s="${s//$'\r'/%0D}"
	s="${s//$'\n'/%0A}"
	printf '%s' "$s"
}

escape_property() {
	local s
	s="$(escape_data "$1")"
	s="${s//:/%3A}"
	s="${s//,/%2C}"
	printf '%s' "$s"
}

# annotate <level> <title> <line>... — one annotation, a line per argument
annotate() {
	local level="$1" title="$2" message="" line
	shift 2
	for line in "$@"; do
		message="${message:+$message%0A}$(escape_data "$line")"
	done
	echo "::$level title=$(escape_property "$title")::$message"
}

# WP-CLI or PHP can print a notice before the JSON; the report is its last line.
json="$(printf '%s\n' "$HEALTH_OUTPUT" | grep -E '^\{' | tail -1)"
if ! jq -e '.checks | type == "array"' >/dev/null 2>&1 <<<"$json"; then
	printf '%s\n' "$HEALTH_OUTPUT"
	exit 0
fi

{
	printf 'name\tstatus\tmessage\n'
	jq -r '.checks[] | [.name, .status, .message] | @tsv' <<<"$json"
} | column -t -s $'\t' 2>/dev/null || jq -r '.checks[] | "\(.name)\t\(.status)\t\(.message)"' <<<"$json"

# Every failing check but plugins gets its message as an error.
while IFS=$'\x1f' read -r name message; do
	[ -n "$name" ] || continue
	annotate error "Health check failed: $name" "$message"
done < <(jq -r '.checks[] | select(.status == "fail" and .name != "plugins") | [.name, .message] | join("\u001f")' <<<"$json")

plugins_message="$(jq -r '.checks[] | select(.name == "plugins" and .status == "fail") | .message' <<<"$json")"
[ -n "$plugins_message" ] || exit 0

# Mantle lists the plugin files in `missing` (LINCHPIN-6089); older Mantle only
# says "Active but not on disk: a/a.php, b/b.php."
jq -r '.checks[] | select(.name == "plugins") | (.missing // [])[]' <<<"$json" > "$WORK/missing.txt"
if [ ! -s "$WORK/missing.txt" ]; then
	printf '%s\n' "$plugins_message" | sed -E 's/^.*: //; s/\.$//' | tr ',' '\n' | sed -E 's/^ +//; s/ +$//' | grep -v '^$' > "$WORK/missing.txt"
fi
[ -s "$WORK/missing.txt" ] || { annotate error "Health check failed: plugins" "$plugins_message"; exit 0; }

# --- context ------------------------------------------------------------------

# A development site with Safety Net is one Sisyphus refreshes from production
# every night: its database, and so its active plugins, are production's.
context="$(ssh -n "$SSH_ALIAS" "cd '$WP_PATH' && wp eval 'echo wp_get_environment_type();' --skip-plugins --skip-themes 2>/dev/null; echo; [ -f wp-content/mu-plugins/safety-net-loader.php ] && echo synced-from-production" 2>/dev/null || true)"
environment_type="$(printf '%s\n' "$context" | head -1 | tr -d '[:space:]')"
synced=false
if printf '%s\n' "$context" | grep -qx 'synced-from-production' && [ "$environment_type" = "development" ]; then
	synced=true
fi
case "$environment_type" in
	production) env_label="Production" ;;
	staging) env_label="Staging" ;;
	development) env_label="Development" ;;
	local) env_label="Local" ;;
	*) env_label="this site" ;;
esac

protected_patterns=("plugins/jetpack" "plugins/akismet") # as the entrypoint seeds them
if [ -n "$PROTECTED_PATHS_FILE" ] && [ -f "$PROTECTED_PATHS_FILE" ]; then
	while IFS= read -r line || [ -n "$line" ]; do
		[ -n "$line" ] && protected_patterns+=("$line")
	done < "$PROTECTED_PATHS_FILE"
fi

is_protected_path() {
	local rel="$1" pattern
	for pattern in "${protected_patterns[@]}"; do
		# shellcheck disable=SC2053
		[[ "$rel" == $pattern ]] && return 0
		# shellcheck disable=SC2053
		[[ "$pattern" != */* && "${rel##*/}" == $pattern ]] && return 0
	done
	return 1
}

# The release's composer.lock, when it carries one (REMOTE_PLUGIN_INSTALL).
lock="$WORK/composer.lock"
if [ -n "$RELEASE_ARCHIVE" ] && [ -f "$RELEASE_ARCHIVE" ]; then
	unzip -p "$RELEASE_ARCHIVE" composer.lock > "$lock" 2>/dev/null || : > "$lock"
elif [ -n "$RELEASE_DIRECTORY" ] && [ -f "$RELEASE_DIRECTORY/composer.lock" ]; then
	cp "$RELEASE_DIRECTORY/composer.lock" "$lock"
else
	: > "$lock"
fi

in_lock() {
	[ -s "$lock" ] && jq -e --arg s "$1" \
		'any(.packages[]?; .type == "wordpress-plugin" and (.name | split("/") | last) == $s)' "$lock" >/dev/null 2>&1
}

# The package to require: wp-plugin/<slug> when wp-packages.org has it,
# otherwise linchpin/<slug> through packagist.linchpin.com.
require_line() {
	local slug="$1" code
	if [[ ! "$slug" =~ ^[A-Za-z0-9._-]+$ ]]; then
		printf 'add it to composer.json'
		return
	fi
	code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$REGISTRY_URL/p2/wp-plugin/$slug.json" || true)
	case "$code" in
		200) printf 'composer require wp-plugin/%s' "$slug" ;;
		404) printf 'composer require linchpin/%s (mirror it on packagist.linchpin.com first if it is not there)' "$slug" ;;
		*) printf 'add it to composer.json' ;;
	esac
}

# --- one explanation per missing plugin -------------------------------------------

summary="$WORK/summary.md"
: > "$summary"

while IFS= read -r file; do
	[ -n "$file" ] || continue
	if [[ "$file" == */* ]]; then slug="${file%%/*}"; else slug="${file%.php}"; fi

	if is_protected_path "plugins/$slug"; then
		lines=(
			"$file is active on $env_label, and the deploy leaves plugins/$slug to the host (PROTECTED_PATHS or a platform plugin), but its files aren't on the server."
			"Do one of:"
			"• Restore it on $env_label: whoever manages it there, outside the repo, needs to put it back"
			"• It isn't needed: deactivate it: wp plugin deactivate $slug"
		)
	elif in_lock "$slug"; then
		lines=(
			"$file is active on $env_label but its files aren't on the server yet. It is in this release's composer.lock, and REMOTE_PLUGIN_INSTALL installs it after this check runs."
			"Re-run the deploy once; if it fails again, check the Remote plugin install step."
		)
	elif [ "$synced" = "true" ]; then
		lines=(
			"$file is active on Development but its files aren't on the server. Development's database is copied from Production every night, so Production has $slug active, and this release doesn't include it."
			"Do one of:"
			"• The site uses it: add it to the repo: $(require_line "$slug") (at the version Production runs)"
			"• It isn't needed: deactivate it on Production"
			"PROTECTED_PATHS won't fix this: it only keeps a plugin that is already on the server, and Development doesn't have this one."
		)
	else
		lines=(
			"$file is active on $env_label but its files aren't on the server, and this release doesn't include it. Its folder was removed, or this database came from a site where it is installed."
			"Do one of:"
			"• The site uses it: add it to the repo: $(require_line "$slug")"
			"• It isn't needed: deactivate it: wp plugin deactivate $slug"
		)
	fi

	annotate error "Active but not on disk: $slug" "${lines[@]}"

	{
		echo "#### \`$slug\`"
		echo
		echo "${lines[0]}"
		for line in "${lines[@]:1}"; do
			case "$line" in
				"• "*) echo "- ${line#• }" ;;
				*) echo; echo "$line" ;;
			esac
		done
		echo
	} >> "$summary"
done < "$WORK/missing.txt"

{
	echo "### Health check failed on $env_label: active plugins missing from disk"
	echo
	cat "$summary"
} >> "$GITHUB_STEP_SUMMARY"
exit 0
