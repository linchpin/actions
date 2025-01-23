#!/bin/bash

# Default shell script used when deploying to Pressable unless provided within the project directly.
# This shell script will take the following actions:
# 1. Sync from the /tmp/release/ folder to the public directory
# 2. Backup the database
# 3. Cleanup any older releases

release_folder_name=$1 # data/timestamp release folder name

# Shared variables for bash scripts.
export RELEASES_DIR=$(pwd) # releases
export PRIVATE_DIR="$(dirname "$RELEASES_DIR")"
export PUBLIC_DIR="/srv/htdocs"
export RELEASE_DIR="$RELEASES_DIR/release" # release

echo "Private: $PRIVATE_DIR"
echo "Releases: $RELEASES_DIR"
echo "Release: $RELEASE_DIR"
echo "Public: $PUBLIC_DIR"

# Every release should be cleaned up before we start
# If it exists, delete it
if [ -d "$RELEASE_DIR" ]; then
    rm -rf "$RELEASE_DIR"
fi

# Unzip the release

if [ ! -f "$RELEASES_DIR/$release_folder_name.zip" ]; then
	echo "::error::❌ Release zip not found at $RELEASES_DIR/$release_folder_name.zip"
	exit 1
else 
	echo "::notice::ℹ︎ Release zip found at $RELEASES_DIR/$release_folder_name.zip"

	# Make sure both the zip file and the directory we created have the proper permissions
	chmod a+r "$RELEASES_DIR/$release_folder_name.zip"
	chmod g+wx "$RELEASES_DIR"
	unzip -o -q -d "$RELEASE_DIR" "$RELEASES_DIR/$release_folder_name.zip"
fi

# Sync Plugins
if [[ -d "${RELEASE_DIR}/plugins/" ]]; then

	cd "$RELEASE_DIR/plugins"

	# On pressable, jetpack is managed by the platform
 	if [[ -d "${RELEASE_DIR}/plugins/jetpack" ]]; then
  		rm -rf "${RELEASE_DIR}/plugins/jetpack"
  	fi

	# On pressable, akismet is managed by the platform
    	if [[ -d "${RELEASE_DIR}/plugins/akismet" ]]; then
  		rm -rf "${RELEASE_DIR}/plugins/akismet"
  	fi

	for dir in ./*/
	do
		base=$(basename "$dir")
		echo "Syncing Plugin $base"
		rsync -arxW --inplace --delete "$dir" "${PUBLIC_DIR}/wp-content/plugins/$base"
	done
else
	echo "::error::❌ Plugins directory not found at ${RELEASE_DIR}/plugins/ not found"
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
	echo "::error::❌ Themes directory not found at ${RELEASE_DIR}/plugins/ not found"
fi

# Only sync MU Plugins if we have them
if [[ -d "${RELEASE_DIR}/mu-plugins/" ]]; then

	# This may no longer be needed
	if [[ ! -f "${RELEASE_DIR}/.distignore" ]]; then
		echo "::warning::ℹ︎ Loading default .distignore from github.com/linchpin/actions, you should add one to your project"
		wget -O .distignore https://raw.githubusercontent.com/linchpin/actions/v3/default.distignore
	fi;

	rsync -arxW --inplace --delete --exclude-from=".distignore" ${RELEASE_DIR}/mu-plugins/. ${PUBLIC_DIR}/wp-content/mu-plugins
fi

# Final cleanup within the releases directory: Only keep the latest release zip

cd "$RELEASES_DIR"

# check for any zip files all but the newest

if [[ -f ./*.zip ]]; then
  echo "ℹ︎ Found old release zips. Removing all but the newest..."
  ls -t *.zip | awk 'NR>2' | xargs rm -f
fi

# Scan for release sub directories and remove them if we have any
subdircount=$(find ./ -maxdepth 1 -type d | wc -l)

if [[ "$subdircount" -gt 1 ]]; then
  echo "ℹ︎ Delete all old release folders"
  find -maxdepth 1 ! -name "release" ! -name . -exec rm -rv {} \;
fi

cd "$PUBLIC_DIR"

# End maintenance mode, reset 

echo "::notice::ℹ︎ Maintenance Complete::"

# Check if the WP-CLI command exists
if wp cli has-command page-cache; then
    wp page-cache flush
fi

echo "::notice::ℹ︎ Maintenance Mode Removed::"
