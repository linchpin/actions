#!/bin/bash

# v4 of .deployment/cloudways-entrypoint.sh. Runs ON THE CLOUDWAYS SERVER from
# <deployment_path>/release/.deployment. Previously wget'd from the v3 branch
# at deploy time (along with maintenance.php); in v4 both are uploaded by the
# deploy-cloudways composite action.
#
# Steps:
# 1. Enable maintenance mode (bundled maintenance.php)
# 2. Clean up legacy deployment symlinks, detect platform-managed ones
# 3. Sync plugins/themes/mu-plugins to public_html
# 4. Keep only the newest release zips, remove old release folders
# 5. Disable maintenance mode, flush redis/object caches when available

set -uo pipefail

# Resolved before any cd: protected-paths.txt is uploaded next to this script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Directory layout (derived from pwd = <releases>/release/.deployment):
export DEPLOYMENT_DIR=$(pwd)
export RELEASE_DIR="$(dirname "$DEPLOYMENT_DIR")"
export RELEASES_DIR="$(dirname "$RELEASE_DIR")"
export PRIVATE_DIR="$(dirname "$RELEASES_DIR")"
export PUBLIC_DIR="$(dirname "$PRIVATE_DIR")/public_html"
export CONTENT_DIR="$PUBLIC_DIR/wp-content"

echo "Release:  $RELEASE_DIR"
echo "Releases: $RELEASES_DIR"
echo "Public:   $PUBLIC_DIR"

# ---------------------------------------------------------------------------
# Symlink + protected-path handling
#
# KEEP IN SYNC with the identical block in the sibling host entrypoints
# (deploy-pressable, deploy-wpengine). Every action ships a self-contained
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

if [ ! -d "$PUBLIC_DIR" ]; then
  echo "::error::❌ Public directory not found at $PUBLIC_DIR"
  exit 1
fi

cd "$PUBLIC_DIR"

# Start maintenance mode (maintenance.php ships with the deploy action)
cp "$DEPLOYMENT_DIR/maintenance.php" "$PUBLIC_DIR/maintenance.php"
wp maintenance-mode activate 2>/dev/null || true

# Cleanup symlinks left by the legacy deployment process, which pointed
# wp-content/{themes,plugins,mu-plugins} at a release directory.
#
# v4 change: only links that point back into the deployment tree are removed.
# v3 removed any symlink at these paths — on a host that legitimately serves one
# of these directories from platform storage, that replaced the link with a real
# folder and silently detached the site from platform updates.
for legacy in themes plugins mu-plugins; do
  link="$CONTENT_DIR/$legacy"
  [ -L "$link" ] || continue
  target="$(readlink "$link" 2>/dev/null || echo '')"
  case "$target" in
    *private_html*|*/releases/*|*/release/*)
      echo "ℹ︎ Removing legacy deployment symlink wp-content/$legacy → $target"
      rm -rf "$link"
      ;;
    *)
      echo "::notice::ℹ︎ wp-content/$legacy is a symlink → $target — leaving it in place"
      ;;
  esac
done

load_protected_paths
report_symlinks "$CONTENT_DIR"

# Sync the release into the public folder. Cloudways syncs plugins/ and themes/
# as whole trees so that --delete prunes what the project removed; protected and
# symlinked children become --exclude rules, which rsync neither overwrites nor
# deletes.
RSYNC_OPTS=(-arxcO --delete --no-perms --no-times)
sync_tree "plugins" "${RELEASE_DIR}/plugins" "${CONTENT_DIR}/plugins"
sync_tree "themes" "${RELEASE_DIR}/themes" "${CONTENT_DIR}/themes"

# Sync MU Plugins when present.
# v4 change: no .distignore filtering here — the release was already cleaned
# by the build-release action before it was zipped.
if [ -d "${RELEASE_DIR}/mu-plugins/" ]; then
  RSYNC_OPTS=(-rxc --delete)
  sync_tree "mu-plugins" "${RELEASE_DIR}/mu-plugins" "${CONTENT_DIR}/mu-plugins"
fi

# Final cleanup: keep only the two newest release zips
cd "$RELEASES_DIR"

zipcount=$(ls -t ./*.zip 2>/dev/null | wc -l)
if [[ "$zipcount" -gt 2 ]]; then
  echo "ℹ︎ Removing all but the two newest release zips"
  ls -t ./*.zip | awk 'NR>2' | xargs rm -f
fi

subdircount=$(find ./ -maxdepth 1 -type d | wc -l)
if [[ "$subdircount" -gt 1 ]]; then
  echo "ℹ︎ Removing old release folders"
  find . -maxdepth 1 -type d ! -name "release" ! -name . -exec rm -r {} \;
fi

cd "$PUBLIC_DIR"

# End maintenance mode (fixes the v3 $FILE/$MAINTENANCE_FILE shell bugs)
if [[ -e "$PUBLIC_DIR/maintenance.php" ]]; then
  rm -f "$PUBLIC_DIR/maintenance.php"
fi

if wp maintenance-mode is-active 2>/dev/null; then
  wp maintenance-mode deactivate
  echo "::notice::ℹ︎ Maintenance Mode Removed"
fi

# Flush caches when the commands exist
if wp cli has-command redis 2>/dev/null; then
    wp redis enable --force
    wp redis flush
fi

if wp cli has-command cache 2>/dev/null; then
    wp cache flush
fi

report_skipped_summary

echo "::notice::ℹ︎ Release sync complete"
