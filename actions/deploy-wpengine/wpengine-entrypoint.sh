#!/bin/bash

# v4 of .deployment/wpengine-entrypoint.sh. Runs ON THE WP ENGINE SERVER.
# Previously wget'd from the v3 branch at deploy time; in v4 it is uploaded by
# the deploy-wpengine composite action. The v3 wpengine-endpoint.sh
# (maintenance cleanup) is folded into the end of this script — it ran from an
# inconsistent directory in v3 and computed the wrong PUBLIC_DIR.
#
# Steps:
# 1. Unzip the uploaded release
# 2. Sync plugins, themes and mu-plugins into the public directory
# 3. Keep only the newest release zips, remove old release folders
# 4. Clear maintenance mode if active, flush caches when available

set -uo pipefail

release_folder_name=$1 # timestamp release zip name (without .zip)

# Run from <site>/_wpeprivate/releases
export RELEASES_DIR=$(pwd)
export PRIVATE_DIR="$(dirname "$RELEASES_DIR")"
export PUBLIC_DIR="$(dirname "$PRIVATE_DIR")"
export RELEASE_DIR="$RELEASES_DIR/release"

echo "Releases: $RELEASES_DIR"
echo "Release:  $RELEASE_DIR"
echo "Public:   $PUBLIC_DIR"

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

# Sync Plugins
if [[ -d "${RELEASE_DIR}/plugins/" ]]; then
	cd "$RELEASE_DIR/plugins"
	for dir in ./*/
	do
		base=$(basename "$dir")
		echo "Syncing Plugin: $base"
		rsync -arxW --inplace --delete "$dir" "${PUBLIC_DIR}/wp-content/plugins/$base"
	done
fi

# Sync Themes
if [[ -d "${RELEASE_DIR}/themes/" ]]; then
	cd "$RELEASE_DIR/themes"
	for dir in ./*/
	do
		base=$(basename "$dir")
		echo "Syncing Theme: $base"
		rsync -arxW --inplace --delete "$dir" "${PUBLIC_DIR}/wp-content/themes/$base"
	done
fi

# Sync MU Plugins when present.
# v4 change: no .distignore filtering here — the release was already cleaned
# by the build-release action before it was zipped.
if [[ -d "${RELEASE_DIR}/mu-plugins/" ]]; then
	rsync -arxW --inplace --delete "${RELEASE_DIR}/mu-plugins/." "${PUBLIC_DIR}/wp-content/mu-plugins"
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

echo "::notice::ℹ︎ Release sync complete"
