#!/bin/bash

# Report plugins that are on the server but that the repository does not manage.
#
# Runs ON THE GITHUB RUNNER, after the host deploy action (and, with
# REMOTE_PLUGIN_INSTALL, after remote-plugin-install).
#
# A plugin installed by hand on one environment never reaches the others: no
# deploy ships it. Worse, a development site that copies this environment's
# database lists it as active without its files, and Mantle's health check fails
# Deploy to Dev. ideainfanttoddler hit exactly that with MCP Adapter, installed
# by hand on production (LINCHPIN-6087). Saying so on every deploy finds such a
# plugin the day it is installed, with what to do about it.
#
# A plugin counts as managed when it is:
#   - shipped in release.zip (plugins/<slug>/ or plugins/<slug>.php);
#   - a wordpress-plugin package in the composer.lock release.zip carries, which
#     remote-plugin-install puts on the server;
#   - a symlink on the server, the host's own (Pressable's Jetpack);
#   - covered by PROTECTED_PATHS, or always managed by the host.
#
# It only reports: one warning per plugin and a step summary. It never fails a
# deploy, and anything it cannot read skips the check with a notice.
#
# Expects (via the environment, set by action.yml):
#   SSH_ALIAS, HOST, WP_PATH, RELEASE_ARCHIVE, PROTECTED_PATHS_FILE,
#   ENVIRONMENT_LABEL, REGISTRY_URL

set -uo pipefail

SSH_ALIAS="${SSH_ALIAS:-unmanagedplugins}"
HOST="${HOST:-}"
WP_PATH="${WP_PATH:-}"
RELEASE_ARCHIVE="${RELEASE_ARCHIVE:-}"
PROTECTED_PATHS_FILE="${PROTECTED_PATHS_FILE:-}"
ENVIRONMENT_LABEL="${ENVIRONMENT_LABEL:-this environment}"
REGISTRY_URL="${REGISTRY_URL:-https://wp-packages.org}"
REGISTRY_URL="${REGISTRY_URL%/}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

DOCS_URL="https://github.com/linchpin/actions/blob/main/docs/guides/host-managed-folders.md"
MAX_ANNOTATIONS=8 # GitHub shows at most 10 warnings per step

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

skip() {
	echo "::notice::Unmanaged plugin check skipped: $1"
	echo "count=" >> "$GITHUB_OUTPUT"
	echo "unmanaged=[]" >> "$GITHUB_OUTPUT"
	exit 0
}

# Workflow commands: % and newlines are escaped in the message, and : and , as
# well in a property such as the title.
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

# --- inputs ------------------------------------------------------------------

# WP_PATH is interpolated into a remote command, so constrain it rather than
# trusting whatever a repository variable holds.
if [[ ! "$WP_PATH" =~ ^[A-Za-z0-9._~/-]+$ ]]; then
	skip "wp-path is empty or has characters that are not allowed in a remote path: '$WP_PATH'"
fi

# A ~/ path must stay outside quotes on the remote side, or the shell there
# never expands it. (SC2088: the pattern matches a literal ~/ in the input.)
# shellcheck disable=SC2088
case "$WP_PATH" in
	"~/"*) remote_cd="cd ~/'${WP_PATH#\~/}'" ;;
	*) remote_cd="cd '$WP_PATH'" ;;
esac

[ -f "$RELEASE_ARCHIVE" ] || skip "release.zip not found at '$RELEASE_ARCHIVE'"

protected_patterns=()
if [ "$HOST" = "pressable" ]; then
	# deploy-pressable protects jetpack and akismet however they appear on disk.
	# Pressable also installs the Automattic for Agencies client on its sites as
	# a real folder, dev sites included (seen 2026-11-12 on itcadev, which never
	# received production's files, and on packagist.linchpin.com).
	protected_patterns+=("plugins/jetpack" "plugins/akismet" "plugins/automattic-for-agencies-client")
fi
if [ -n "$PROTECTED_PATHS_FILE" ] && [ -f "$PROTECTED_PATHS_FILE" ]; then
	while IFS= read -r line || [ -n "$line" ]; do
		[ -n "$line" ] && protected_patterns+=("$line")
	done < "$PROTECTED_PATHS_FILE"
fi

# Same contract as the deploy entrypoints.
is_protected_path() {
	local rel="$1" pattern
	[ ${#protected_patterns[@]} -gt 0 ] || return 1
	for pattern in "${protected_patterns[@]}"; do
		# Unquoted right-hand side on purpose: entries are globs (woocommerce*).
		# shellcheck disable=SC2053
		[[ "$rel" == $pattern ]] && return 0
		# shellcheck disable=SC2053
		[[ "$pattern" != */* && "${rel##*/}" == $pattern ]] && return 0
	done
	return 1
}

# --- what the repository manages ----------------------------------------------

managed="$WORK/managed.txt"
: > "$managed"

# Folders under plugins/, and single-file plugins/<slug>.php, in the release.
if ! unzip -Z1 "$RELEASE_ARCHIVE" > "$WORK/entries.txt" 2>/dev/null; then
	skip "could not list the files in '$RELEASE_ARCHIVE'"
fi
sed 's#^\./##' "$WORK/entries.txt" | awk -F/ '
	$1 == "plugins" && $2 != "" {
		slug = $2
		if (NF == 2) {
			if (slug !~ /\.php$/) next
			sub(/\.php$/, "", slug)
		}
		print slug
	}' >> "$managed"

# With REMOTE_PLUGIN_INSTALL, third-party plugins are left out of the release
# and installed from its composer.lock instead. The slug is the package name's
# last segment, as remote-plugin-install has it.
if grep -qx 'composer.lock' "$WORK/entries.txt"; then
	unzip -p "$RELEASE_ARCHIVE" composer.lock 2>/dev/null |
		jq -r '.packages[]? | select(.type == "wordpress-plugin") | .name | split("/") | last' >> "$managed" 2>/dev/null || true
fi

is_managed() {
	grep -Fxq -- "$1" "$managed"
}

# --- what is on the server ----------------------------------------------------

echo "➤ Reading the plugins on $ENVIRONMENT_LABEL"

# One exec. --skip-plugins/--skip-themes so a fatal in a plugin cannot blind
# the inventory.
remote_state=$(ssh -n "$SSH_ALIAS" "$remote_cd || exit 9; \
wp plugin list --format=json --fields=name,title,version,status --skip-plugins --skip-themes 2>/dev/null || echo '[]'; \
echo '@@SPLIT@@'; \
wp eval 'echo wp_get_environment_type();' --skip-plugins --skip-themes 2>/dev/null || true; \
echo; \
echo '@@SPLIT@@'; \
find wp-content/plugins -mindepth 1 -maxdepth 1 -type l 2>/dev/null || true")
ssh_status=$?

if [ "$ssh_status" -eq 9 ]; then
	skip "could not enter $WP_PATH on the server"
elif [ "$ssh_status" -ne 0 ]; then
	skip "could not read the server over SSH (exit $ssh_status)"
fi

section() { awk -v want="$1" 'BEGIN{n=0} /^@@SPLIT@@$/{n++;next} n==want' <<<"$remote_state"; }
plugins_json="$(section 0)"
environment_type="$(section 1 | tr -d '[:space:]')"
section 2 | sed 's#^wp-content/plugins/##' > "$WORK/symlinks.txt"

if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$plugins_json"; then
	skip "could not read 'wp plugin list' on the server. Is WP-CLI available at $WP_PATH?"
fi

is_symlinked() {
	grep -Fxq -- "$1" "$WORK/symlinks.txt" || grep -Fxq -- "$1.php" "$WORK/symlinks.txt"
}

# --- the plugins nobody manages -------------------------------------------------

checked=0
unmanaged_rows=()
# \x1f, not a tab: read collapses runs of whitespace separators, so an empty
# version would shift the title into its place.
US=$'\x1f'
while IFS="$US" read -r slug status version title; do
	[ -n "$slug" ] || continue
	checked=$((checked + 1))
	is_managed "$slug" && continue
	is_symlinked "$slug" && continue
	is_protected_path "plugins/$slug" && continue
	is_protected_path "plugins/$slug.php" && continue
	unmanaged_rows+=("$slug$US$status$US$version$US$title")
done < <(jq -r '
	.[]
	| select(.status == "active" or .status == "inactive" or .status == "active-network")
	| [.name, .status, (.version // ""), (.title // .name)]
	| map(gsub("[\u001f\n]"; " "))
	| join("\u001f")
' <<<"$plugins_json")

if [ ${#unmanaged_rows[@]} -eq 0 ]; then
	echo "✓ Every plugin on $ENVIRONMENT_LABEL ($checked) is in the repository, managed by the host, or in PROTECTED_PATHS."
	echo "count=0" >> "$GITHUB_OUTPUT"
	echo "unmanaged=[]" >> "$GITHUB_OUTPUT"
	exit 0
fi

# The package to require. wp-packages.org serves WordPress.org plugins as
# wp-plugin/<slug>; anything else comes through packagist.linchpin.com as
# linchpin/<slug>, once it is mirrored there. Sets: package, require, note.
suggest_package() {
	local slug="$1" version="$2" code
	package="" require="" note=""
	if [[ ! "$slug" =~ ^[A-Za-z0-9._-]+$ ]]; then
		return
	fi
	code=$(curl -s -o "$WORK/lookup.json" -w '%{http_code}' --max-time 10 "$REGISTRY_URL/p2/wp-plugin/$slug.json" || true)
	case "$code" in
		200)
			package="wp-plugin/$slug"
			if [ -n "$version" ] && jq -e --arg p "$package" --arg v "$version" \
				'(.packages[$p] // []) | map(.version) | index($v) != null' "$WORK/lookup.json" >/dev/null 2>&1; then
				require="$package:$version"
			else
				require="$package"
				[ -n "$version" ] && note="${version} isn't on ${REGISTRY_URL#https://}, so pin the version you want"
			fi
			;;
		404)
			package="linchpin/$slug"
			require="$package${version:+:$version}"
			note="it isn't on WordPress.org: mirror it on packagist.linchpin.com first if it isn't there"
			;;
		*)
			note="add it to composer.json (${REGISTRY_URL#https://} could not be reached to name the package)"
			;;
	esac
}

count=${#unmanaged_rows[@]}
echo "::group::$count plugin(s) on $ENVIRONMENT_LABEL that the repository doesn't manage"

json_rows="$WORK/unmanaged.jsonl"
: > "$json_rows"
summary_rows=""
shown=0

for row in "${unmanaged_rows[@]}"; do
	IFS="$US" read -r slug status version title <<<"$row"
	suggest_package "$slug" "$version"

	jq -cn --arg slug "$slug" --arg title "$title" --arg version "$version" --arg status "$status" --arg package "$package" \
		'{slug: $slug, title: $title, version: $version, status: $status, package: $package}' >> "$json_rows"

	if [ -n "$require" ]; then
		add_line="• The site uses it: add it to the repo: composer require $require${note:+ ($note)}"
		add_cell="\`composer require $require\`${note:+ ($note)}"
	else
		add_line="• The site uses it: ${note:-add it to composer.json}"
		add_cell="${note:-add it to composer.json}"
	fi

	if [ "$status" = "inactive" ]; then
		remove_line="• It isn't needed: delete it on $ENVIRONMENT_LABEL"
	else
		remove_line="• It isn't needed: deactivate and delete it on $ENVIRONMENT_LABEL"
	fi

	lines=("$title${version:+ $version} ($status) is on $ENVIRONMENT_LABEL but this repository doesn't manage it, so no other environment gets it.")
	if [ "$environment_type" = "production" ] && [ "$status" != "inactive" ]; then
		lines+=("A development site that copies this database will list it as active without its files, and its deploy health check will fail.")
	fi
	lines+=(
		"Do one of:"
		"$add_line"
		"• The host installs it on every environment (like Pressable's Jetpack): add plugins/$slug to the PROTECTED_PATHS variable"
		"$remove_line"
	)

	if [ "$shown" -lt "$MAX_ANNOTATIONS" ]; then
		annotate warning "Not in the repo: $slug" "${lines[@]}"
		shown=$((shown + 1))
	else
		printf '  %s\n' "${lines[@]}"
	fi

	safe_title="${title//|/\\|}"
	summary_rows+="| $safe_title (\`$slug\`) | ${version:-?} | $status | $add_cell |"$'\n'
done

if [ "$count" -gt "$MAX_ANNOTATIONS" ]; then
	echo "::warning title=$(escape_property "Not in the repo: $((count - MAX_ANNOTATIONS)) more")::See the step summary for the rest of the plugins the repository doesn't manage."
fi
echo "::endgroup::"

{
	echo "### Plugins on $ENVIRONMENT_LABEL that the repository doesn't manage"
	echo
	echo "| Plugin | Version | Status | Add it to the repo |"
	echo "| --- | --- | --- | --- |"
	printf '%s' "$summary_rows"
	echo
	echo "No other environment gets these plugins."
	if [ "$environment_type" = "production" ]; then
		echo "A development site that copies this database lists the active ones without their files, and its deploy health check fails."
	fi
	echo "For each, do one of:"
	echo
	echo "- **The site uses it:** add it to the repo with the command in the table."
	echo "- **The host installs it on every environment** (like Pressable's Jetpack): add \`plugins/<slug>\` to the \`PROTECTED_PATHS\` variable. See [Host-managed folders]($DOCS_URL)."
	echo "- **It isn't needed:** deactivate and delete it on $ENVIRONMENT_LABEL."
} >> "$GITHUB_STEP_SUMMARY"

echo "count=$count" >> "$GITHUB_OUTPUT"
echo "unmanaged=$(jq -cs . "$json_rows")" >> "$GITHUB_OUTPUT"
exit 0
