#!/bin/bash

# v4 of .deployment/pressable-entrypoint.sh. Runs ON THE PRESSABLE SERVER.
# Previously this script was wget'd from the v3 branch by the server at deploy
# time; in v4 it is uploaded alongside the release zip by the deploy-pressable
# composite action, so the pinned action ref is the code that runs.
#
# Steps:
# 1. Unzip the uploaded release
# 2. Sync plugins, themes and mu-plugins into the public directory
# 3. Keep only the newest release zips, remove old release folders
# 4. Flush the page cache when available

set -uo pipefail

release_folder_name=$1 # timestamp release zip name (without .zip)

export RELEASES_DIR=$(pwd)
export PUBLIC_DIR="/srv/htdocs"
export RELEASE_DIR="$RELEASES_DIR/release"

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

	# On Pressable, jetpack and akismet are managed by the platform
	rm -rf "${RELEASE_DIR}/plugins/jetpack" "${RELEASE_DIR}/plugins/akismet"

	for dir in ./*/
	do
		base=$(basename "$dir")
		echo "Syncing Plugin: $base"
		rsync -arxW --inplace --delete "$dir" "${PUBLIC_DIR}/wp-content/plugins/$base"
	done
else
	echo "::error::❌ Plugins directory not found at ${RELEASE_DIR}/plugins/"
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
else
	echo "::error::❌ Themes directory not found at ${RELEASE_DIR}/themes/"
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

# Remove any stale extracted release folders other than the current one
subdircount=$(find ./ -maxdepth 1 -type d | wc -l)
if [[ "$subdircount" -gt 1 ]]; then
  find . -maxdepth 1 -type d ! -name "release" ! -name . -exec rm -r {} \;
fi

cd "$PUBLIC_DIR"

# Flush the page cache when the command exists
if wp cli has-command page-cache 2>/dev/null; then
    wp page-cache flush
fi

echo "::notice::ℹ︎ Release sync complete"
