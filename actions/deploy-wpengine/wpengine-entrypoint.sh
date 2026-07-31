#!/bin/bash

# v4 of .deployment/wpengine-entrypoint.sh. Runs ON THE WP ENGINE SERVER.
# Previously wget'd from the v3 branch at deploy time; in v4 it is uploaded by
# the deploy-wpengine composite action. The v3 wpengine-endpoint.sh
# (maintenance cleanup) is folded into the end of this script — it ran from an
# inconsistent directory in v3 and computed the wrong PUBLIC_DIR.
#
# Steps:
# 1. Unzip the uploaded release
# 2. Detect platform-managed symlinks and configured protected paths
# 3. Sync plugins, themes and mu-plugins into the public directory
# 4. Keep only the newest release zips, remove old release folders
# 5. Clear maintenance mode if active, flush caches when available

set -uo pipefail

release_folder_name=$1 # timestamp release zip name (without .zip)

# Resolved before any cd: protected-paths.txt is uploaded next to this script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Run from <site>/_wpeprivate/releases
export RELEASES_DIR=$(pwd)
export PRIVATE_DIR="$(dirname "$RELEASES_DIR")"
export PUBLIC_DIR="$(dirname "$PRIVATE_DIR")"
export RELEASE_DIR="$RELEASES_DIR/release"
export CONTENT_DIR="$PUBLIC_DIR/wp-content"

echo "Releases: $RELEASES_DIR"
echo "Release:  $RELEASE_DIR"
echo "Public:   $PUBLIC_DIR"

# ---------------------------------------------------------------------------
# Symlink + protected-path handling
#
# KEEP IN SYNC with the identical block in the sibling host entrypoints
# (deploy-pressable, deploy-cloudways). Every action ships a self-contained
# entrypoint by design — the ref you pin is the code that runs — so this block
# is duplicated rather than sourced from a shared file.
#
# Managed hosts serve some plugins from platform-owned storage and link them
# into the site: on Pressable, jetpack and woocommerce are usually symlinks in
# wp-content/plugins rather than real folders. rsyncing a release copy onto such
# a path is destructive either way — rsync follows the link and writes THROUGH
# it (so --delete prunes files the platform owns), or the link is replaced by a
# real directory and the site silently stops receiving platform updates.
#
# Rule: whatever is a symlink on the server is left exactly as it is. Projects
# can protect additional paths that are still real folders through the deploy
# action's protected-paths input (vars.PROTECTED_PATHS), which arrives as
# protected-paths.txt next to this script.
# ---------------------------------------------------------------------------

PRESERVE_SYMLINKS="${PRESERVE_SYMLINKS:-true}"
PROTECTED_PATHS_FILE="${PROTECTED_PATHS_FILE:-$SCRIPT_DIR/protected-paths.txt}"

protected_patterns=() # wp-content-relative globs a deploy must never overwrite
skip_reason=""        # set by should_skip() for the caller to log
skipped_paths=()      # everything left untouched, for the closing summary

load_protected_paths() {
	local line
	[ -f "$PROTECTED_PATHS_FILE" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		line="$(printf '%s' "${line%%#*}" | sed -e 's#^[[:space:]/]*##' -e 's#[[:space:]/]*$##')"
		[ -n "$line" ] && protected_patterns+=("$line")
	done < "$PROTECTED_PATHS_FILE"
	if [ ${#protected_patterns[@]} -gt 0 ]; then
		echo "ℹ︎ Protected paths: ${protected_patterns[*]}"
	fi
}

is_protected_path() {
	local rel="$1" pattern
	[ ${#protected_patterns[@]} -gt 0 ] || return 1
	for pattern in "${protected_patterns[@]}"; do
		# Unquoted right-hand side on purpose: entries are globs (woocommerce*).
		# shellcheck disable=SC2053
		[[ "$rel" == $pattern ]] && return 0
		# A bare name (no slash) protects that folder wherever it lives, so
		# "woocommerce" covers "plugins/woocommerce".
		# shellcheck disable=SC2053
		[[ "$pattern" != */* && "${rel##*/}" == $pattern ]] && return 0
	done
	return 1
}

# should_skip <wp-content-relative path> <destination on the server>
should_skip() {
	local rel="$1" dest="$2"
	skip_reason=""
	if [ "$PRESERVE_SYMLINKS" = "true" ] && [ -L "$dest" ]; then
		skip_reason="platform symlink → $(readlink "$dest" 2>/dev/null || echo 'unknown target')"
	elif is_protected_path "$rel"; then
		skip_reason="protected by configuration"
	else
		return 1
	fi
	skipped_paths+=("$rel — $skip_reason")
	return 0
}

# An undeclared symlink that the release also ships is the surprising case: the
# project built that plugin expecting it to land, so say so loudly.
report_skip() {
	local rel="$1" shipped="$2"
	if [ ! -e "$shipped" ]; then
		echo "::notice::⤵︎ $rel left untouched — $skip_reason"
	elif is_protected_path "$rel"; then
		echo "::notice::⤵︎ $rel ships in this release but was not deployed — $skip_reason"
	else
		echo "::warning::⤵︎ $rel ships in this release but was NOT deployed — $skip_reason. Add it to PROTECTED_PATHS to make this explicit."
	fi
}

# Print what the host manages, so the log explains itself and the paths worth
# adding to PROTECTED_PATHS are easy to copy out.
report_symlinks() {
	local content_dir="$1" links link
	[ -d "$content_dir" ] || return 0
	links="$(find "$content_dir" -maxdepth 2 -type l 2>/dev/null | sort)"
	if [ -z "$links" ]; then
		echo "ℹ︎ No symlinks detected under $content_dir"
		return 0
	fi
	echo "ℹ︎ Symlinks detected under $content_dir (this deploy will not overwrite them):"
	while IFS= read -r link; do
		[ -n "$link" ] || continue
		echo "  • ${link#"$content_dir"/} → $(readlink "$link" 2>/dev/null || echo 'unknown target')"
	done <<< "$links"
}

# sync_children <kind> <label> <source root> <destination root>
# One rsync per child directory (plugins/, themes/), so a child that is
# symlinked or protected can be skipped whole — neither the link nor whatever
# it points at is touched.
sync_children() {
	local kind="$1" label="$2" src_root="$3" dest_root="$4"
	local dir base rel dest
	if [ -L "$dest_root" ]; then
		echo "ℹ︎ $dest_root is itself a symlink → $(readlink "$dest_root") — syncing through it"
	fi
	for dir in "$src_root"/*/; do
		[ -d "$dir" ] || continue
		base="$(basename "$dir")"
		rel="$kind/$base"
		dest="$dest_root/$base"
		if should_skip "$rel" "$dest"; then
			report_skip "$rel" "$dir"
			continue
		fi
		echo "Syncing $label: $base"
		rsync "${RSYNC_OPTS[@]}" "$dir" "$dest"
	done
}

# sync_tree <kind> <source root> <destination root>
# One rsync for the whole directory, used where --delete is meant to prune
# entries the project removed. Protection becomes an --exclude rule: rsync
# neither overwrites nor deletes an excluded path.
sync_tree() {
	local kind="$1" src_root="$2" dest_root="$3"
	local excludes=() entry base
	if [ -L "$dest_root" ]; then
		echo "ℹ︎ $dest_root is itself a symlink → $(readlink "$dest_root") — syncing through it"
	fi
	for entry in "$dest_root"/*; do
		# -L as well as -e: a broken symlink still has to be preserved.
		[ -e "$entry" ] || [ -L "$entry" ] || continue
		base="$(basename "$entry")"
		if should_skip "$kind/$base" "$entry"; then
			report_skip "$kind/$base" "$src_root/$base"
			excludes+=("--exclude=/$base")
		fi
	done
	rsync "${RSYNC_OPTS[@]}" ${excludes[@]+"${excludes[@]}"} "$src_root/." "$dest_root"
}

report_skipped_summary() {
	local path
	[ ${#skipped_paths[@]} -gt 0 ] || return 0
	echo "::notice::ℹ︎ ${#skipped_paths[@]} path(s) left untouched on the server:"
	for path in "${skipped_paths[@]}"; do
		echo "  • $path"
	done
}

# --- end of shared block ---------------------------------------------------

# Every release starts from a clean extraction directory
if [ -d "$RELEASE_DIR" ]; then
    rm -rf "$RELEASE_DIR"
fi

if [ ! -f "$RELEASES_DIR/$release_folder_name.zip" ]; then
	echo "::error::❌ Release zip not found at $RELEASES_DIR/$release_folder_name.zip"
	exit 1
fi

echo "::notice::ℹ︎ Release zip found at $RELEASES_DIR/$release_folder_name.zip"
chmod a+r "$RELEASES_DIR/$release_folder_name.zip"
chmod g+wx "$RELEASES_DIR"
unzip -o -q -d "$RELEASE_DIR" "$RELEASES_DIR/$release_folder_name.zip"

load_protected_paths
report_symlinks "$CONTENT_DIR"

RSYNC_OPTS=(-arxW --inplace --delete)

# Sync Plugins
if [[ -d "${RELEASE_DIR}/plugins/" ]]; then
	sync_children "plugins" "Plugin" "$RELEASE_DIR/plugins" "$CONTENT_DIR/plugins"
fi

# Sync Themes
if [[ -d "${RELEASE_DIR}/themes/" ]]; then
	sync_children "themes" "Theme" "$RELEASE_DIR/themes" "$CONTENT_DIR/themes"
fi

# Sync MU Plugins when present.
# v4 change: no .distignore filtering here — the release was already cleaned
# by the build-release action before it was zipped. mu-plugins is synced as one
# tree (its files sit at the root rather than one folder per plugin), so
# platform-managed entries are protected with --exclude instead of being skipped
# — without that, --delete would remove the host's own mu-plugins.
if [[ -d "${RELEASE_DIR}/mu-plugins/" ]]; then
	sync_tree "mu-plugins" "$RELEASE_DIR/mu-plugins" "$CONTENT_DIR/mu-plugins"
fi

# Final cleanup within the releases directory: keep only the two newest zips
cd "$RELEASES_DIR"

zipcount=$(ls -t ./*.zip 2>/dev/null | wc -l)
if [[ "$zipcount" -gt 2 ]]; then
  echo "ℹ︎ Removing all but the two newest release zips"
  ls -t ./*.zip | awk 'NR>2' | xargs rm -f
fi

# Remove stale database export archives from older deploy flows
if compgen -G "./*.gz" > /dev/null; then
  echo "ℹ︎ Removing old .gz archives"
  rm -f ./*.gz
fi

# Remove any stale extracted release folders other than the current one
subdircount=$(find ./ -maxdepth 1 -type d | wc -l)
if [[ "$subdircount" -gt 1 ]]; then
  find . -maxdepth 1 -type d ! -name "release" ! -name . -exec rm -r {} \;
fi

cd "$PUBLIC_DIR"

# Maintenance cleanup (previously wpengine-endpoint.sh, with the
# $FILE/$MAINTENANCE_FILE shell bugs fixed)
if [[ -e "./maintenance.php" ]]; then
  rm -f "./maintenance.php"
fi

if wp maintenance-mode is-active 2>/dev/null; then
  wp maintenance-mode deactivate
  echo "::notice::ℹ︎ Maintenance Mode Removed"
fi

# Flush caches when the commands exist
if wp cli has-command page-cache 2>/dev/null; then
    wp page-cache flush
fi

report_skipped_summary

echo "::notice::ℹ︎ Release sync complete"
