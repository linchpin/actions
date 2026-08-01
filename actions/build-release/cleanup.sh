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

# Remote plugin install: the server resolves third-party plugins and themes from
# composer.lock itself (see actions/remote-plugin-install), so the lock has to
# ship and the packages it covers must not. Dropping them is where this mode pays
# for itself — vendor-installed plugins are the bulk of a release, and a release
# that carries only the project's own code transfers, stores and syncs in a
# fraction of the time.
if [ "$REMOTE_PLUGIN_INSTALL" = "true" ]; then
  echo "Keeping composer.json/composer.lock in the release for remote plugin install"
  sed -i '/composer.json\|composer.lock/d' "$EXCLUDES"

  LOCK="$SRC/composer.lock"
  if [ ! -f "$LOCK" ]; then
    echo "::error::REMOTE_PLUGIN_INSTALL is true but no composer.lock was found at $LOCK"
    exit 1
  fi

  # Only packages that actually have a dist archive: WP-CLI installs from a zip
  # URL, so a source-only requirement (typically a dev-* VCS branch) has nothing
  # to install from and must keep travelling in the release instead.
  excluded_packages=0
  while IFS=$'\t' read -r name type; do
    slug="${name##*/}"
    case "$type" in
      wordpress-plugin) printf '/plugins/%s/\n' "$slug" >> "$EXCLUDES" ;;
      wordpress-theme) printf '/themes/%s/\n' "$slug" >> "$EXCLUDES" ;;
      *) continue ;;
    esac
    excluded_packages=$((excluded_packages + 1))
  done < <(jq -r '
    .packages[]
    | select((.type == "wordpress-plugin" or .type == "wordpress-theme")
             and (.dist.url // "") != "")
    | [.name, .type]
    | @tsv
  ' "$LOCK")

  echo "Excluding $excluded_packages Composer-managed package(s) — the server installs these from composer.lock"

  # Note: this mode does not run the root Composer install on the runner either,
  # so there is no root vendor/ to ship and nothing creates one on the server.
  # It suits the per-plugin autoloader layout Pressable's Composer guide
  # recommends (each plugin requires its own vendor/autoload.php); a project that
  # depends on a ROOT autoloader should not use REMOTE_PLUGIN_INSTALL.
fi

# Never ship these, regardless of what the project .distignore says.
printf '%s\n' ".git" ".github" "node_modules/" "auth.json" "$DEST" >> "$EXCLUDES"

echo "➤ Copying files from $SRC to $DEST"
rsync -rcq --exclude-from="$EXCLUDES" "$SRC/" "$DEST/" --delete
rm -f "$EXCLUDES"

echo "Release size: $(du -sh "$DEST" | cut -f1)"
echo "Release top-level contents:"
find "$DEST" -maxdepth 2 -type d | sort | head -40
