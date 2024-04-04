#!/bin/bash

# Default shell script used when deploying to Cloudways unless provided within the project directly.
# This shell script will take the following actions:
# 1. Sync from the _wpeprivate folder to the public directory
# 2. Backup the database
# 3. Cleanup any older releases

# Shared variables for bash scripts.
export DEPLOYMENT_DIR=$(pwd)

    echo "::warning::ℹ︎ $DEPLOYMENT_DIR"

export RELEASE_DIR="$(dirname "$DEPLOYMENT_DIR")"

    echo "::warning::ℹ︎ $RELEASE_DIR"

export RELEASES_DIR="$(dirname "$RELEASE_DIR")"

    echo "::warning::ℹ︎ $RELEASES_DIR"
export PRIVATE_DIR="$(dirname "$RELEASES_DIR")"

    echo "::warning::ℹ︎ $PRIVATE_DIR"
export PUBLIC_DIR="$(dirname "$PRIVATE_DIR")/public_html/"

    echo "::warning::ℹ︎ $PUBLIC_DIR"

cd "$PUBLIC_DIR"

# Start maintenance mode

wget -O maintenance.php https://raw.githubusercontent.com/linchpin/actions/main/maintenance.php
wp maintenance-mode activate

# Backup our database
# wp db export --path="$PUBLIC_DIR" - | gzip > "$RELEASES_DIR/db_backup.sql.gz"

# Cleanup symlinks (from legacy deployment process)

cd "$PUBLIC_DIR/wp-content"

if [ -L "$PUBLIC_DIR/wp-content/plugins" ]; then
  unlink plugins
fi

if [ -L "$PUBLIC_DIR/wp-content/themes" ]; then
  unlink themes
fi

if [ -L "$PUBLIC_DIR/wp-content/mu-plugins" ]; then
  unlink mu-plugins
fi

if [ -f "$PUBLIC_DIR/wp-content/themes" ]; then
    rm -rf "$PUBLIC_DIR/wp-content/themes"
fi

if [ -f "$PUBLIC_DIR/wp-content/plugins" ]; then
    rm -rf "$PUBLIC_DIR/wp-content/plugins"
fi

if [ -f "$PUBLIC_DIR/wp-content/mu-plugins" ]; then
    rm -rf "$PUBLIC_DIR/wp-content/mu-plugins"
fi

# End symlink cleanup

cd "$RELEASE_DIR"

# rsync latest release to public folder.
rsync -arxcO --delete ${RELEASE_DIR}/plugins/. ${PUBLIC_DIR}/wp-content/plugins
rsync -arxcO --delete ${RELEASE_DIR}/themes/. ${PUBLIC_DIR}/wp-content/themes

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

cd "$PUBLIC_DIR"

# End maintenance mode, reset 

rm maintenance.php

# Check if the WP-CLI command exists
if wp cli has-command redis flush; then
    wp redis enable --force
    wp redis flush
    wp flush cache
fi

wp maintenance-mode deactivate
