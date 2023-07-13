#!/bin/bash

# Default shell script used when deploying to WP Engine unless provided within the project directly.
# This shell script will take the following actions:
# 1. Sync from the _wpeprivate folder to the public directory
# 2. Backup the database
# 3. Cleanup any older releases

release_folder_name=$1 # data/timestamp release folder name

# Shared variables for bash scripts.
export PRIVATE_DIR=$(pwd) # _wpeprivate
export RELEASES_DIR="$DEPLOYMENT_DIR/releases"	# releases
export RELEASE_DIR="$RELEASES_DIR/release" # release
export PUBLIC_DIR="$(dirname "$PRIVATE_DIR")"

# Maintenance Mode Flag (Commented out for now)
# cd "$PUBLIC_DIR"
# Start maintenance mode
# echo "Starting Maintenance Mode"
# wget -O maintenance.php https://raw.githubusercontent.com/linchpin/actions/v2/maintenance.php
# wp maintenance-mode activate

# Every release should be cleaned up before we start
# If it exists, delete it
if [ -d "$RELEASE_DIR" ]; then
    rm -rf "$RELEASE_DIR"
fi

mkdir -p "$RELEASE_DIR/.deployment"

// Unzip the release
unzip -o -q "$PRIVATE_DIR/$release_folder_name.zip -d $PRIVATE_DIR"

## echo "::notice::ℹ︎ Exporting Database"

# wp db export --path="$PUBLIC_DIR" - | gzip > "$RELEASES_DIR/db_backup.sql.gz"

## echo "::notice::ℹ︎ Exporting Complete"

cd "$RELEASE_DIR"

# rsync latest release to the public folder.

for dir in ./plugins/*/
do
    base=$(basename "$dir")
	echo "Syncing Plugin $base"
    rsync -arxW --inplace --delete "$dir" "${PUBLIC_DIR}/wp-content/plugins/$base"
done

for dir in ./themes/*/
do
    base=$(basename "$dir")
	echo "Syncing Theme: $base"
    rsync -arxW --inplace --delete "$dir" "${PUBLIC_DIR}/wp-content/themes/$base"
done

# Only sync MU Plugins if we have them
if [[ -d "${RELEASE_DIR}/mu-plugins/" ]]; then

	# This may no longer be needed
	if [[ ! -f "${RELEASE_DIR}/.distignore" ]]; then
		echo "::warning::ℹ︎ Loading default .distignore from github.com/linchpin/actions, you should add one to your project"
		wget -O .distignore https://raw.githubusercontent.com/linchpin/actions/v2/default.distignore
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

# Check for any .gz files and remove them
if [[ -f ./*.gz ]]; then
  echo "ℹ︎ Found old tar.gz files. Removing all..."
  ls -t *.gz | xargs rm -f
fi

# Scan for release sub directories and remove them if we have any
subdircount=$(find ./ -maxdepth 1 -type d | wc -l)

if [[ "$subdircount" -gt 1 ]]; then
  echo "ℹ︎ Delete all old release folders"
  find -maxdepth 1 ! -name "release" ! -name . -exec rm -rv {} \;
fi
