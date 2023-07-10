#!/bin/bash

# Default shell script used when deploying to WP Engine unless provided within the project directly.
# This shell script will take the following actions:
# 1. Sync from the _wpeprivate folder to the public directory
# 2. Backup the database
# 3. Cleanup any older releases

# Shared variables for bash scripts.
export DEPLOYMENT_DIR=$(pwd)
export RELEASE_DIR="$(dirname "$DEPLOYMENT_DIR")"
export RELEASES_DIR="$(dirname "$RELEASE_DIR")"
export PRIVATE_DIR="$(dirname "$RELEASES_DIR")"
export PUBLIC_DIR="$(dirname "$PRIVATE_DIR")"

cd "$PUBLIC_DIR"

# Start maintenance mode
echo "Starting Maintenance Mode"

wget -O maintenance.php https://raw.githubusercontent.com/linchpin/actions/main/maintenance.php
wp maintenance-mode activate

## echo "::notice::ℹ︎ Exporting Database"

# wp db export --path="$PUBLIC_DIR" - | gzip > "$RELEASES_DIR/db_backup.sql.gz"

## echo "::notice::ℹ︎ Exporting Complete"

cd "$RELEASE_DIR"

# rsync latest release to the public folder.
rsync -arxW --inplace --delete ${RELEASE_DIR}/plugins/. ${PUBLIC_DIR}/wp-content/plugins
rsync -arxW --inplace --delete ${RELEASE_DIR}/themes/. ${PUBLIC_DIR}/wp-content/themes

# Only sync MU Plugins if we have them
if [[ -d "${RELEASE_DIR}/mu-plugins/" ]]; then
  rsync -arxW --inplace --delete --exclude-from=".distignore" ${RELEASE_DIR}/mu-plugins/. ${PUBLIC_DIR}/wp-content/mu-plugins
fi

if [[ ! -f "${RELEASE_DIR}/.distignore" ]]; then
  echo "::warning::ℹ︎ Loading default .distignore from github.com/linchpin/actions, you should add one to your project"
  wget -O .distignore https://raw.githubusercontent.com/linchpin/actions/main/default.distignore
fi;

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
