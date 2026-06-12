#!/bin/bash

# v4 of .deployment/cloudways-entrypoint.sh. Runs ON THE CLOUDWAYS SERVER from
# <deployment_path>/release/.deployment. Previously wget'd from the v3 branch
# at deploy time (along with maintenance.php); in v4 both are uploaded by the
# deploy-cloudways composite action.
#
# Steps:
# 1. Enable maintenance mode (bundled maintenance.php)
# 2. Clean up legacy symlinks, sync plugins/themes/mu-plugins to public_html
# 3. Keep only the newest release zips, remove old release folders
# 4. Disable maintenance mode, flush redis/object caches when available

set -uo pipefail

# Directory layout (derived from pwd = <releases>/release/.deployment):
export DEPLOYMENT_DIR=$(pwd)
export RELEASE_DIR="$(dirname "$DEPLOYMENT_DIR")"
export RELEASES_DIR="$(dirname "$RELEASE_DIR")"
export PRIVATE_DIR="$(dirname "$RELEASES_DIR")"
export PUBLIC_DIR="$(dirname "$PRIVATE_DIR")/public_html"

echo "Release:  $RELEASE_DIR"
echo "Releases: $RELEASES_DIR"
echo "Public:   $PUBLIC_DIR"

if [ ! -d "$PUBLIC_DIR" ]; then
  echo "::error::❌ Public directory not found at $PUBLIC_DIR"
  exit 1
fi

cd "$PUBLIC_DIR"

# Start maintenance mode (maintenance.php ships with the deploy action)
cp "$DEPLOYMENT_DIR/maintenance.php" "$PUBLIC_DIR/maintenance.php"
wp maintenance-mode activate 2>/dev/null || true

# Cleanup symlinks (from the legacy deployment process)
for legacy in themes plugins mu-plugins; do
  if [ -L "$PUBLIC_DIR/wp-content/$legacy" ]; then
    rm -rf "$PUBLIC_DIR/wp-content/$legacy"
  fi
done

# Sync the release into the public folder
rsync -arxcO --delete --no-perms --no-times "${RELEASE_DIR}/plugins/." "${PUBLIC_DIR}/wp-content/plugins"
rsync -arxcO --delete --no-perms --no-times "${RELEASE_DIR}/themes/." "${PUBLIC_DIR}/wp-content/themes"

# Sync MU Plugins when present.
# v4 change: no .distignore filtering here — the release was already cleaned
# by the build-release action before it was zipped.
if [ -d "${RELEASE_DIR}/mu-plugins/" ]; then
  rsync -rxc --delete "${RELEASE_DIR}/mu-plugins/." "${PUBLIC_DIR}/wp-content/mu-plugins"
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

echo "::notice::ℹ︎ Release sync complete"
