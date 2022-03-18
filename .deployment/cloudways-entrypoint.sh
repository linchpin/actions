#!/bin/bash

# Default shell script used when deploying to Cloudways unless provided within the project directly.
# This shell script will take the following actions:
# 1. Sync from the _wpeprivate folder to the public directory
# 2. Backup the database
# 3. Cleanup any older releases

# Shared variables for bash scripts.
export DEPLOYMENT_DIR=$(pwd)
export RELEASE_DIR="$(dirname "$DEPLOYMENT_DIR")"
export RELEASES_DIR="$(dirname "$RELEASE_DIR")"
export PUBLIC_DIR="$(dirname "$RELEASES_DIR")"

echo "$DEPLOYMENT_DIR"
echo "$RELEASE_DIR"
echo "$RELEASES_DIR"
echo "$PUBLIC_DIR"

cd "$PUBLIC_DIR"

wp db export --path="$PUBLIC_DIR" - | gzip > "$RELEASES_DIR/db_backup.sql.gz"

cd "$RELEASE_DIR"

# rsync latest release to public folder.
rsync -arxc --delete ${RELEASE_DIR}/plugins/. ${PUBLIC_DIR}/wp-content/plugins
rsync -arxc --delete ${RELEASE_DIR}/themes/. ${PUBLIC_DIR}/wp-content/themes

# Only sync MU Plugins if we have them
if [ -d "${RELEASE_DIR}/mu-plugins/" ] ; then

  if [ ! -e "${RELEASE_DIR}/.distignore" ]; then
    echo "::warning::ℹ︎ Loading default .distignore from github.com/linchpin/actions, you should add one to your project"
    wget -O .distignore https://raw.githubusercontent.com/linchpin/actions/main/default.distignore
  fi;

  rsync -rxc --delete --exclude-from=".distignore" ${RELEASE_DIR}/mu-plugins/. ${PUBLIC_DIR}/wp-content/mu-plugins
fi

# Final cleanup: Only keep the latest release zip

echo "Delete all old release zips"
cd "$RELEASES_DIR"

rm `ls -t *.zip | awk 'NR>2'`

echo "Delete all old release folders"
find -maxdepth 1 ! -name "release" ! -name . -exec rm -rv {} \;
