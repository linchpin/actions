#!/bin/bash

# Default shell script used when deploying to WP Engine unless provided within the project directly.
# This shell script will take the following actions:

# This file ends maintenance and is one of the last commands run upon deployment completion

# Shared variables for bash scripts.
export DEPLOYMENT_DIR=$(pwd)
export RELEASE_DIR="$(dirname "$DEPLOYMENT_DIR")"
export RELEASES_DIR="$(dirname "$RELEASE_DIR")"
export PRIVATE_DIR="$(dirname "$RELEASES_DIR")"
export PUBLIC_DIR="$(dirname "$PRIVATE_DIR")"

cd "$PUBLIC_DIR"

# End maintenance mode, reset 

echo "::notice::ℹ︎ Maintenance Complete::"

MAINTENANCE_FILE="./maintenance.php"

if [[ -e $FILE ]]; then
  rm MAINTENANCE_FILE
fi

if wp maintenance-mode is-active; then
  wp maintenance-mode deactivate
  echo "::notice::ℹ︎ Maintenance Mode Removed::"
fi
