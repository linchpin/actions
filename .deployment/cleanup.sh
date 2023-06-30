#!/bin/bash

# This script is used to clean up any files that should not deploy to the server
# It utilizes the default.distignore unless the project provides its own

set -eo

TMP_DIR="$GITHUB_WORKSPACE/temp_archive"
mkdir "$TMP_DIR"

cd "$GITHUB_WORKSPACE/build"

# If there's no .distignore file, write a default one into place
if [ ! -e "$GITHUB_WORKSPACE/build/.distignore" ]; then
  echo "::warning::ℹ︎ Loading default .distignore from github.com/linchpin/actions, you should add one to your project"
  wget -O .distignore https://raw.githubusercontent.com/linchpin/actions/main/default.distignore
fi;

# $1 = the GitHub action input remote_plugin_install
# If we are remotely installing plugins, we need to use the composer files to know what plugins to install/update
# When installing via composer these files are not needed in the deployment
if [ "$1" == "true" ]; then
  sed -i '/composer.json\|composer.lock/d' .distignore
fi;

echo "➤ Copying files to $TMP_DIR"

# This will exclude everything in the .distignore file with the export-ignore flag
rsync -rcq --progress --exclude-from="$GITHUB_WORKSPACE/build/.distignore" "$GITHUB_WORKSPACE/build/" "$TMP_DIR/" --delete
