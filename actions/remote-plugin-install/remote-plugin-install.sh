#!/bin/bash

# Reconcile the third-party plugins and themes in composer.lock with what is
# actually installed on the server, using short-run WP-CLI calls over SSH.
#
# Runs ON THE GITHUB RUNNER — not on the server. This is the v4 port of
# .deployment/remote-plugin-install.sh.
#
# Why not `composer install` on the server (the "SSH build" in Pressable's
# Composer Workflows doc)? Managed containers cap a single exec at ~300s, and a
# cold Composer install for a WooCommerce-scale project does not reliably fit
# inside that — it would die mid-write, with maintenance mode already on and
# wp-content half updated. Driving one short WP-CLI call per package keeps every
# exec well inside the cap, keeps Composer and private-registry credentials off
# the server entirely, and leaves dependency resolution on the runner where it is
# already cached. SSH connection reuse (ControlMaster) means the many calls still
# cost one handshake.
#
# The lock file is the source of truth: a package whose installed version does
# not match the lock is reinstalled AT THE LOCKED VERSION, so rolling back to an
# older release downgrades plugins instead of leaving them ahead. v3 compared
# with version_compare and only ever upgraded, which silently made rollbacks a
# no-op for third-party plugins.
#
# Expects (all via the environment, set by action.yml):
#   SSH_ALIAS, WP_PATH, COMPOSER_LOCK, PROTECTED_PATHS_FILE, PRESERVE_SYMLINKS,
#   PACKAGE_AUTH_HOST, PACKAGE_AUTH_USER, PACKAGE_AUTH_PASSWORD, DRY_RUN

set -uo pipefail

SSH_ALIAS="${SSH_ALIAS:-remoteinstall}"
WP_PATH="${WP_PATH:?WP_PATH is required}"
COMPOSER_LOCK="${COMPOSER_LOCK:?COMPOSER_LOCK is required}"
PROTECTED_PATHS_FILE="${PROTECTED_PATHS_FILE:-}"
PRESERVE_SYMLINKS="${PRESERVE_SYMLINKS:-true}"
PACKAGE_AUTH_HOST="${PACKAGE_AUTH_HOST:-}"
PACKAGE_AUTH_USER="${PACKAGE_AUTH_USER:-}"
PACKAGE_AUTH_PASSWORD="${PACKAGE_AUTH_PASSWORD:-}"
DRY_RUN="${DRY_RUN:-false}"

if [ ! -f "$COMPOSER_LOCK" ]; then
	echo "::error::composer.lock not found at $COMPOSER_LOCK. Remote plugin install needs the lock file in the release — check that the project .distignore does not exclude it."
	exit 1
fi

# WP_PATH is interpolated into a remote command, so constrain it rather than
# trusting whatever a repo variable holds.
if [[ ! "$WP_PATH" =~ ^[A-Za-z0-9._~/-]+$ ]]; then
	echo "::error::wp-path contains characters that are not allowed in a remote path: $WP_PATH"
	exit 1
fi

# --- protected paths (same contract as the deploy entrypoints) --------------

protected_patterns=()
if [ -n "$PROTECTED_PATHS_FILE" ] && [ -f "$PROTECTED_PATHS_FILE" ]; then
	while IFS= read -r line || [ -n "$line" ]; do
		[ -n "$line" ] && protected_patterns+=("$line")
	done < "$PROTECTED_PATHS_FILE"
fi

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

# --- version comparison ----------------------------------------------------

# Composer and WordPress spell the same release differently often enough that a
# naive string compare would reinstall half the site on every deploy: the lock
# may say "v8.0.0" where the plugin header says "8.0". Strip a leading v, drop
# build metadata, and collapse trailing zero segments so 8.0.0 == 8.0 == 8.
# Replaces v3's `php -r "version_compare(...)"` shell-out.
normalize_version() {
	local v="${1#v}"
	v="${v%%+*}"
	while [[ "$v" == *.0 ]]; do v="${v%.0}"; done
	printf '%s' "$v"
}

# --- remote state ----------------------------------------------------------

echo "➤ Reading installed plugins, themes and symlinks from the server"

# One exec for the whole snapshot. --skip-plugins/--skip-themes so a fatal in
# somebody else's plugin cannot blind the inventory.
remote_state=$(ssh -n "$SSH_ALIAS" "cd '$WP_PATH' || exit 9; \
wp plugin list --format=json --fields=name,version,status --skip-plugins --skip-themes 2>/dev/null || echo '[]'; \
echo '@@SPLIT@@'; \
wp theme list --format=json --fields=name,version,status --skip-plugins --skip-themes 2>/dev/null || echo '[]'; \
echo '@@SPLIT@@'; \
find wp-content/plugins wp-content/themes -maxdepth 1 -type l 2>/dev/null || true")
ssh_status=$?

if [ "$ssh_status" -eq 9 ]; then
	echo "::error::Could not enter $WP_PATH on the server"
	exit 1
elif [ "$ssh_status" -ne 0 ]; then
	echo "::error::Failed to read the current plugin/theme state over SSH (exit $ssh_status)"
	exit 1
fi

section() { awk -v want="$1" 'BEGIN{n=0} /^@@SPLIT@@$/{n++;next} n==want' <<<"$remote_state"; }
installed_plugins_json="$(section 0)"
installed_themes_json="$(section 1)"
server_symlinks="$(section 2)"

if ! jq -e . >/dev/null 2>&1 <<<"$installed_plugins_json"; then
	echo "::error::Could not parse 'wp plugin list' output from the server. Is WP-CLI available at $WP_PATH?"
	exit 1
fi

# wp-content-relative symlink paths, e.g. plugins/jetpack
symlinked_paths=()
while IFS= read -r link; do
	[ -n "$link" ] || continue
	symlinked_paths+=("${link#wp-content/}")
done <<<"$server_symlinks"

is_symlinked() {
	local rel="$1" p
	[ "$PRESERVE_SYMLINKS" = "true" ] || return 1
	[ ${#symlinked_paths[@]} -gt 0 ] || return 1
	for p in "${symlinked_paths[@]}"; do
		[ "$p" = "$rel" ] && return 0
	done
	return 1
}

installed_version() {
	local kind="$1" slug="$2" json
	if [ "$kind" = "plugin" ]; then json="$installed_plugins_json"; else json="$installed_themes_json"; fi
	jq -r --arg s "$slug" '(.[] | select(.name == $s) | .version) // empty' <<<"$json" | head -1
}

# --- plan ------------------------------------------------------------------

PLAN="$(mktemp)"
trap 'rm -f "$PLAN"' EXIT

skipped_protected=0
skipped_current=0
skipped_nodist=0
to_install=0
to_update=0

echo
echo "➤ Comparing composer.lock against the server"

while IFS=$'\t' read -r name type version dist_url; do
	slug="${name##*/}"
	kind="plugin"
	[ "$type" = "wordpress-theme" ] && kind="theme"
	rel="${kind}s/$slug"

	if [[ ! "$slug" =~ ^[A-Za-z0-9._-]+$ ]]; then
		echo "::warning::Skipping $name — '$slug' is not a usable directory name"
		continue
	fi

	if is_symlinked "$rel"; then
		echo "  ⤵︎ $rel — platform symlink, left alone"
		skipped_protected=$((skipped_protected + 1))
		continue
	fi

	if is_protected_path "$rel"; then
		echo "  ⤵︎ $rel — protected by configuration, left alone"
		skipped_protected=$((skipped_protected + 1))
		continue
	fi

	# A package with no dist archive (typically a dev-* VCS requirement) cannot
	# be installed by WP-CLI. build-release keeps those in the release, so they
	# arrive over rsync instead — nothing to do here.
	if [ -z "$dist_url" ] || [ "$dist_url" = "null" ]; then
		echo "  ⤵︎ $rel — no dist archive in the lock, shipped in the release instead"
		skipped_nodist=$((skipped_nodist + 1))
		continue
	fi

	current="$(installed_version "$kind" "$slug")"
	if [ -n "$current" ] && [ "$(normalize_version "$current")" = "$(normalize_version "$version")" ]; then
		skipped_current=$((skipped_current + 1))
		continue
	fi

	if [ -n "$current" ]; then
		echo "  ↻ $rel — $current → $version"
		printf 'update\t%s\t%s\t%s\t%s\n' "$kind" "$slug" "$version" "$dist_url" >> "$PLAN"
		to_update=$((to_update + 1))
	else
		echo "  + $rel — install $version"
		printf 'install\t%s\t%s\t%s\t%s\n' "$kind" "$slug" "$version" "$dist_url" >> "$PLAN"
		to_install=$((to_install + 1))
	fi
done < <(jq -r '
	.packages[]
	| select(.type == "wordpress-plugin" or .type == "wordpress-theme")
	| [.name, .type, .version, (.dist.url // "")]
	| @tsv
' "$COMPOSER_LOCK")

echo
echo "::notice::Plan: $to_install to install, $to_update to update, $skipped_current already at the locked version, $skipped_protected protected, $skipped_nodist shipped in the release"

if [ "$DRY_RUN" = "true" ]; then
	echo "::notice::dry-run: no changes made"
	exit 0
fi

if [ "$to_install" -eq 0 ] && [ "$to_update" -eq 0 ]; then
	echo "::notice::Nothing to do — the server already matches composer.lock"
	exit 0
fi

# --- execute ---------------------------------------------------------------

# Credentials for the private registry are injected into the dist URL, which is
# then handed to the remote shell over STDIN rather than on the command line, so
# it never lands in the server's process list or in a shell history.
authenticated_url() {
	local url="$1"
	if [ -n "$PACKAGE_AUTH_USER" ] && [ -n "$PACKAGE_AUTH_HOST" ] && [[ "$url" == *"$PACKAGE_AUTH_HOST"* ]]; then
		printf '%s' "${url/:\/\//://$PACKAGE_AUTH_USER:$PACKAGE_AUTH_PASSWORD@}"
	else
		printf '%s' "$url"
	fi
}

echo
echo "➤ Applying $((to_install + to_update)) change(s), one WP-CLI call per package"

# Read the plan into an array (rather than piping it into the loop) so the ssh
# calls below cannot consume the loop's stdin — the classic "ssh in a while-read
# loop swallows the rest of the input" bug. Plain read loop rather than mapfile,
# which needs bash 4.
plan_lines=()
while IFS= read -r line; do
	[ -n "$line" ] && plan_lines+=("$line")
done < "$PLAN"

failed=()

for line in "${plan_lines[@]}"; do
	IFS=$'\t' read -r action kind slug version dist_url <<<"$line"
	echo "  → $action $kind $slug@$version"
	if printf '%s\n' "$(authenticated_url "$dist_url")" \
		| ssh "$SSH_ALIAS" "cd '$WP_PATH' && IFS= read -r url && wp $kind install \"\$url\" --force 2>&1"; then
		:
	else
		echo "::warning::wp $kind install failed for $slug@$version"
		failed+=("$kind/$slug@$version")
	fi
done

# --- verify ----------------------------------------------------------------

# One extra exec re-reads the inventory and confirms the lock is now satisfied.
# This is also what catches an archive whose top-level folder does not match the
# package name — WP-CLI names the directory after the zip's root, and unlike
# Composer it has no installer-paths to correct it.
echo
echo "➤ Verifying the server now matches composer.lock"

verify_state=$(ssh -n "$SSH_ALIAS" "cd '$WP_PATH' || exit 9; \
wp plugin list --format=json --fields=name,version,status --skip-plugins --skip-themes 2>/dev/null || echo '[]'; \
echo '@@SPLIT@@'; \
wp theme list --format=json --fields=name,version,status --skip-plugins --skip-themes 2>/dev/null || echo '[]'")

verify_plugins="$(awk 'BEGIN{n=0} /^@@SPLIT@@$/{n++;next} n==0' <<<"$verify_state")"
verify_themes="$(awk 'BEGIN{n=0} /^@@SPLIT@@$/{n++;next} n==1' <<<"$verify_state")"

mismatched=()
inactive=()
for line in "${plan_lines[@]}"; do
	IFS=$'\t' read -r action kind slug version dist_url <<<"$line"
	if [ "$kind" = "plugin" ]; then json="$verify_plugins"; else json="$verify_themes"; fi
	now="$(jq -r --arg s "$slug" '(.[] | select(.name == $s) | .version) // empty' <<<"$json" | head -1)"
	status="$(jq -r --arg s "$slug" '(.[] | select(.name == $s) | .status) // empty' <<<"$json" | head -1)"
	if [ -z "$now" ]; then
		mismatched+=("$kind/$slug — expected $version, not present after install (the archive's top-level folder probably is not '$slug')")
	elif [ "$(normalize_version "$now")" != "$(normalize_version "$version")" ]; then
		mismatched+=("$kind/$slug — expected $version, server reports $now")
	elif [ "$action" = "install" ] && [ "$status" = "inactive" ]; then
		inactive+=("$kind/$slug")
	fi
done

if [ ${#inactive[@]} -gt 0 ]; then
	echo "::warning::Newly installed and NOT activated: ${inactive[*]}. This action never activates packages — activate them in wp-admin or with a post_deploy_command (wp plugin activate <slug>)."
fi

if [ ${#failed[@]} -gt 0 ] || [ ${#mismatched[@]} -gt 0 ]; then
	for item in ${failed[@]+"${failed[@]}"}; do
		echo "::error::Install failed: $item"
	done
	for item in ${mismatched[@]+"${mismatched[@]}"}; do
		echo "::error::Version mismatch after install: $item"
	done
	exit 1
fi

echo "::notice::ℹ︎ Server matches composer.lock ($to_install installed, $to_update updated)"
