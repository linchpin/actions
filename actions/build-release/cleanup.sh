#!/bin/bash

# v4 of .deployment/cleanup.sh (previously wget'd from the v3 branch at run time).
# Copies a built project tree into a clean release directory, excluding
# everything listed in the project .distignore (or the bundled default).
#
# Args:
#   $1  source directory (default ".")
#   $2  target directory (default "release")
#   $3  remote plugin install flag — "true" keeps composer.json/composer.lock
#   $4  path to the bundled default.distignore fallback

set -euo pipefail

SRC="${1:-.}"
DEST="${2:-release}"
REMOTE_PLUGIN_INSTALL="${3:-false}"
DEFAULT_DISTIGNORE="${4:?path to default.distignore is required}"

mkdir -p "$DEST"

DISTIGNORE="$SRC/.distignore"
if [ ! -f "$DISTIGNORE" ]; then
  echo "::warning::No .distignore found in the project — using the bundled default. Add one to your project."
  DISTIGNORE="$DEFAULT_DISTIGNORE"
fi

EXCLUDES="$(mktemp)"
cp "$DISTIGNORE" "$EXCLUDES"

# When installing plugins remotely the server needs the composer files,
# so remove them from the exclude list.
if [ "$REMOTE_PLUGIN_INSTALL" = "true" ]; then
  echo "Keeping composer.json/composer.lock in the release for remote plugin install"
  sed -i '/composer.json\|composer.lock/d' "$EXCLUDES"
fi

# Never ship these, regardless of what the project .distignore says.
printf '%s\n' ".git" ".github" "node_modules/" "auth.json" "$DEST" >> "$EXCLUDES"

echo "➤ Copying files from $SRC to $DEST"
rsync -rcq --exclude-from="$EXCLUDES" "$SRC/" "$DEST/" --delete
rm -f "$EXCLUDES"

echo "Release size: $(du -sh "$DEST" | cut -f1)"
echo "Release top-level contents:"
find "$DEST" -maxdepth 2 -type d | sort | head -40
